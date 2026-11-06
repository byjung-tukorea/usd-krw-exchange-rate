import Foundation
import SwiftUI

enum DisplayMode: String, CaseIterable, Identifiable {
    case used, remaining
    var id: String { rawValue }
    var label: String { self == .used ? "사용량" : "남은 양" }
}

enum ProviderKey: String { case claude, codex }

@MainActor
final class Store: ObservableObject {
    @Published var subs: [Subscription] = [] {
        didSet { if subs != oldValue { save() } }
    }
    @Published var lastSync: Date?
    @Published var isSyncing = false
    @Published var rateUpdatedAt: Date?
    /// 일별 사용량 (히트맵). 값은 0...1 강도
    @Published var daily: [ProviderKey: [Date: Double]] = [:]
    @Published var dailyIsPeak: [ProviderKey: Set<Date>] = [:]
    private var dailyComputedAt: Date?

    /// 앱이 기록한 날짜별 최대 5시간 사용률 (%)
    private var peaks: [String: [String: Double]] = [:]

    private var timer: Timer?

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    private let fileURL = Store.folder.appendingPathComponent("subscriptions.json")
    private let peaksURL = Store.folder.appendingPathComponent("peaks.json")

    var usdKrw: Double {
        get { let v = UserDefaults.standard.double(forKey: "usdKrw"); return v > 0 ? v : 1400 }
        set { UserDefaults.standard.set(newValue, forKey: "usdKrw"); objectWillChange.send() }
    }

    init() {
        load()
        migrate()
        rollOverAll()
        startTimer()
        Task {
            await sync()
            await refreshRateIfNeeded()
            await refreshDaily()
        }
    }

    // MARK: 저장/불러오기

