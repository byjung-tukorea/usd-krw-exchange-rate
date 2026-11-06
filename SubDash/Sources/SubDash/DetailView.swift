import SwiftUI

/// Claude / Codex 상세: 5시간 세션 · 주간 한도 · 연결 상태 · 일별 히트맵
struct ProviderDetailView: View {
    @EnvironmentObject var store: Store
    var source: UsageSource
    var now: Date

    private var key: ProviderKey { source == .claudeCodeLogs ? .claude : .codex }
    private var title: String { source == .claudeCodeLogs ? "Claude" : "Codex" }

    var body: some View {
        VStack(spacing: 16) {
            if let sub = store.sub(for: source) {
                usageCard(sub)
                HeatmapCard(title: "일별 사용량",
                            caption: "하루 중 5시간 최고 사용률 · 기록 전 날짜는 로컬 로그 토큰량 · 오른쪽이 최근",
                            values: store.daily[key] ?? [:],
                            peakDays: store.dailyIsPeak[key] ?? [],
                            now: now)
            } else {
                Text("\(title) 구독이 목록에 없어요.\n한눈에 탭에서 + 로 추가하고 집계 방식을 '\(source.label)'로 고르세요.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .raised(radius: 16)
            }
        }
        .task { await store.refreshDaily() }
    }

    private func usageCard(_ sub: Subscription) -> some View {
        let st = sub.state
        let windows = sub.windows ?? []
        let session = windows.filter { !$0.isWeekly }
        let weekly = windows.filter { $0.isWeekly }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(title) 사용량")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let plan = sub.detectedPlan {
                    Text(plan)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(InsetBackground(shape: Capsule(), depth: 1.5))
                }
                Spacer()
                IconButton(symbol: "arrow.clockwise", size: 26, help: "다시 확인", spinning: store.isSyncing) {
                    Task { await store.sync() }
                }
            }

            if windows.isEmpty {
                Text(st == .failed ? "아직 실제 값을 받지 못했어요." : "불러오는 중…")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }

            ForEach(session) { w in DetailRow(window: w, state: st, now: now, big: true) }

            if !weekly.isEmpty {
                SectionLabel(text: "주간 한도")
                    .padding(.top, 2)
                ForEach(weekly) { w in DetailRow(window: w, state: st, now: now, big: false) }
            }

            if let at = sub.liveAt {
                Text("업데이트 \(Fmt.relative(at, now: now))")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
            }

            if st != .live, let detail = sub.syncedDetail, source == .claudeCodeLogs {
                Label(detail, systemImage: "internaldrive")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
            }

            // 홈 파인 구분선
            Rectangle().fill(Color.black).frame(height: 1)
                .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).offset(y: 1))

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(st.dotColor).frame(width: 7, height: 7)
                        .shadow(color: st == .live ? Theme.accentGlow : .clear, radius: 4)
                    Text(statusText(sub))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(st == .live ? Theme.accent : Theme.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Button {
                    Task { await store.sync() }
                } label: {
                    Text("다시 확인").font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 9, prominent: st != .live))
            }

            if st == .failed || st == .fallback {
                Text(hint)
                    .font(.system(size: 9.5)).foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .raised(radius: 18, depth: 6)
    }

    private func statusText(_ sub: Subscription) -> String {
        switch sub.state {
        case .live: return sub.liveMessage ?? "연결됨"
        case .fallback: return sub.liveMessage ?? "로컬 기록 기준"
        case .failed: return "연결 실패 · " + (sub.liveMessage ?? "알 수 없는 오류")
        case .manual: return "수동 입력"
        }
    }

    private var hint: String {
        source == .claudeCodeLogs
            ? "Claude Code 에 로그인된 계정의 토큰으로 조회합니다. 처음엔 macOS 가 키체인 접근을 물으면 '항상 허용'을 누르세요. 토큰이 만료됐다면 터미널에서 claude 를 한 번 실행하면 갱신됩니다."
            : "Codex CLI 로그인 정보(~/.codex/auth.json)로 조회합니다. 터미널에서 codex 를 한 번 실행해 로그인을 갱신하면 다시 연결됩니다."
    }
}

