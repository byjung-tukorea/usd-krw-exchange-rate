import Foundation

/// 한도를 세는 단위
enum LimitUnit: String, Codable, CaseIterable, Identifiable {
    case tokens, messages, credits, requests, percent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .tokens: return "토큰"
        case .messages: return "메시지"
        case .credits: return "크레딧"
        case .requests: return "요청"
        case .percent: return "%"
        }
    }
}

/// 한도가 초기화되는 주기
enum ResetCycle: String, Codable, CaseIterable, Identifiable {
    case fiveHours, daily, weekly, monthly, none
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiveHours: return "5시간"
        case .daily: return "매일"
        case .weekly: return "매주"
        case .monthly: return "매월"
        case .none: return "없음"
        }
    }

    func next(after date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .fiveHours: return date.addingTimeInterval(5 * 3600)
        case .daily: return cal.date(byAdding: .day, value: 1, to: date)
        case .weekly: return cal.date(byAdding: .day, value: 7, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        case .none: return nil
        }
    }
}

/// 사용량을 어디서 가져올지
enum UsageSource: String, Codable, CaseIterable, Identifiable {
    case manual, claudeCodeLogs, codexLogs
    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "직접 입력"
        case .claudeCodeLogs: return "Claude Code 로그"
        case .codexLogs: return "Codex CLI 로그"
        }
    }
}

enum Currency: String, Codable, CaseIterable, Identifiable {
    case usd = "USD", krw = "KRW"
    var id: String { rawValue }
    var symbol: String { self == .usd ? "$" : "₩" }
}

struct Subscription: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var plan: String
    var symbol: String                 // SF Symbol 이름
    var price: Double
    var currency: Currency
    var renewalDate: Date              // 다음 결제일
    var autoRenew: Bool = true
    var limitUnit: LimitUnit
    var used: Double
    var limit: Double                  // 0 이면 한도 미정
    var resetCycle: ResetCycle
    var lastReset: Date
    var source: UsageSource = .manual
    var isActive: Bool = true
    var notes: String = ""

    // 로컬 로그 동기화 결과 (선택 값이라 예전 데이터와도 호환)
    var syncedResetAt: Date?
    var syncedDetail: String?

    // MARK: 계산 값

    var ratio: Double {
        guard limit > 0 else { return 0 }
        return min(max(used / limit, 0), 1)
    }

    var remaining: Double { max(limit - used, 0) }

    var nextReset: Date? {
        if source != .manual, let s = syncedResetAt { return s }
        return resetCycle.next(after: lastReset)
    }

    var daysUntilRenewal: Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: Date())
        let b = cal.startOfDay(for: renewalDate)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    func monthlyCost(usdKrw: Double) -> Double {
        currency == .krw ? price : price * usdKrw
    }

    /// 지난 주기를 정리: 결제일 자동 연장, 수동 사용량 초기화
    mutating func rollOver(now: Date = Date()) {
        if autoRenew {
            var guardCount = 0
            while renewalDate < Calendar.current.startOfDay(for: now), guardCount < 120 {
                renewalDate = Calendar.current.date(byAdding: .month, value: 1, to: renewalDate) ?? now
                guardCount += 1
            }
        }
        guard source == .manual else { return }
        var guardCount = 0
        while let n = resetCycle.next(after: lastReset), n <= now, guardCount < 10_000 {
            lastReset = n
            used = 0
            guardCount += 1
        }
    }
}

extension Subscription {
    static func days(_ d: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
    }

    static var defaults: [Subscription] {
        let now = Date()
        return [
            Subscription(name: "Claude Code", plan: "Max 5x", symbol: "sparkle",
                         price: 100, currency: .usd, renewalDate: days(18),
                         limitUnit: .tokens, used: 0, limit: 2_000_000,
                         resetCycle: .fiveHours, lastReset: now, source: .claudeCodeLogs,
                         notes: "토큰은 입력+출력+캐시 생성 기준. 한도는 체감에 맞게 조정하세요."),
            Subscription(name: "ChatGPT Codex", plan: "Plus", symbol: "terminal",
                         price: 20, currency: .usd, renewalDate: days(9),
                         limitUnit: .percent, used: 0, limit: 100,
                         resetCycle: .fiveHours, lastReset: now, source: .codexLogs),
            Subscription(name: "Lovable", plan: "Pro", symbol: "heart",
                         price: 25, currency: .usd, renewalDate: days(4),
                         limitUnit: .credits, used: 32, limit: 100,
                         resetCycle: .monthly, lastReset: Calendar.current.date(byAdding: .day, value: -26, to: now) ?? now),
            Subscription(name: "Genspark", plan: "Plus", symbol: "bolt",
                         price: 24.99, currency: .usd, renewalDate: days(22),
                         limitUnit: .credits, used: 2_400, limit: 10_000,
                         resetCycle: .monthly, lastReset: Calendar.current.date(byAdding: .day, value: -8, to: now) ?? now),
            Subscription(name: "Gemini", plan: "Google AI Pro", symbol: "diamond",
                         price: 29_000, currency: .krw, renewalDate: days(13),
                         limitUnit: .requests, used: 12, limit: 100,
                         resetCycle: .daily, lastReset: Calendar.current.startOfDay(for: now)),
        ]
    }
}