    private func load() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let list = try? dec.decode([Subscription].self, from: data) {
            subs = list
        } else {
            subs = Subscription.defaults
        }
        if let d = try? Data(contentsOf: peaksURL),
           let p = try? JSONDecoder().decode([String: [String: Double]].self, from: d) {
            peaks = p
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(subs) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 1.x 의 예시 값을 정리 (사용자가 바꾼 값은 건드리지 않음)
    private func migrate() {
        let key = "dataVersion"
        guard UserDefaults.standard.integer(forKey: key) < 2 else { return }
        var copy = subs
        for i in copy.indices {
            let s = copy[i]
            if s.source == .claudeCodeLogs {
                if s.name == "Claude Code" { copy[i].name = "Claude" }
                copy[i].limitUnit = .percent; copy[i].limit = 100; copy[i].used = 0
            }
            if s.name == "Lovable", s.used == 32 { copy[i].used = 0 }
            if s.name == "Genspark", s.used == 2_400 { copy[i].used = 0 }
            if s.name == "Gemini", s.used == 12, s.source == .manual {
                copy[i].used = 0; copy[i].source = .geminiCLI; copy[i].limit = 1_500
            }
            if s.renewalConfirmed == nil { copy[i].renewalConfirmed = false }
        }
        subs = copy
        UserDefaults.standard.set(2, forKey: key)
    }

    var dataFolder: URL { Store.folder }

    // MARK: 편집

    func upsert(_ s: Subscription) {
        if let i = subs.firstIndex(where: { $0.id == s.id }) { subs[i] = s } else { subs.append(s) }
    }

    func delete(_ s: Subscription) { subs.removeAll { $0.id == s.id } }

    func resetUsage(_ s: Subscription) {
        guard let i = subs.firstIndex(where: { $0.id == s.id }) else { return }
        subs[i].used = 0
        subs[i].lastReset = Date()
    }

    func adjust(_ s: Subscription, by delta: Double) {
        guard let i = subs.firstIndex(where: { $0.id == s.id }) else { return }
        subs[i].used = max(0, subs[i].used + delta)
    }

    func sub(for source: UsageSource) -> Subscription? { subs.first { $0.source == source } }

    // MARK: 요약

    var active: [Subscription] { subs.filter(\.isActive) }

    func activeSubs(_ f: AccountFilter) -> [Subscription] { active.filter { f.matches($0) } }

    var monthlyTotalKRW: Double { monthlyTotal(.all) }

    func monthlyTotal(_ f: AccountFilter) -> Double {
        activeSubs(f).reduce(0) { $0 + $1.monthlyCost(usdKrw: usdKrw) }
    }

    func nextRenewal(_ f: AccountFilter) -> Subscription? {
        activeSubs(f).filter(\.hasRenewal).min { $0.renewalDate < $1.renewalDate }
    }

    func liveCount(_ f: AccountFilter) -> (live: Int, total: Int) {
        let list = activeSubs(f)
        return (list.filter { $0.state == .live }.count, list.count)
    }

    // MARK: 동기화

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rollOverAll()
                if UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true {
                    await self.sync()
                }
                await self.refreshDaily()
            }
        }
    }

    func rollOverAll() {
        var copy = subs
        for i in copy.indices { copy[i].rollOver() }
        if copy != subs { subs = copy }
    }

    private enum Outcome: Sendable {
        case live(LiveResult)
        case fallback(UsageSnapshot, reason: String)
        case failed(String, UsageSnapshot?)
    }

    /// 모든 서비스의 실제 값을 가져온다. 실패하면 로컬 기록, 그것도 없으면 '연결 끊김'.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let targets = subs.filter { $0.source != .manual && $0.isActive }.map { ($0.id, $0.source) }
        var results: [UUID: Outcome] = [:]
        await withTaskGroup(of: (UUID, Outcome).self) { group in
            for (id, source) in targets {
                group.addTask {
                    let o = await Store.fetch(source)
                    return (id, o)
                }
            }
            for await (id, outcome) in group { results[id] = outcome }
        }

        let now = Date()
        var copy = subs
        for i in copy.indices {
            guard let outcome = results[copy[i].id] else { continue }
            switch outcome {
            case .live(let r):
                copy[i].windows = r.windows
                copy[i].used = r.windows.first?.percent ?? 0
                copy[i].limit = 100
                copy[i].limitUnit = .percent
                copy[i].syncedResetAt = r.windows.first?.resetsAt
                copy[i].liveState = .live
                copy[i].liveMessage = r.message
                copy[i].liveAt = now
                copy[i].detectedPlan = r.plan
                if let p = r.windows.first(where: { !$0.isWeekly }) {
                    recordPeak(copy[i].source == .claudeCodeLogs ? .claude : .codex, p.percent, now)
                }
            case .fallback(let snap, let reason):
                if !snap.windows.isEmpty {
                    copy[i].windows = snap.windows
                    copy[i].used = snap.windows.first?.percent ?? 0
                    copy[i].limit = 100
                } else if copy[i].source == .geminiCLI {
                    copy[i].windows = nil
                    copy[i].used = snap.used
                } else {
                    // Claude 로그는 % 를 알 수 없어 기존 창 값은 유지하고 설명만 갱신
                }
                copy[i].syncedResetAt = snap.resetAt
                copy[i].syncedDetail = snap.detail
                copy[i].liveState = .fallback
                copy[i].liveMessage = reason
                if copy[i].source == .geminiCLI { copy[i].liveAt = now }
            case .failed(let reason, let snap):
                copy[i].liveState = .failed
                copy[i].liveMessage = reason
                if let snap { copy[i].syncedDetail = snap.detail }
            }
        }
        if copy != subs { subs = copy }
        lastSync = now
    }

    private nonisolated static func fetch(_ source: UsageSource) async -> Outcome {
        switch source {
        case .claudeCodeLogs:
            do { return .live(try await ClaudeAPI.fetch()) }
            catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? "네트워크 연결 실패"
                return .failed(reason, LocalUsageReader.claudeUsage())
            }
        case .codexLogs:
            do { return .live(try await CodexAPI.fetch()) }
            catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? "네트워크 연결 실패"
                if let snap = LocalUsageReader.codexUsage(), !snap.windows.isEmpty {
                    return .fallback(snap, reason: "실시간 실패(\(reason)) · 로컬 기록 표시")
                }
                return .failed(reason, nil)
            }
        case .geminiCLI:
            if let snap = LocalUsageReader.geminiUsage() {
                return .fallback(snap, reason: "Gemini CLI 기록 기준 (웹·앱 사용 미포함)")
            }
            return .failed("Gemini 는 사용량 API 가 없어요 — Gemini CLI 기록도 없음", nil)
        case .manual:
            return .failed("", nil)
        }
    }

    // MARK: 일별 기록 (히트맵)

    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func recordPeak(_ p: ProviderKey, _ pct: Double, _ when: Date) {
        let k = Store.dayKey.string(from: when)
        var m = peaks[p.rawValue] ?? [:]
        if pct > (m[k] ?? -1) {
            m[k] = pct
            peaks[p.rawValue] = m
            if let d = try? JSONEncoder().encode(peaks) { try? d.write(to: peaksURL, options: .atomic) }
        }
    }

    func refreshDaily(force: Bool = false) async {
        if !force, let at = dailyComputedAt, Date().timeIntervalSince(at) < 20 * 60 { return }
        dailyComputedAt = Date()
        let days = 7 * 22
        let (claudeLog, codexLog) = await Task.detached(priority: .utility) {
            (LocalUsageReader.claudeDaily(days: days), LocalUsageReader.codexDaily(days: days))
        }.value

        for (key, logs) in [(ProviderKey.claude, claudeLog), (ProviderKey.codex, codexLog)] {
            var out: [Date: Double] = [:]
            var peakDays = Set<Date>()
            let maxTokens = logs.values.max() ?? 0
            for (day, tokens) in logs where maxTokens > 0 {
                out[day] = tokens / maxTokens          // 로그 토큰 상대 강도
            }
            for (k, pct) in peaks[key.rawValue] ?? [:] {
                guard let d = Store.dayKey.date(from: k) else { continue }
                let day = Calendar.current.startOfDay(for: d)
                out[day] = min(pct / 100, 1)          // 실제 5시간 최고 사용률이 있으면 우선
                peakDays.insert(day)
            }
            daily[key] = out
            dailyIsPeak[key] = peakDays
        }
    }

    // MARK: 환율 (open.er-api.com)

    func refreshRateIfNeeded(force: Bool = false) async {
        guard force || (UserDefaults.standard.object(forKey: "autoRate") as? Bool ?? true) else { return }
        let last = UserDefaults.standard.object(forKey: "rateFetchedAt") as? Date
        if !force, let last, Date().timeIntervalSince(last) < 6 * 3600 { rateUpdatedAt = last; return }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = obj["rates"] as? [String: Any],
               let krw = (rates["KRW"] as? NSNumber)?.doubleValue, krw > 0 {
                usdKrw = krw
                let now = Date()
                UserDefaults.standard.set(now, forKey: "rateFetchedAt")
                rateUpdatedAt = now
            }
        } catch {
            // 오프라인이면 마지막 값을 그대로 쓴다
        }
    }
}

