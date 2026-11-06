import SwiftUI

/// Claude / Codex 상세 — 참고 스크린샷 구성:
/// [사용량 카드: 5시간 · 주간 한도 · 업데이트 시각 · 연결 상태 / 다시 확인 / 연결 해제]
/// [일별 사용량: 하루 중 5시간 최고 사용량 히트맵]
struct ProviderDetailView: View {
    @EnvironmentObject var store: Store
    var source: UsageSource
    var now: Date

    private var key: ProviderKey { source == .claudeCodeLogs ? .claude : .codex }
    private var title: String { source == .claudeCodeLogs ? "Claude" : "Codex" }
    private var via: String { source == .claudeCodeLogs ? "Claude" : "ChatGPT" }

    var body: some View {
        VStack(spacing: 18) {
            if let sub = store.sub(for: source) {
                usageCard(sub)
                HeatmapCard(values: store.daily[key] ?? [:],
                            peakDays: store.dailyIsPeak[key] ?? [],
                            calibrated: store.dailyCalibrated[key] ?? false,
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
        let off = store.isDisconnected(source)
        let st: LiveState = off ? .failed : sub.state
        let windows = sub.windows ?? []
        let session = windows.filter { !$0.isWeekly }
        let weekly = windows.filter { $0.isWeekly }

        return VStack(alignment: .leading, spacing: 0) {
            // 제목 + 새로고침
            HStack(spacing: 8) {
                Text("\(title) 사용량")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let plan = sub.detectedPlan {
                    Text(plan)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(st == .live ? Theme.accent : Theme.inkFaint)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(InsetBackground(shape: Capsule(), depth: 1.5))
                }
                Spacer()
                Button { Task { await store.sync() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(store.isSyncing ? 360 : 0))
                        .animation(store.isSyncing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                                   value: store.isSyncing)
                }
                .buttonStyle(.plain)
                .help("새로고침")
                .disabled(off)
            }
            .padding(.bottom, 18)

            if windows.isEmpty {
                Text(off ? "연결이 해제되어 있어요." : (st == .failed ? "아직 실제 값을 받지 못했어요." : "불러오는 중…"))
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .padding(.bottom, 14)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(session) { w in DetailRow(window: w, state: st, now: now) }
            }

            if !weekly.isEmpty {
                SectionLabel(text: "주간 한도")
                    .padding(.top, session.isEmpty ? 0 : 18)
                    .padding(.bottom, 10)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(weekly) { w in DetailRow(window: w, state: st, now: now) }
                }
            }

            Group {
                if let at = sub.liveAt {
                    Text("업데이트 \(Fmt.relative(at, now: now))")
                } else {
                    Text("업데이트 기록 없음")
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.inkFaint)
            .padding(.top, 16)

            if st != .live, !off, let detail = sub.syncedDetail, source == .claudeCodeLogs {
                Label(detail, systemImage: "internaldrive")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                    .padding(.top, 6)
            }

            // 홈 파인 구분선
            Rectangle().fill(Color.black).frame(height: 1)
                .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).offset(y: 1))
                .padding(.vertical, 14)

            // 연결 상태 · 다시 확인 · 연결 해제
            HStack(spacing: 12) {
                Text(statusText(sub, off: off))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(st == .live ? Theme.accent : Theme.inkFaint)
                    .shadow(color: st == .live ? Theme.accentGlow : .clear, radius: 4)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if off {
                    Button { store.setConnected(source, true) } label: {
                        Text("연결").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    .buttonStyle(NeuButtonStyle(radius: 10, prominent: true))
                } else {
                    Button { Task { await store.sync() } } label: {
                        Text("다시 확인").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .buttonStyle(NeuButtonStyle(radius: 10, prominent: st == .failed))
                    Button { store.setConnected(source, false) } label: {
                        Text("연결 해제").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !off, st == .failed || st == .fallback {
                Text(hint)
                    .font(.system(size: 9.5)).foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(18)
        .raised(radius: 18, depth: 6)
    }

    private func statusText(_ sub: Subscription, off: Bool) -> String {
        if off { return "연결 해제됨" }
        switch sub.state {
        case .live: return "\(via) 계정으로 연결됨"
        case .fallback: return sub.liveMessage ?? "로컬 기록 기준"
        case .failed: return "연결 실패 · " + (sub.liveMessage ?? "알 수 없는 오류")
        case .manual: return "수동 입력"
        }
    }

    private var hint: String {
        source == .claudeCodeLogs
            ? "Claude Code 에 로그인된 계정으로 조회합니다. 처음엔 macOS 가 키체인 접근을 물으면 '항상 허용'을 누르세요. 토큰이 만료됐다면 터미널에서 claude 를 한 번 실행하면 갱신됩니다."
            : "Codex CLI 로그인 정보(~/.codex/auth.json)로 조회합니다. 터미널에서 codex 를 한 번 실행해 로그인을 갱신하면 다시 연결됩니다."
    }
}

/// 한 줄: [이름 | 막대 | %] + 아래에 리셋 시각 · 남은 시간
struct DetailRow: View {
    var window: UsageWindow
    var state: LiveState
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Text(window.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .leading)
                NeuProgress(value: window.percent / 100, height: 8, state: state)
                Text(Fmt.pct(window.percent))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state == .live ? Theme.ink : Theme.inkSoft)
                    .frame(width: 40, alignment: .trailing)
            }
            if let r = window.resetsAt {
                Text(resetText(r))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 104)
            }
        }
    }

    /// "리셋 09:40 (Asia/Seoul) · 4시간 42분 남음"
    private func resetText(_ r: Date) -> String {
        let cal = Calendar.current
        let when = cal.isDate(r, inSameDayAs: now) ? Fmt.time(r) : "\(Fmt.date(r)) \(Fmt.time(r))"
        return "리셋 \(when) (\(TimeZone.current.identifier)) · \(Fmt.countdown(to: r, now: now)) 남음"
    }
}

// MARK: - 일별 사용량 히트맵

struct HeatmapCard: View {
    var values: [Date: Double]       // 0...1
    var peakDays: Set<Date>          // 앱이 실제 % 를 기록한 날
    var calibrated: Bool             // 로그 값을 % 로 환산했는지
    var now: Date

    private let weeks = 26
    private let cell: CGFloat = 10.5
    private let gap: CGFloat = 3
    private let labelW: CGFloat = 19

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }

    private var startMonday: Date {
        let today = cal.startOfDay(for: now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7     // 월=0 … 일=6
        let thisMonday = cal.date(byAdding: .day, value: -weekday, to: today) ?? today
        return cal.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday) ?? today
    }

    var body: some View {
        let start = startMonday
        let today = cal.startOfDay(for: now)

        VStack(alignment: .leading, spacing: 0) {
            Text("일별 사용량")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                .padding(.bottom, 8)
            Text("하루 중 5시간 최고 사용량 · 오른쪽이 최근")
                .font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 14)

            // 월 표시
            HStack(spacing: gap) {
                Color.clear.frame(width: labelW, height: 10)
                ForEach(0..<weeks, id: \.self) { w in
                    let d = cal.date(byAdding: .day, value: 7 * w, to: start) ?? start
                    let prev = cal.date(byAdding: .day, value: 7 * (w - 1), to: start) ?? start
                    let show = w == 0 || cal.component(.month, from: d) != cal.component(.month, from: prev)
                    Text(show ? "\(cal.component(.month, from: d))월" : "")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            .padding(.bottom, 5)

            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { r in
                        Text(["월", "", "수", "", "금", "", ""][r])
                            .font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
                            .frame(width: labelW, height: cell, alignment: .leading)
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

            HStack(spacing: 4) {
                Text(calibrated || !peakDays.isEmpty ? "앱 기록 + 로그 환산" : "로컬 로그 기준 (상대값)")
                    .font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
                Spacer()
                Text("적음").font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
                ForEach([0.0, 0.2, 0.45, 0.7, 1.0], id: \.self) { v in
                    swatch(v).frame(width: 9, height: 9)
                }
                Text("많음").font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.top, 12)
        }
        .padding(18)
        .raised(radius: 18, depth: 6)
    }

    @ViewBuilder
    private func cellView(day: Date, future: Bool) -> some View {
        if future {
            Color.clear.frame(width: cell, height: cell)
        } else {
            let v = values[day] ?? 0
            let real = peakDays.contains(day)
            swatch(v)
                .frame(width: cell, height: cell)
                .help("\(Fmt.date(day)) · " + (v <= 0 ? "기록 없음"
                    : real ? "5시간 최고 \(Fmt.pct(v * 100))"
                    : calibrated ? "5시간 최고 약 \(Fmt.pct(v * 100)) (로그 환산)"
                    : "최고 블록 상대량 \(Fmt.pct(v * 100))"))
        }
    }

    @ViewBuilder
    private func swatch(_ v: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        if v <= 0 {
            InsetBackground(shape: shape, depth: 1.2)
        } else {
            let level = v < 0.2 ? 0.28 : (v < 0.45 ? 0.5 : (v < 0.7 ? 0.75 : 1.0))
            shape.fill(Theme.accent.opacity(level))
                .overlay(shape.stroke(Color.white.opacity(level >= 1 ? 0.25 : 0.08), lineWidth: 0.5))
                .shadow(color: level >= 1 ? Theme.accentGlow : .clear, radius: 2.5)
        }
    }
}
