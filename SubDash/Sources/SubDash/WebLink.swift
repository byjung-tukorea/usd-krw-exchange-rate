import SwiftUI
import WebKit

/// 공개 사용량 API 가 없는 서비스(Lovable, Genspark, Gemini 등)를 위한 '웹 로그인' 연동.
/// 1) 앱 안의 로그인 창에서 사용자가 직접 로그인 → 로그인 상태는 서비스별 저장소에 유지
/// 2) 주기적으로 같은 저장소로 사용량 페이지를 화면 밖에서 열어 글자를 읽고 숫자를 찾는다
/// 비밀번호는 앱이 보거나 저장하지 않는다 (WebKit 쿠키만 유지).
enum WebLink {
    static func defaultHome(for name: String) -> URL {
        let n = name.lowercased()
        if n.contains("lovable") { return URL(string: "https://lovable.dev/")! }
        if n.contains("genspark") { return URL(string: "https://www.genspark.ai/")! }
        if n.contains("gemini") || n.contains("google") { return URL(string: "https://one.google.com/")! }
        return URL(string: "https://www.google.com/")!
    }

    static func usageURL(for s: Subscription) -> URL {
        if let u = s.webURL, let url = URL(string: u) { return url }
        return defaultHome(for: s.name)
    }

    @MainActor
    static func configuration(for id: UUID) -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)   // 서비스마다 따로 로그인 유지
        return c
    }

    @MainActor
    static func signOut(id: UUID) async {
        let store = WKWebsiteDataStore(forIdentifier: id)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}

// MARK: - 페이지 읽기 (화면 밖 WebView)

@MainActor
final class WebScraper: NSObject, WKNavigationDelegate {
    struct Page { var text: String; var finalURL: URL? }
    enum ScrapeError: LocalizedError {
        case timeout
        var errorDescription: String? { "페이지 응답 없음 (시간 초과)" }
    }

    private var webView: WKWebView?
    private var waiting: CheckedContinuation<Void, Error>?

    func read(_ url: URL, id: UUID) async throws -> Page {
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900),
                           configuration: WebLink.configuration(for: id))
        wv.navigationDelegate = self
        webView = wv
        defer { webView = nil; waiting = nil }

        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.finish(ScrapeError.timeout)
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            waiting = c
            wv.load(URLRequest(url: url))
        }
        timeout.cancel()

        // 앱 화면(SPA)이 그려질 때까지 글자가 안정되길 기다림 (최대 12초)
        var last = ""
        var text = ""
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            text = (try? await wv.evaluateJavaScript("document.body ? document.body.innerText : ''") as? String) ?? ""
            if text.count > 80, text == last { break }
            last = text
        }
        return Page(text: text, finalURL: wv.url)
    }

    private func finish(_ error: Error?) {
        guard let c = waiting else { return }
        waiting = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }
}

// MARK: - 글자에서 사용량 찾기

struct WebReading {
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var renewal: Date?
    var evidence: String?
    var loggedOut = false

    var hasUsage: Bool { remaining != nil || used != nil }
}

enum WebUsageParser {
    private static let unit = #"(?:credits?|크레딧|points?|포인트|messages?|메시지)"#
    private static let num = #"(\d[\d,]*(?:\.\d+)?)"#

