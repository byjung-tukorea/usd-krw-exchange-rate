import Foundation
import SwiftUI

enum DisplayMode: String, CaseIterable, Identifiable {
    case used, remaining
    var id: String { rawValue }
    var label: String { self == .used ? "사용량" : "남은 양" }
}

@MainActor
final class Store: ObservableObject {
    @Published var subs: [Subscription] = [] {
        didSet { if subs != oldValue { save() } }
    }
    @Published var lastSync: Date?
    @Published var isSyncing = false
    @Published var rateUpdatedAt: Date?

    private var timer: Timer?

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("subscriptions.json")
    }()

    var usdKrw: Double {
        get { let v = UserDefaults.standard.double(forKey: "usdKrw"); return v > 0 ? v : 1400 }
        set { UserDefaults.standard.set(newValue, forKey: "usdKrw"); objectWillChange.send() }
    }

    init() {
        load()
        rollOverAll()
        startTimer()
        Task { await syncLocal(); await refreshRateIfNeeded() }
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
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(subs) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    var dataFolder: URL { fileURL.deletingLastPathComponent() }

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

    func move(from: IndexSet, to: Int) { subs.move(fromOffsets: from, toOffset: to) }

    // MARK: 요약

    var active: [Subscription] { subs.filter(\.isActive) }

    func activeSubs(_ f: AccountFilter) -> [Subscription] { active.filter { f.matches($0) } }

    var monthlyTotalKRW: Double { monthlyTotal(.all) }

    func monthlyTotal(_ f: AccountFilter) -> Double {
        activeSubs(f).reduce(0) { $0 + $1.monthlyCost(usdKrw: usdKrw) }
    }

    func nextRenewal(_ f: AccountFilter) -> Subscription? { activeSubs(f).min { $0.renewalDate < $1.renewalDate } }

    func mostUsed(_ f: AccountFilter) -> Subscription? {
        activeSubs(f).filter { $0.limit > 0 }.max { $0.ratio < $1.ratio }
    }

    // MARK: 동기화

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rollOverAll()
                if UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true {
                    await self.syncLocal()
                }
            }
        }
    }

    func rollOverAll() {
        var copy = subs
        for i in copy.indices { copy[i].rollOver() }
        if copy != subs { subs = copy }
    }

    func syncLocal() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let targets = subs.filter { $0.source != .manual && $0.isActive }
        var results: [UUID: UsageSnapshot] = [:]
        await withTaskGroup(of: (UUID, UsageSnapshot?).self) { group in
            for t in targets {
                let source = t.source, cycle = t.resetCycle, id = t.id
                group.addTask {
                    switch source {
                    case .claudeCodeLogs: return (id, LocalUsageReader.claudeUsage(cycle: cycle))
                    case .codexLogs: return (id, LocalUsageReader.codexUsage())
                    case .manual: return (id, nil)
                    }
                }
            }
            for await (id, snap) in group { if let snap { results[id] = snap } }
        }

        var copy = subs
        for i in copy.indices {
            guard let snap = results[copy[i].id] else { continue }
            copy[i].used = snap.used
            if let l = snap.limit { copy[i].limit = l }
            copy[i].syncedResetAt = snap.resetAt
            copy[i].syncedDetail = snap.detail
        }
        if copy != subs { subs = copy }
        lastSync = Date()
    }

    // MARK: 환율 (open.er-api.com, 하루 1회)

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