struct DetailRow: View {
    var window: UsageWindow
    var state: LiveState
    var now: Date
    var big: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(window.title)
                    .font(.system(size: big ? 12 : 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 100, alignment: .leading)
                NeuProgress(value: window.percent / 100, height: big ? 9 : 7, state: state)
                Text(Fmt.pct(window.percent))
                    .font(.system(size: big ? 13 : 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state == .live ? Theme.ink : Theme.inkSoft)
                    .frame(width: 38, alignment: .trailing)
            }
            if let r = window.resetsAt {
                Text(Fmt.resetLine(r, now: now) + " (\(TimeZone.current.identifier))")
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 110)
            }
        }
    }
}

// MARK: - 히트맵 (깃허브 잔디 형태)

struct HeatmapCard: View {
    var title: String
    var caption: String
    var values: [Date: Double]       // 0...1
    var peakDays: Set<Date>
    var now: Date

    private let weeks = 22
    private let cell: CGFloat = 10
    private let gap: CGFloat = 3

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2          // 월요일 시작
        c.timeZone = .current
        return c
    }

    /// 첫 열의 월요일
    private var startMonday: Date {
        let today = cal.startOfDay(for: now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7     // 월=0 … 일=6
        let thisMonday = cal.date(byAdding: .day, value: -weekday, to: today) ?? today
        return cal.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday) ?? today
    }

    var body: some View {
        let start = startMonday
        let today = cal.startOfDay(for: now)

        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
            Text(caption).font(.system(size: 9.5)).foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                // 월 표시
                HStack(spacing: gap) {
                    Color.clear.frame(width: 18, height: 10)
                    ForEach(0..<weeks, id: \.self) { w in
                        let d = cal.date(byAdding: .day, value: 7 * w, to: start) ?? start
                        let prev = cal.date(byAdding: .day, value: 7 * (w - 1), to: start) ?? start
                        let showMonth = w == 0 || cal.component(.month, from: d) != cal.component(.month, from: prev)
                        Text(showMonth ? "\(cal.component(.month, from: d))월" : "")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize()
                            .frame(width: cell, alignment: .leading)
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    VStack(alignment: .leading, spacing: gap) {
                        ForEach(0..<7, id: \.self) { r in
                            Text(["월", "", "수", "", "금", "", ""][r])
                                .font(.system(size: 8)).foregroundStyle(Theme.inkFaint)
                                .frame(width: 18, height: cell, alignment: .leading)
                        }
                    }
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { r in
                                let day = cal.date(byAdding: .day, value: 7 * w + r, to: start) ?? start
                                cellView(day: day, future: day > today)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Spacer()
                Text("적음").font(.system(size: 8)).foregroundStyle(Theme.inkFaint)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                    swatch(v).frame(width: 9, height: 9)
                }
                Text("많음").font(.system(size: 8)).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(16)
        .raised(radius: 18, depth: 6)
    }

    @ViewBuilder
    private func cellView(day: Date, future: Bool) -> some View {
        if future {
            Color.clear.frame(width: cell, height: cell)
        } else {
            let v = values[day] ?? 0
            swatch(v)
                .frame(width: cell, height: cell)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(peakDays.contains(day) ? Color.white.opacity(0.18) : .clear, lineWidth: 0.6)
                )
                .help("\(Fmt.date(day)) · " + (v > 0
                      ? (peakDays.contains(day) ? "5시간 최고 \(Fmt.pct(v * 100))" : "로그 기준 상대량 \(Fmt.pct(v * 100))")
                      : "기록 없음"))
        }
    }

    @ViewBuilder
    private func swatch(_ v: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        if v <= 0 {
            InsetBackground(shape: shape, depth: 1.2)
        } else {
            let level = v < 0.25 ? 0.3 : (v < 0.5 ? 0.5 : (v < 0.75 ? 0.75 : 1.0))
            shape.fill(Theme.accent.opacity(level))
                .shadow(color: level >= 1 ? Theme.accentGlow : .clear, radius: 2)
        }
    }
}
