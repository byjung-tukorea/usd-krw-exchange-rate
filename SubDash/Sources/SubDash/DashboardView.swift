import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.used.rawValue
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("showInactive") private var showInactive = true

    @State private var editing: Subscription?
    @State private var showSettings = false

    private var displayMode: Binding<DisplayMode> {
        Binding(get: { DisplayMode(rawValue: displayModeRaw) ?? .used },
                set: { displayModeRaw = $0.rawValue })
    }

    private var visible: [Subscription] {
        showInactive ? store.subs : store.subs.filter(\.isActive)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            SummaryPanel()
            NeuSegmented(options: DisplayMode.allCases, selection: displayMode) { $0.label }
                .padding(.horizontal, 2)

            ScrollView(.vertical, showsIndicators: false) {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    LazyVStack(spacing: 14) {
                        ForEach(visible) { sub in
                            SubscriptionCard(sub: sub, mode: displayMode.wrappedValue, now: ctx.date,
                                             onEdit: { editing = sub })
                        }
                        if visible.isEmpty {
                            Text("구독이 없습니다. + 로 추가하세요.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                                .padding(.top, 30)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, -6)

            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)       // 숨긴 타이틀바(신호등 버튼) 공간
        .padding(.bottom, 14)
        .frame(width: 360)
        .frame(minHeight: 520, idealHeight: 640)
        .background(Theme.surface.ignoresSafeArea())
        .sheet(item: $editing) { sub in
            EditView(original: sub, isNew: !store.subs.contains { $0.id == sub.id })
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .background(WindowAccessor(alwaysOnTop: alwaysOnTop))
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SubDash")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("AI 구독 대시보드")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            IconButton(symbol: alwaysOnTop ? "pin.fill" : "pin", help: "항상 위에") {
                alwaysOnTop.toggle()
            }
            IconButton(symbol: "plus", help: "구독 추가") {
                editing = Subscription(name: "", plan: "", symbol: "circle.hexagongrid",
                                       price: 0, currency: .usd, renewalDate: Subscription.days(30),
                                       limitUnit: .credits, used: 0, limit: 100,
                                       resetCycle: .monthly, lastReset: Date())
            }
            IconButton(symbol: "slider.horizontal.3", help: "설정") { showSettings = true }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.syncLocal() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(store.isSyncing ? 360 : 0))
                        .animation(store.isSyncing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                   value: store.isSyncing)
                    Text("동기화").font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(NeuButtonStyle(radius: 8))

            Text(store.lastSync.map { "마지막 \(Fmt.time($0))" } ?? "로그 대기 중")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)

            Spacer()

            Toggle(isOn: $showInactive) {
                Text("꺼진 항목").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            .toggleStyle(NeuToggleStyle(width: 32, height: 18))
            .fixedSize()
        }
    }
}

// MARK: - 상단 요약 (음각 패널)

struct SummaryPanel: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            stat(title: "월 합계", value: Fmt.won(store.monthlyTotalKRW),
                 sub: "\(store.active.count)개 구독")
            divider
            if let n = store.nextRenewal {
                stat(title: "다음 결제", value: Fmt.dday(n.daysUntilRenewal), sub: n.name)
            } else {
                stat(title: "다음 결제", value: "–", sub: " ")
            }
            divider
            if let m = store.mostUsed {
                stat(title: "최다 사용", value: "\(Int((m.ratio * 100).rounded()))%", sub: m.name)
            } else {
                stat(title: "최다 사용", value: "–", sub: " ")
            }
        }
        .padding(.vertical, 12)
        .inset(radius: 16, depth: 3.5)
    }

    private var divider: some View {
        Rectangle().fill(Theme.darkShadow.opacity(0.35)).frame(width: 1, height: 30)
            .overlay(Rectangle().fill(Theme.lightShadow).frame(width: 1).offset(x: 1))
    }

    private func stat(title: String, value: String, sub: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 9)).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

// MARK: - 구독 카드 (양각)

struct SubscriptionCard: View {
    @EnvironmentObject var store: Store
    var sub: Subscription
    var mode: DisplayMode
    var now: Date
    var onEdit: () -> Void

    private var isOn: Binding<Bool> {
        Binding(get: { sub.isActive },
                set: { v in var s = sub; s.isActive = v; store.upsert(s) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: sub.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.graphite)
                    .frame(width: 32, height: 32)
                    .insetCircle(depth: 2.5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(sub.name.isEmpty ? "이름 없음" : sub.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(sub.plan) · \(Fmt.price(sub))/월")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                ddayBadge
                Toggle("", isOn: isOn).labelsHidden()
                    .toggleStyle(NeuToggleStyle(width: 34, height: 18))
                    .frame(width: 34)
            }

            if sub.isActive {
                usageBlock
            }
        }
        .padding(12)
        .raised(radius: 16, depth: 5)
        .opacity(sub.isActive ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("편집…", action: onEdit)
            if sub.source == .manual {
                Button("사용량 +1") { store.adjust(sub, by: 1) }
                Button("사용량 +10") { store.adjust(sub, by: 10) }
                Button("사용량 초기화") { store.resetUsage(sub) }
            }
            Divider()
            Button("삭제", role: .destructive) { store.delete(sub) }
        }
    }

    private var ddayBadge: some View {
        let d = sub.daysUntilRenewal
        let urgent = d <= 3
        return Text(Fmt.dday(d))
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(urgent ? Theme.surface : Theme.inkSoft)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background {
                if urgent {
                    Capsule().fill(Theme.warn.opacity(0.85))
                } else {
                    InsetBackground(shape: Capsule(), depth: 2)
                }
            }
            .help("다음 결제일 \(Fmt.date(sub.renewalDate))")
    }

    private var usageBlock: some View {
        let hasLimit = sub.limit > 0
        let shown = mode == .used ? sub.used : sub.remaining
        let ratio = mode == .used ? sub.ratio : (hasLimit ? 1 - sub.ratio : 0)
        let unit = sub.limitUnit == .percent ? "%" : " \(sub.limitUnit.label)"

        return VStack(alignment: .leading, spacing: 6) {
            NeuProgress(value: hasLimit ? ratio : 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.compact(hasLimit || mode == .used ? shown : sub.used))
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                Text(hasLimit ? "/ \(Fmt.compact(sub.limit))\(unit)" : unit)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
                if sub.source != .manual {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.inkFaint)
                        .help(sub.source.label + "에서 자동 집계")
                }
                Spacer()
                if let r = sub.nextReset {
                    Label(Fmt.countdown(to: r, now: now), systemImage: "clock")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                        .labelStyle(.titleAndIcon)
                } else if let detail = sub.syncedDetail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                }
            }
            if sub.nextReset != nil, let detail = sub.syncedDetail {
                Text(detail).font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
            }
        }
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
        w.backgroundColor = NSColor(Theme.surface)
    }
}
