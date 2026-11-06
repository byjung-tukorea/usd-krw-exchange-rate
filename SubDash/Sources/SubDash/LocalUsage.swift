import Foundation

/// 로컬 CLI 로그에서 읽어 온 사용량
struct UsageSnapshot: Sendable {
    var used: Double
    var limit: Double?
    var resetAt: Date?
    var detail: String?
}

/// Claude Code(~/.claude/projects) 와 Codex CLI(~/.codex/sessions) 의 JSONL 로그를 읽는다.
/// 외부 서버로 아무것도 보내지 않으며, 파일은 읽기만 한다.
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

    /// 주어진 폴더 아래에서 `since` 이후 수정된 .jsonl 파일 목록
    static func jsonlFiles(under roots: [URL], modifiedSince since: Date) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let e = fm.enumerator(at: root,
                                        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                        options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e where url.pathExtension == "jsonl" {
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

    // MARK: - Claude Code

    struct ClaudeEntry { let time: Date; let tokens: Double }

    static func claudeEntries(since: Date) -> [ClaudeEntry] {
        var roots = [home.appendingPathComponent(".claude/projects"),
                     home.appendingPathComponent(".config/claude/projects")]
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            roots.append(URL(fileURLWithPath: custom).appendingPathComponent("projects"))
        }
        var seen = Set<String>()
        var entries: [ClaudeEntry] = []
        for file in jsonlFiles(under: roots, modifiedSince: since) {
            forEachJSONLine(in: file) { obj in
                guard let ts = obj["timestamp"] as? String, let t = parseDate(ts), t >= since,
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any] else { return }
                // 같은 응답이 여러 줄로 기록될 수 있어 message.id + requestId 로 중복 제거
                let key = "\(msg["id"] as? String ?? UUID().uuidString)|\(obj["requestId"] as? String ?? "")"
                guard seen.insert(key).inserted else { return }
                func n(_ k: String) -> Double { (usage[k] as? NSNumber)?.doubleValue ?? 0 }
                let tokens = n("input_tokens") + n("output_tokens") + n("cache_creation_input_tokens")
                entries.append(ClaudeEntry(time: t, tokens: tokens))
            }
        }
        return entries.sorted { $0.time < $1.time }
    }

    /// Claude 의 5시간 세션 블록 규칙(첫 메시지 시각의 정시부터 5시간)을 흉내 내 현재 블록 사용량을 계산
    static func claudeUsage(cycle: ResetCycle, now: Date = Date()) -> UsageSnapshot {
        switch cycle {
        case .fiveHours:
            let entries = claudeEntries(since: now.addingTimeInterval(-10 * 3600))
            var blockStart: Date?
            var blockTokens = 0.0
            var blockCount = 0
            for e in entries {
                if let s = blockStart, e.time < s.addingTimeInterval(5 * 3600) {
                    blockTokens += e.tokens
                    blockCount += 1
                } else {
                    blockStart = floorHour(e.time)
                    blockTokens = e.tokens
                    blockCount = 1
                }
            }
            guard let s = blockStart, now < s.addingTimeInterval(5 * 3600) else {
                return UsageSnapshot(used: 0, resetAt: nil, detail: "활성 세션 없음")
            }
            return UsageSnapshot(used: blockTokens, resetAt: s.addingTimeInterval(5 * 3600),
                                 detail: "현재 블록 \(blockCount)회 응답")
        default:
            let interval: TimeInterval
            switch cycle {
            case .daily: interval = 86_400
            case .weekly: interval = 7 * 86_400
            default: interval = 30 * 86_400
            }
            let entries = claudeEntries(since: now.addingTimeInterval(-interval))
            let total = entries.reduce(0) { $0 + $1.tokens }
            return UsageSnapshot(used: total, resetAt: nil, detail: "최근 \(Int(interval / 86_400))일 \(entries.count)회 응답")
        }
    }

    private static func floorHour(_ d: Date) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour], from: d)
        return cal.date(from: c) ?? d
    }

    // MARK: - Codex CLI

    /// Codex 로그의 token_count 이벤트에 포함된 rate_limits(primary=5시간, secondary=주간) 를 읽는다.
    static func codexUsage(now: Date = Date()) -> UsageSnapshot? {
        var roots = [home.appendingPathComponent(".codex/sessions")]
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            roots.append(URL(fileURLWithPath: custom).appendingPathComponent("sessions"))
        }
        let files = jsonlFiles(under: roots, modifiedSince: now.addingTimeInterval(-8 * 86_400))
        var latestTime = Date.distantPast
        var latestLimits: [String: Any]?

        for file in files {
            forEachJSONLine(in: file) { obj in
                guard let payload = obj["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let limits = payload["rate_limits"] as? [String: Any],
                      let ts = obj["timestamp"] as? String, let t = parseDate(ts),
                      t > latestTime else { return }
                latestTime = t
                latestLimits = limits
            }
        }
        guard let limits = latestLimits else { return nil }

        func window(_ key: String) -> (pct: Double, reset: Date?)? {
            guard let w = limits[key] as? [String: Any] else { return nil }
            let pct = (w["used_percent"] as? NSNumber)?.doubleValue ?? 0
            var reset: Date?
            if let at = (w["resets_at"] as? NSNumber)?.doubleValue {
                reset = Date(timeIntervalSince1970: at)
            } else if let s = (w["resets_in_seconds"] as? NSNumber)?.doubleValue {
                reset = latestTime.addingTimeInterval(s)
            }
            // 리셋 시각이 지났으면 0% 로 본다
            if let r = reset, r <= now { return (0, nil) }
            return (pct, reset)
        }

        let primary = window("primary")
        let secondary = window("secondary")
        var detail: String?
        if let s = secondary {
            detail = "주간 \(Int(s.pct.rounded()))% 사용"
        }
        return UsageSnapshot(used: primary?.pct ?? 0, limit: 100, resetAt: primary?.reset, detail: detail)
    }
}