    private static func value(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "")) }

    private static func match(_ pattern: String, in line: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { i in
            Range(m.range(at: i), in: line).map { String(line[$0]) }
        }
    }

    private static let remainingWords = #"remaining|left|available|남은|남음|잔여|사용 가능"#
    private static let usedWords = #"used|spent|consumed|사용함|사용량|사용됨"#

    static func parse(_ text: String, finalURL: URL?) -> WebReading {
        var r = WebReading()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 로그인 페이지로 돌아갔는지
        if let u = finalURL {
            let s = (u.host ?? "") + u.path
            if s.contains("accounts.google.com") || s.range(of: #"/(login|signin|sign-in|sign_in|auth)"#,
                                                               options: .regularExpression) != nil {
                r.loggedOut = true
            }
        }

        // 한 줄 또는 이어진 두 줄을 합쳐서 검사 ("Credits" / "85 / 100" 처럼 나뉜 경우)
        var candidates: [String] = lines
        for i in 0..<max(lines.count - 1, 0) { candidates.append(lines[i] + " " + lines[i + 1]) }

        for line in candidates where !r.hasUsage {
            let lower = line.lowercased()
            let mentionsRemaining = lower.range(of: remainingWords, options: .regularExpression) != nil
            let mentionsUsed = lower.range(of: usedWords, options: .regularExpression) != nil

            // "85 / 100 credits", "85 of 100 credits left"
            if let g = match(num + #"\s*(?:/|of|out of)\s*"# + num + #"\s*"# + unit, in: line)
                ?? (lower.range(of: unit, options: .regularExpression) != nil
                    ? match(num + #"\s*(?:/|of|out of)\s*"# + num, in: line) : nil),
               g.count == 2, let a = value(g[0]), let b = value(g[1]), b > 0, a <= b * 1.0001 {
                r.limit = b
                if mentionsUsed && !mentionsRemaining { r.used = a } else { r.remaining = a }
                r.evidence = line
                continue
            }
            // "1,234 credits remaining"
            if mentionsRemaining, let g = match(num + #"\s*"# + unit, in: line), let a = value(g[0]) {
                r.remaining = a; r.evidence = line; continue
            }
            // "Remaining credits: 1,234"
            if mentionsRemaining, let g = match("(?:" + remainingWords + #")\s*"# + unit + #"?\s*[:：]?\s*"# + num, in: line),
               let a = value(g[0]) {
                r.remaining = a; r.evidence = line; continue
            }
        }

        // 다음 결제일 / 갱신일
        let billingWords = #"renew|next billing|billing date|next payment|next charge|결제일|갱신|다음 결제|청구"#
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            for (i, line) in lines.enumerated()
            where line.lowercased().range(of: billingWords, options: .regularExpression) != nil {
                let probe = line + " " + (i + 1 < lines.count ? lines[i + 1] : "")
                let found = detector.matches(in: probe, range: NSRange(probe.startIndex..., in: probe))
                    .compactMap(\.date)
                    .filter { $0 > Date().addingTimeInterval(-86_400) }
                if let d = found.first { r.renewal = d; break }
            }
        }

        if r.hasUsage || r.renewal != nil { r.loggedOut = false }
        return r
    }
}

// MARK: - 로그인 창

@MainActor
final class WebLoginModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var url: URL?
    @Published var loading = false
    @Published var canGoBack = false
    private var popups: [NSWindow] = []

    init(id: UUID, start: URL) {
        webView = WKWebView(frame: .zero, configuration: WebLink.configuration(for: id))
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: start))
    }

    private func refresh() {
        url = webView.url
        loading = webView.isLoading
        canGoBack = webView.canGoBack
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refresh() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh() }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refresh() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refresh() }

    /// 소셜 로그인 팝업(구글 등)은 별도 창으로 띄워 opener 관계를 유지
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        popup.uiDelegate = self
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                           styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = "로그인"
        win.contentView = popup
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        popups.append(win)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let w = popups.first(where: { $0.contentView === webView }) {
            w.close()
            popups.removeAll { $0 === w }
        }
        refresh()
        self.webView.reload()
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct WebLoginView: View {
    @EnvironmentObject var store: Store
    let id: UUID
    @StateObject private var model: WebLoginModel
    @State private var saved = false

    init(id: UUID, start: URL) {
        self.id = id
        _model = StateObject(wrappedValue: WebLoginModel(id: id, start: start))
    }

    private var sub: Subscription? { store.subs.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    IconButton(symbol: "chevron.left", size: 26, help: "뒤로") { model.webView.goBack() }
                        .disabled(!model.canGoBack)
                    IconButton(symbol: "arrow.clockwise", size: 26, help: "새로고침", spinning: model.loading) {
                        model.webView.reload()
                    }
                    Text(model.url?.absoluteString ?? "")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .inset(radius: 8, depth: 2)
                }
                HStack(spacing: 8) {
                    Text("① 로그인  ② 크레딧·결제일이 보이는 페이지로 이동  ③ 오른쪽 버튼")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Button {
                        guard var s = sub, let u = model.url else { return }
                        s.webURL = u.absoluteString
                        store.upsert(s)
                        saved = true
                        Task { await store.syncWeb(force: true, only: id) }
                    } label: {
                        Text(saved ? "✓ 지정됨" : "이 페이지에서 사용량 읽기")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .buttonStyle(NeuButtonStyle(radius: 9, prominent: true))
                    .disabled(model.url == nil)
                    Menu("⋯") {
                        Button("로그아웃 (이 서비스 로그인 정보 삭제)") {
                            Task {
                                await WebLink.signOut(id: id)
                                model.webView.load(URLRequest(url: WebLink.defaultHome(for: sub?.name ?? "")))
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if let s = sub, s.source == .webPage, let msg = s.liveMessage {
                    Label(msg, systemImage: s.state == .live ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(s.state == .live ? Theme.accent : Theme.inkSoft)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(Theme.bg)

            WebViewHost(webView: model.webView)
        }
        .frame(minWidth: 720, minHeight: 640)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .navigationTitle("\(sub?.name ?? "서비스") 로그인")
    }
}
