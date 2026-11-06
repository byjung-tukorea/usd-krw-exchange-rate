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

/// 한도가 초기화되는 주기 (수동 입력용)
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
        case .daily: return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))
        case .weekly: return cal.date(byAdding: .day, value: 7, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        case .none: return nil
        }
    }
}

/// 사용량을 어디서 가져올지 (rawValue 는 예전 저장 데이터와 호환)
enum UsageSource: String, Codable, CaseIterable, Identifiable {
    case claudeCodeLogs   // Claude 계정 (실시간 API → 실패 시 로그)
    case codexLogs        // ChatGPT/Codex 계정 (실시간 API → 실패 시 로그)
    case geminiCLI        // Gemini CLI 로컬 기록 (추정)
    case manual
    var id: String { rawValue }

    var label: String {
        switch self {
        case .claudeCodeLogs: return "Claude 계정 (실시간)"
        case .codexLogs: return "ChatGPT·Codex 계정 (실시간)"
        case .geminiCLI: return "Gemini CLI 기록 (추정)"
        case .manual: return "직접 입력"
        }
    }

    var isLive: Bool { self == .claudeCodeLogs || self == .codexLogs }
}

enum Currency: String, Codable, CaseIterable, Identifiable {
    case usd = "USD", krw = "KRW"
    var id: String { rawValue }
    var symbol: String { self == .usd ? "$" : "₩" }
}

/// 구글 SSO 로그인 계정 (서비스마다 다름)
enum Account: String, Codable, CaseIterable, Identifiable {
    case school, personal
    var id: String { rawValue }
    var label: String { self == .school ? "학교" : "개인" }
    var symbol: String { self == .school ? "graduationcap" : "person" }
    var email: String {
        UserDefaults.standard.string(forKey: self == .school ? "schoolEmail" : "personalEmail") ?? ""
    }
}

enum AccountFilter: String, CaseIterable, Identifiable {
    case all, school, personal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "전체"
        case .school: return "학교"
        case .personal: return "개인"
        }
    }
    func matches(_ s: Subscription) -> Bool {
        switch self {
        case .all: return true
        case .school: return s.acct == .school
        case .personal: return s.acct == .personal
        }
    }
}

/// 서비스가 알려 준 사용 창 하나 (예: 5시간, 주간 전체, 주간 Opus)
struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    var id: String          // five_hour, seven_day ...
    var title: String       // "5시간", "주간 · 전체 모델"
    var percent: Double     // 0...100
    var resetsAt: Date?
    var isWeekly: Bool = false
}

struct Subscription: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var plan: String
    var symbol: String
    var price: Double
    var currency: Currency
    var renewalDate: Date
    var autoRenew: Bool = true
    var limitUnit: LimitUnit
    var used: Double
    var limit: Double                  // 0 이면 한도 미정
    var resetCycle: ResetCycle
    var lastReset: Date
    var source: UsageSource = .manual
    var isActive: Bool = true
    var notes: String = ""

    // 이하 선택 값 (예전 데이터 호환)
    var syncedResetAt: Date?
    var syncedDetail: String?
    var account: Account?
    var windows: [UsageWindow]?        // 실시간/로그로 받은 사용 창
    var liveState: LiveState?
    var liveMessage: String?           // "Claude 계정 연결됨", 실패 사유 등
    var liveAt: Date?                  // 마지막으로 값을 받은 시각
    var detectedPlan: String?          // 서비스가 알려 준 플랜
    var renewalConfirmed: Bool?        // 사용자가 결제일을 직접 확인했는지

    var acct: Account {
        get { account ?? .personal }
        set { account = newValue }
    }

    var state: LiveState { source == .manual ? .manual : (liveState ?? .failed) }

    var hasRenewal: Bool { renewalConfirmed ?? false }

    /// 대표 사용률 (0...1). 실시간 서비스는 5시간 창, 수동은 used/limit
    var ratio: Double {
        if let w = windows?.first { return min(max(w.percent / 100, 0), 1) }
        guard limit > 0 else { return 0 }
        return min(max(used / limit, 0), 1)
    }

    var remaining: Double { max(limit - used, 0) }

    var primaryWindow: UsageWindow? { windows?.first { !$0.isWeekly } }
    var weeklyWindow: UsageWindow? { windows?.first { $0.isWeekly } }

    var nextReset: Date? {
        if let r = primaryWindow?.resetsAt { return r }
        if source != .manual { return syncedResetAt }
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

    /// 지난 주기 정리: 결제일 자동 연장, 수동 사용량 초기화
    mutating func rollOver(now: Date = Date()) {
        if autoRenew {
            var n = 0
            while renewalDate < Calendar.current.startOfDay(for: now), n < 120 {
                renewalDate = Calendar.current.date(byAdding: .month, value: 1, to: renewalDate) ?? now
                n += 1
            }
        }
        guard source == .manual else { return }
        var n = 0
        while let next = resetCycle.next(after: lastReset), next <= now, n < 10_000 {
            lastReset = next
            used = 0
            n += 1
        }
    }
}

extension Subscription {
    static func days(_ d: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
    }

    /// 처음 실행 시 목록. 사용량은 0, 결제일은 '미설정' 상태로 시작한다.
    static var defaults: [Subscription] {
        let now = Date()
        let soon = days(30)
        return [
            Subscription(name: "Claude", plan: "Max", symbol: "sparkle",
                         price: 100, currency: .usd, renewalDate: soon,
                         limitUnit: .percent, used: 0, limit: 100,
                         resetCycle: .fiveHours, lastReset: now, source: .claudeCodeLogs, renewalConfirmed: false),
            Subscription(name: "ChatGPT Codex", plan: "Plus", symbol: "terminal",
                         price: 20, currency: .usd, renewalDate: soon,
                         limitUnit: .percent, used: 0, limit: 100,
                         resetCycle: .fiveHours, lastReset: now, source: .codexLogs, renewalConfirmed: false),
            Subscription(name: "Lovable", plan: "Pro", symbol: "heart",
                         price: 25, currency: .usd, renewalDate: soon,
                         limitUnit: .credits, used: 0, limit: 100,
                         resetCycle: .monthly, lastReset: now, renewalConfirmed: false),
            Subscription(name: "Genspark", plan: "Plus", symbol: "bolt",
                         price: 24.99, currency: .usd, renewalDate: soon,
                         limitUnit: .credits, used: 0, limit: 10_000,
                         resetCycle: .monthly, lastReset: now, renewalConfirmed: false),
            Subscription(name: "Gemini", plan: "Google AI Pro", symbol: "diamond",
                         price: 29_000, currency: .krw, renewalDate: soon,
                         limitUnit: .requests, used: 0, limit: 1_500,
                         resetCycle: .daily, lastReset: Calendar.current.startOfDay(for: now),
                         source: .geminiCLI, renewalConfirmed: false),
        ]
    }
}
