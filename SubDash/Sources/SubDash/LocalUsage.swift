import Foundation

/// 로컬 기록에서 읽은 사용량 (실시간 연결 실패 시 대체 값)
struct UsageSnapshot: Sendable {
    var used: Double
    var limit: Double?
    var resetAt: Date?
    var detail: String?
    var windows: [UsageWindow] = []
    var recordedAt: Date?
}

/// Claude Code(~/.claude/projects), Codex CLI(~/.codex/sessions), Gemini CLI(~/.gemini/tmp) 기록을 읽는다.
/// 파일은 읽기만 하며 외부로 아무것도 보내지 않는다.
enum LocalUsageReader {

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        iso.date(from: s) ?? isoNoFraction.date(from: s)
    }

    static func files(under roots: [URL], ext: String, modifiedSince since: Date) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let e = fm.enumerator(at: root,
                                        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                        options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e where url.pathExtension == ext {
                let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard v?.isRegularFile == true else { continue }
                if let m = v?.contentModificationDate, m < since { continue }
                result.append(url)
            }
        }
        return result
    }

    static func forEachJSONLine(in url: URL, _ body: ([String: Any]) -> Void) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                body(obj)
            }
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func num(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? 0 }

    // MARK: - Claude Code

    struct Entry { let time: Date; let tokens: Double }

    static func claudeEntries(since: Date) -> [Entry] {
        var roots = [home.appendingPathComponent(".claude/projects"),
                     home.appendingPathComponent(".config/claude/projects")]
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            roots.append(URL(fileURLWithPath: custom).appendingPathComponent("projects"))
        }
        var seen = Set<String>()
        var entries: [Entry] = []
        for file in files(under: roots, ext: "jsonl", modifiedSince: since) {
            forEachJSONLine(in: file) { obj in
                guard let ts = obj["timestamp"] as? String, let t = parseDate(ts), t >= since,
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any] else { return }
                let key = "\(msg["id"] as? String ?? UUID().uuidString)|\(obj["requestId"] as? String ?? "")"
                guard seen.insert(key).inserted else { return }
                let tokens = num(usage["input_tokens"]) + num(usage["output_tokens"])
                    + num(usage["cache_creation_input_tokens"])
                entries.append(Entry(time: t, tokens: tokens))
            }
        }
        return entries.sorted { $0.time < $1.time }
    }

    /// 실시간 연결 실패 시: 로그로 현재 5시간 블록 토큰을 추정
    static func claudeUsage(now: Date = Date()) -> UsageSnapshot {
        let entries = claudeEntries(since: now.addingTimeInterval(-10 * 3600))
        var start: Date?
        var tokens = 0.0
        var count = 0
        for e in entries {
            if let s = start, e.time < s.addingTimeInterval(5 * 3600) {
                tokens += e.tokens; count += 1
            } else {
                start = floorHour(e.time); tokens = e.tokens; count = 1
            }
        }
        guard let s = start, now < s.addingTimeInterval(5 * 3600) else {
            return UsageSnapshot(used: 0, detail: "로그상 활성 세션 없음", recordedAt: entries.last?.time)
        }
        return UsageSnapshot(used: tokens, resetAt: s.addingTimeInterval(5 * 3600),
                             detail: "로그상 현재 블록 \(Fmt.compact(tokens)) 토큰 · \(count)회 응답",
                             recordedAt: entries.last?.time)
    }

    static func claudeDaily(days: Int, now: Date = Date()) -> [Date: Double] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        var out: [Date: Double] = [:]
        let cal = Calendar.current
        for e in claudeEntries(since: since) {
            out[cal.startOfDay(for: e.time), default: 0] += e.tokens
        }
        return out
    }

    private static func floorHour(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: d)) ?? d
    }

    // MARK: - Codex CLI

    private static var codexRoots: [URL] {
        var roots = [home.appendingPathComponent(".codex/sessions")]
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            roots.append(URL(fileURLWithPath: custom).appendingPathComponent("sessions"))
        }
        return roots
    }

    /// 로그의 마지막 token_count 이벤트에 담긴 rate_limits (primary=5시간, secondary=주간)
    static func codexUsage(now: Date = Date()) -> UsageSnapshot? {
        let found = files(under: codexRoots, ext: "jsonl", modifiedSince: now.addingTimeInterval(-8 * 86_400))
        var latest = Date.distantPast
        var limits: [String: Any]?
        for file in found {
            forEachJSONLine(in: file) { obj in
                guard let payload = obj["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let rl = payload["rate_limits"] as? [String: Any],
                      let ts = obj["timestamp"] as? String, let t = parseDate(ts), t > latest else { return }
                latest = t
                limits = rl
            }
        }
        guard let limits else { return nil }

        func window(_ key: String, _ title: String, weekly: Bool) -> UsageWindow? {
            guard let w = limits[key] as? [String: Any] else { return nil }
            var pct = num(w["used_percent"])
            var reset: Date?
            if let at = (w["resets_at"] as? NSNumber)?.doubleValue {
                reset = Date(timeIntervalSince1970: at)
            } else if let s = (w["resets_in_seconds"] as? NSNumber)?.doubleValue {
                reset = latest.addingTimeInterval(s)
            }
            if let r = reset, r <= now { pct = 0; reset = nil }   // 이미 리셋됨
            return UsageWindow(id: key, title: title, percent: pct, resetsAt: reset, isWeekly: weekly)
        }
        let windows = [window("primary", "5시간 세션", weekly: false),
                       window("secondary", "주간 한도", weekly: true)].compactMap { $0 }
        return UsageSnapshot(used: windows.first?.percent ?? 0, limit: 100,
                             resetAt: windows.first?.resetsAt,
                             detail: "마지막 Codex 기록 \(Fmt.relative(latest)) 기준",
                             windows: windows, recordedAt: latest)
    }

    static func codexDaily(days: Int, now: Date = Date()) -> [Date: Double] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for file in files(under: codexRoots, ext: "jsonl", modifiedSince: since) {
            forEachJSONLine(in: file) { obj in
                guard let payload = obj["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let last = info["last_token_usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String, let t = parseDate(ts), t >= since else { return }
                let total = num(last["total_tokens"]) > 0
                    ? num(last["total_tokens"])
                    : num(last["input_tokens"]) + num(last["output_tokens"])
                out[cal.startOfDay(for: t), default: 0] += total
            }
        }
        return out
    }

    // MARK: - Gemini CLI

    /// ~/.gemini/tmp/<프로젝트>/logs.json 의 사용자 프롬프트 수 (오늘)
    static func geminiUsage(now: Date = Date()) -> UsageSnapshot? {
        let root = home.appendingPathComponent(".gemini/tmp")
        let start = Calendar.current.startOfDay(for: now)
        let logFiles = files(under: [root], ext: "json", modifiedSince: start)
            .filter { $0.lastPathComponent == "logs.json" }
        let anyLogs = !files(under: [root], ext: "json", modifiedSince: .distantPast)
            .filter { $0.lastPathComponent == "logs.json" }.isEmpty
        guard anyLogs else { return nil }
        var count = 0
        var latest: Date?
        for f in logFiles {
            guard let d = try? Data(contentsOf: f),
                  let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { continue }
            for item in arr where (item["type"] as? String ?? "user") == "user" {
                guard let ts = item["timestamp"] as? String, let t = parseDate(ts), t >= start else { continue }
                count += 1
                if latest == nil || t > latest! { latest = t }
            }
        }
        return UsageSnapshot(used: Double(count), resetAt: Calendar.current.date(byAdding: .day, value: 1, to: start),
                             detail: "Gemini CLI 오늘 프롬프트 \(count)회 (웹 사용 제외)", recordedAt: latest)
    }
}
