import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case overview, claude, codex, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .overview: return "한눈에"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .settings: return "설정"
        }
    }
}

// MARK: - 루트: 헤더 + 탭

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("tab") private var tabRaw = Tab.overview.rawValue

    @State private var editing: Subscription?

    private var tab: Binding<Tab> {
        Binding(get: { Tab(rawValue: tabRaw) ?? .overview }, set: { tabRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            NeuSegmented(options: Tab.allCases, selection: tab) { $0.label }

            ScrollView(.vertical, showsIndicators: false) {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Group {
                        switch tab.wrappedValue {
                        case .overview:
                            OverviewTab(now: ctx.date, onEdit: { editing = $0 }, onOpen: open)
                        case .claude:
                            ProviderDetailView(source: .claudeCodeLogs, now: ctx.date)
                        case .codex:
                            ProviderDetailView(source: .codexLogs, now: ctx.date)
                        case .settings:
                            SettingsTab()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, -8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)       // 숨긴 타이틀바(신호등 버튼) 공간
        .padding(.bottom, 12)
        .frame(width: 380)
        .frame(minHeight: 560, idealHeight: 700)
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $editing) { sub in
            EditView(original: sub, isNew: !store.subs.contains { $0.id == sub.id })
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .background(WindowAccessor(alwaysOnTop: alwaysOnTop))
    }

    private func open(_ s: Subscription) {
        switch s.source {
        case .claudeCodeLogs: withAnimation { tab.wrappedValue = .claude }
        case .codexLogs: withAnimation { tab.wrappedValue = .codex }
        default: editing = s
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 44, height: 22)
            .background(
                Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                              startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                    .shadow(color: Theme.accentGlow, radius: 6)
            )
            Text("SubDash")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            IconButton(symbol: "arrow.triangle.2.circlepath", size: 26, help: "지금 새로고침 (⌘R)",
                       spinning: store.isSyncing) {
                Task { await store.sync(); await store.refreshDaily(force: true) }
            }
            IconButton(symbol: alwaysOnTop ? "pin.fill" : "pin", size: 26, help: "항상 위에") {
                alwaysOnTop.toggle()
            }
            IconButton(symbol: "plus", size: 26, help: "구독 추가") {
                editing = Subscription(name: "", plan: "", symbol: "circle.hexagongrid",
                                       price: 0, currency: .usd, renewalDate: Subscription.days(30),
                                       limitUnit: .credits, used: 0, limit: 100,
                                       resetCycle: .monthly, lastReset: Date(), renewalConfirmed: true)
            }
        }
    }
}

// MARK: - 한눈에 (5개 서비스)

struct OverviewTab: View {
    @EnvironmentObject var store: Store
    @AppStorage("showInactive") private var showInactive = true
    @AppStorage("accountFilter") private var accountFilterRaw = AccountFilter.all.rawValue
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.used.rawValue

    var now: Date
    var onEdit: (Subscription) -> Void
    var onOpen: (Subscription) -> Void

    private var filter: Binding<AccountFilter> {
        Binding(get: { AccountFilter(rawValue: accountFilterRaw) ?? .all }, set: { accountFilterRaw = $0.rawValue })
    }
    private var mode: Binding<DisplayMode> {
        Binding(get: { DisplayMode(rawValue: displayModeRaw) ?? .used }, set: { displayModeRaw = $0.rawValue })
    }

    private var visible: [Subscription] {
        store.subs.filter { (showInactive || $0.isActive) && filter.wrappedValue.matches($0) }
    }

    var body: some View {
        VStack(spacing: 14) {
            SummaryPanel(filter: filter.wrappedValue)

            HStack(spacing: 10) {
                NeuSegmented(options: AccountFilter.allCases, selection: filter) { $0.label }
                NeuSegmented(options: DisplayMode.allCases, selection: mode) { $0.label }
                    .frame(width: 128)
            }

            LazyVStack(spacing: 14) {
                ForEach(visible) { sub in
                    ServiceCard(sub: sub, mode: mode.wrappedValue, now: now,
                                onEdit: { onEdit(sub) }, onOpen: { onOpen(sub) })
                }
                if visible.isEmpty {
                    Text("표시할 구독이 없어요. + 로 추가하세요.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .padding(.top, 24)
                }
            }

            HStack {
                Text(store.lastSync.map { "업데이트 \(Fmt.relative($0, now: now))" } ?? "불러오는 중…")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                Spacer()
                Toggle(isOn: $showInactive) {
                    Text("꺼진 항목").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
                .toggleStyle(NeuToggleStyle(width: 32, height: 18))
                .fixedSize()
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - 상단 요약 (음각 패널)

struct SummaryPanel: View {
    @EnvironmentObject var store: Store
    var filter: AccountFilter = .all

    var body: some View {
        let lc = store.liveCount(filter)
        HStack(spacing: 0) {
            stat(title: filter == .all ? "월 합계" : "월 합계 · \(filter.label)",
                 value: Fmt.won(store.monthlyTotal(filter)),
                 sub: "\(store.activeSubs(filter).count)개 구독", accent: false)
            divider
            if let n = store.nextRenewal(filter) {
                stat(title: "다음 결제", value: Fmt.dday(n.daysUntilRenewal), sub: n.name,
                     accent: n.daysUntilRenewal <= 3)
            } else {
                stat(title: "다음 결제", value: "–", sub: "결제일 미설정", accent: false)
            }
            divider
            stat(title: "실시간 연결", value: "\(lc.live)/\(lc.total)", sub: lc.live > 0 ? "연결됨" : "연결 없음",
                 accent: lc.live > 0)
        }
        .padding(.vertical, 13)
        .inset(radius: 16, depth: 3.5)
    }

    private var divider: some View {
        Rectangle().fill(Color.black).frame(width: 1, height: 30)
            .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1).offset(x: 1))
    }

    private func stat(title: String, value: String, sub: String, accent: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent ? Theme.accent : Theme.ink)
                .shadow(color: accent ? Theme.accentGlow : .clear, radius: 5)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 9)).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

// MARK: - 서비스 카드 (양각)

struct ServiceCard: View {
    @EnvironmentObject var store: Store
    var sub: Subscription
    var mode: DisplayMode
    var now: Date
    var onEdit: () -> Void
    var onOpen: () -> Void

    private var isOn: Binding<Bool> {
        Binding(get: { sub.isActive }, set: { v in var s = sub; s.isActive = v; store.upsert(s) })
    }

    var body: some View {
        let st = sub.state
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: sub.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(st == .live ? Theme.accent : Theme.inkFaint)
                    .shadow(color: st == .live ? Theme.accentGlow : .clear, radius: 4)
                    .frame(width: 32, height: 32)
                    .insetCircle(depth: 2.5)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(sub.name.isEmpty ? "이름 없음" : sub.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        stateDot(st)
                    }
                    HStack(spacing: 5) {
                        accountChip
                        Text("\(sub.detectedPlan ?? sub.plan) · \(Fmt.price(sub))/월")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                ddayBadge
                Toggle("", isOn: isOn).labelsHidden()
                    .toggleStyle(NeuToggleStyle(width: 34, height: 18))
                    .frame(width: 34)
            }

            if sub.isActive { usageBlock(st) }
        }
        .padding(13)
        .raised(radius: 16, depth: 6)
        .opacity(sub.isActive ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            if sub.source.isLive { Button("자세히 보기", action: onOpen) }
            Button("편집…", action: onEdit)
            Menu("로그인 계정") {
                ForEach(Account.allCases) { a in
                    Button((sub.acct == a ? "✓ " : "") + a.label + (a.email.isEmpty ? "" : " (\(a.email))")) {
                        var s = sub; s.acct = a; store.upsert(s)
                    }
                }
            }
            if sub.source == .manual {
                Divider()
                Button("사용량 +1") { store.adjust(sub, by: 1) }
                Button("사용량 +10") { store.adjust(sub, by: 10) }
                Button("사용량 초기화") { store.resetUsage(sub) }
            }
            Divider()
            Button("삭제", role: .destructive) { store.delete(sub) }
        }
    }

    private func stateDot(_ st: LiveState) -> some View {
        HStack(spacing: 3) {
            Circle().fill(st.dotColor).frame(width: 5, height: 5)
                .shadow(color: st == .live ? Theme.accentGlow : .clear, radius: 3)
            Text(st.label).font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(st == .live ? Theme.accent : Theme.inkFaint)
        }
    }

    private var accountChip: some View {
        let a = sub.acct
        return HStack(spacing: 2) {
            Image(systemName: a.symbol).font(.system(size: 7, weight: .bold))
            Text(a.label).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 5).padding(.vertical, 1.5)
        .background(InsetBackground(shape: Capsule(), depth: 1.5))
        .help(a.email.isEmpty ? "\(a.label) 구글 계정" : a.email)
    }

    private var ddayBadge: some View {
        let d = sub.daysUntilRenewal
        let urgent = sub.hasRenewal && d <= 3
        return Text(sub.hasRenewal ? Fmt.dday(d) : "D-?")
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(urgent ? Color.white : (sub.hasRenewal ? Theme.inkSoft : Theme.inkFaint))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background {
                if urgent {
                    Capsule().fill(Theme.accent).shadow(color: Theme.accentGlow, radius: 5)
                } else {
                    InsetBackground(shape: Capsule(), depth: 2)
                }
            }
            .help(sub.hasRenewal ? "다음 결제일 \(Fmt.date(sub.renewalDate))" : "결제일 미설정 — 편집에서 입력")
    }

    @ViewBuilder
    private func usageBlock(_ st: LiveState) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let p = sub.primaryWindow {
                windowRow(p, st: st, big: true)
                if let w = sub.weeklyWindow { windowRow(w, st: st, big: false) }
            } else if let w = sub.weeklyWindow {
                windowRow(w, st: st, big: true)
            } else {
                manualRow(st)
            }
            footnote(st)
        }
    }

    private func windowRow(_ w: UsageWindow, st: LiveState, big: Bool) -> some View {
        let shown = mode == .used ? w.percent : max(100 - w.percent, 0)
        let ratio = (mode == .used ? w.percent : 100 - w.percent) / 100
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(big ? "5시간" : "주간")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 30, alignment: .leading)
                NeuProgress(value: ratio, height: big ? 8 : 5, state: st)
                Text(Fmt.pct(shown))
                    .font(.system(size: big ? 12 : 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(st == .live ? Theme.ink : Theme.inkSoft)
                    .frame(width: 36, alignment: .trailing)
            }
            if big, let r = w.resetsAt {
                Text(Fmt.resetLine(r, now: now))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 38)
            }
        }
    }

    private func manualRow(_ st: LiveState) -> some View {
        let hasLimit = sub.limit > 0
        let shown = mode == .used ? sub.used : sub.remaining
        let ratio = mode == .used ? sub.ratio : (hasLimit ? 1 - sub.ratio : 0)
        let unit = sub.limitUnit == .percent ? "%" : " \(sub.limitUnit.label)"
        return VStack(alignment: .leading, spacing: 5) {
            NeuProgress(value: hasLimit ? ratio : 0, state: st)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.compact(hasLimit ? shown : sub.used))
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(st == .fallback ? Theme.ink : Theme.inkSoft)
                Text(hasLimit ? "/ \(Fmt.compact(sub.limit))\(unit)" : unit)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                if let r = sub.nextReset {
                    Label(Fmt.countdown(to: r, now: now), systemImage: "clock")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
    }

    @ViewBuilder
    private func footnote(_ st: LiveState) -> some View {
        switch st {
        case .live:
            EmptyView()
        case .fallback:
            note(sub.liveMessage ?? "로컬 기록 기준", icon: "internaldrive")
        case .failed:
            let when = sub.liveAt.map { " · 마지막 성공 \(Fmt.relative($0, now: now))" } ?? ""
            note((sub.liveMessage ?? "연결 실패") + when, icon: "exclamationmark.triangle")
        case .manual:
            note("수동 입력 · 우클릭으로 +1 / 초기화 (이 서비스는 사용량 API 없음)", icon: "hand.point.up.left")
        }
    }

    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.inkFaint)
            .lineLimit(2)
    }
}

// MARK: - 창 설정 (항상 위에)

struct WindowAccessor: NSViewRepresentable {
    var alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { apply(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(nsView.window) }
    }

    private func apply(_ w: NSWindow?) {
        guard let w else { return }
        w.level = alwaysOnTop ? .floating : .normal
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(red: 0.031, green: 0.035, blue: 0.043, alpha: 1)
        w.appearance = NSAppearance(named: .darkAqua)
    }
}