// MARK: - 포맷 도우미

enum Fmt {
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        switch a {
        case 1_000_000_000...: return String(format: "%.1fB", v / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 10_000...: return String(format: "%.0fK", v / 1_000)
        case 1_000...: return String(format: "%.1fK", v / 1_000)
        default: return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        }
    }

    static func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    static func won(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "₩" + (f.string(from: NSNumber(value: v)) ?? "0")
    }

    static func price(_ s: Subscription) -> String {
        s.currency == .krw ? won(s.price) : String(format: "$%.2f", s.price)
    }

    static func countdown(to date: Date, now: Date = Date()) -> String {
        let sec = Int(date.timeIntervalSince(now))
        if sec <= 0 { return "곧 리셋" }
        let d = sec / 86_400, h = (sec % 86_400) / 3600, m = (sec % 3600) / 60
        if d > 0 { return "\(d)일 \(h)시간" }
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }

    /// "리셋 11월 12일 16:00 · 5일 11시간 남음"
    static func resetLine(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let when = cal.isDate(date, inSameDayAs: now) ? time(date) : "\(Fmt.date(date)) \(time(date))"
        return "리셋 \(when) · \(countdown(to: date, now: now)) 남음"
    }

    static func relative(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "\(max(s, 0))초 전" }
        if s < 3600 { return "\(s / 60)분 전" }
        if s < 86_400 { return "\(s / 3600)시간 전" }
        return "\(s / 86_400)일 전"
    }

    static func dday(_ n: Int) -> String {
        n == 0 ? "D-DAY" : (n > 0 ? "D-\(n)" : "D+\(-n)")
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M월 d일"
        return f.string(from: d)
    }
}
