import Foundation

/// 서비스에서 받아 온 실제 사용량
struct LiveResult: Sendable {
    var windows: [UsageWindow]
    var plan: String?
    var message: String
}

enum ProviderError: LocalizedError {
    case noCredentials(String)
    case expired(String)
    case http(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noCredentials(let s): return s
        case .expired(let s): return s
        case .http(401), .http(403): return "인증 거부 (다시 로그인 필요)"
        case .http(429): return "요청이 많아 잠시 제한됨"
        case .http(let c): return "서버 응답 오류 \(c)"
        case .unreadable: return "응답 형식을 읽지 못함"
        }
    }
}

private let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 15
    c.httpCookieStorage = nil
    return URLSession(configuration: c)
}()

private func parseISO(_ any: Any?) -> Date? {
    if let s = any as? String { return LocalUsageReader.parseDate(s) }
    if let n = any as? NSNumber {
        let v = n.doubleValue
        return Date(timeIntervalSince1970: v > 10_000_000_000 ? v / 1000 : v)
    }
    return nil
}

private func number(_ any: Any?) -> Double? {
    if let n = any as? NSNumber { return n.doubleValue }
    if let s = any as? String { return Double(s) }
    return nil
}

// MARK: - Claude

/// Claude Code 가 로그인할 때 저장한 OAuth 토큰으로 계정 사용량(/usage 와 같은 값)을 조회한다.
/// 토큰은 macOS 키체인 'Claude Code-credentials' 또는 ~/.claude/.credentials.json 에서 읽기만 하며,
/// api.anthropic.com 외에는 어디에도 보내지 않는다.
enum ClaudeAPI {
    struct Credentials { var token: String; var expiresAt: Date?; var plan: String? }

    static func readCredentials() throws -> Credentials {
        var raw: Data?
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let d = try? Data(contentsOf: file) { raw = d }
        if raw == nil { raw = keychain(service: "Claude Code-credentials") }
        guard let data = raw,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw ProviderError.noCredentials("Claude Code 로그인 정보 없음 — 터미널에서 claude 로그인")
        }
        let exp = number(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) }
        return Credentials(token: token, expiresAt: exp, plan: oauth["subscriptionType"] as? String)
    }

    /// 키체인 접근은 /usr/bin/security 를 통해 한다.
    /// (처음 한 번 '항상 허용' 하면 앱을 업데이트해도 다시 묻지 않음)
    static func keychain(service: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Data(trimmed.utf8)
    }

    static func fetch() async throws -> LiveResult {
        let cred = try readCredentials()
        if let exp = cred.expiresAt, exp < Date() {
            throw ProviderError.expired("로그인 토큰 만료 — 터미널에서 claude 를 한 번 실행하세요")
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(cred.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("SubDash/2.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ProviderError.http(code) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.unreadable
        }

        let spec: [(String, String, Bool)] = [
            ("five_hour", "5시간 세션", false),
            ("seven_day", "전체 모델", true),
            ("seven_day_opus", "Opus", true),
            ("seven_day_sonnet", "Sonnet", true),
            ("seven_day_oauth_apps", "연결 앱", true),
        ]
        var windows: [UsageWindow] = []
        for (key, title, weekly) in spec {
            guard let w = obj[key] as? [String: Any], let pct = number(w["utilization"]) else { continue }
            windows.append(UsageWindow(id: key, title: title, percent: pct,
                                       resetsAt: parseISO(w["resets_at"]), isWeekly: weekly))
        }
        if let extra = obj["extra_usage"] as? [String: Any], extra["is_enabled"] as? Bool == true,
           let pct = number(extra["utilization"]) {
            windows.append(UsageWindow(id: "extra_usage", title: "추가 사용량", percent: pct,
                                       resetsAt: nil, isWeekly: true))
        }
        guard !windows.isEmpty else { throw ProviderError.unreadable }
        return LiveResult(windows: windows, plan: cred.plan.map { $0.capitalized },
                          message: "Claude 계정 연결됨")
    }
}

// MARK: - ChatGPT / Codex

/// Codex CLI 로그인 정보(~/.codex/auth.json)로 ChatGPT 계정의 Codex 사용 한도를 조회한다.
enum CodexAPI {
    static func fetch() async throws -> LiveResult {
        var home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"] { home = URL(fileURLWithPath: custom) }
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty else {
            throw ProviderError.noCredentials("Codex 로그인 정보 없음 — 터미널에서 codex login")
        }

        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let acc = tokens["account_id"] as? String { req.setValue(acc, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("SubDash/2.0", forHTTPHeaderField: "User-Agent")

        let (body, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ProviderError.http(code) }
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw ProviderError.unreadable
        }

        let rl = (json["rate_limit"] as? [String: Any]) ?? json
        func window(_ key: String, _ title: String, weekly: Bool) -> UsageWindow? {
            guard let w = rl[key] as? [String: Any], let pct = number(w["used_percent"]) else { return nil }
            var reset = parseISO(w["reset_at"])
            if reset == nil, let s = number(w["reset_after_seconds"]) { reset = Date().addingTimeInterval(s) }
            return UsageWindow(id: key, title: title, percent: pct, resetsAt: reset, isWeekly: weekly)
        }
        let windows = [window("primary_window", "5시간 세션", weekly: false),
                       window("secondary_window", "전체", weekly: true)].compactMap { $0 }
        guard !windows.isEmpty else { throw ProviderError.unreadable }
        let plan = (json["plan_type"] as? String).map { $0.capitalized }
        return LiveResult(windows: windows, plan: plan, message: "ChatGPT 계정 연결됨")
    }
}
