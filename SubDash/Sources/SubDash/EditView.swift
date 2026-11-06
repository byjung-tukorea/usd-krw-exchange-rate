import SwiftUI

struct EditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let original: Subscription
    let isNew: Bool
    @State private var s: Subscription

    init(original: Subscription, isNew: Bool) {
        self.original = original
        self.isNew = isNew
        _s = State(initialValue: original)
    }

    private let symbols = ["sparkle", "terminal", "heart", "bolt", "diamond", "circle.hexagongrid",
                           "brain", "wand.and.stars", "cube", "globe", "paintbrush", "waveform"]

    private var renewalKnown: Binding<Bool> {
        Binding(get: { s.renewalConfirmed ?? false }, set: { s.renewalConfirmed = $0 })
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(isNew ? "구독 추가" : "구독 편집")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    section("기본") {
                        row("서비스") { NeuField(title: "예: Claude", text: $s.name) }
                        row("플랜") { NeuField(title: "예: Max 5x", text: $s.plan) }
                        row("구글 계정") {
                            NeuSegmented(options: Account.allCases, selection: $s.acct) { $0.label }
                        }
                        if !s.acct.email.isEmpty {
                            Text(s.acct.email)
                                .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        row("아이콘") { symbolPicker }
                    }

                    section("결제") {
                        row("월 요금") {
                            HStack(spacing: 6) {
                                NeuNumberField(title: "0", value: $s.price)
                                NeuSegmented(options: Currency.allCases, selection: $s.currency) { $0.rawValue }
                                    .frame(width: 104)
                            }
                        }
                        Toggle(isOn: renewalKnown) { label("결제일 입력") }
                            .toggleStyle(NeuToggleStyle())
                        if renewalKnown.wrappedValue {
                            row("다음 결제일") {
                                DatePicker("", selection: $s.renewalDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            Toggle(isOn: $s.autoRenew) { label("매월 자동 연장") }
                                .toggleStyle(NeuToggleStyle())
                        }
                    }

                    section("사용량") {
                        row("집계 방식") {
                            Picker("", selection: $s.source) {
                                ForEach(UsageSource.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if s.source.isLive {
                            Text("서비스 계정에서 5시간·주간 사용률을 실시간으로 받아옵니다.")
                                .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            row("단위") {
                                Picker("", selection: $s.limitUnit) {
                                    ForEach(LimitUnit.allCases) { Text($0.label).tag($0) }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            if s.source == .manual {
                                row("리셋 주기") {
                                    Picker("", selection: $s.resetCycle) {
                                        ForEach(ResetCycle.allCases) { Text($0.label).tag($0) }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                            row("한도") { NeuNumberField(title: "0 = 미정", value: $s.limit) }
                            if s.source == .manual {
                                row("사용량") {
                                    HStack(spacing: 6) {
                                        NeuNumberField(title: "0", value: $s.used)
                                        IconButton(symbol: "minus", size: 24) { s.used = max(0, s.used - 1) }
                                        IconButton(symbol: "plus", size: 24) { s.used += 1 }
                                    }
                                }
                            } else {
                                Text("사용량은 로컬 기록에서 자동으로 채워집니다. 한도만 정하세요.")
                                    .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    section("메모") { NeuField(title: "메모", text: $s.notes) }
                }
                .padding(8)
            }

            HStack(spacing: 10) {
                if !isNew {
                    Button {
                        store.delete(original); dismiss()
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                    }
                    .buttonStyle(NeuButtonStyle(radius: 8))
                    .help("삭제")
                }
                Spacer()
                Button { dismiss() } label: {
                    Text("취소").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 8))
                .keyboardShortcut(.cancelAction)

                Button {
                    if s.lastReset > Date() { s.lastReset = Date() }
                    if s.source.isLive { s.limitUnit = .percent; s.limit = 100 }
                    if s.source != original.source { s.liveState = nil; s.windows = nil; s.liveMessage = nil }
                    store.upsert(s)
                    dismiss()
                    if s.source != .manual { Task { await store.sync() } }
                } label: {
                    Text("저장").font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 8, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(s.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 350, height: 580)
        .background(Theme.bg)
    }

    private var symbolPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 6), spacing: 6) {
            ForEach(symbols, id: \.self) { sym in
                let on = sym == s.symbol
                Image(systemName: sym)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? Theme.accent : Theme.inkSoft)
                    .frame(width: 26, height: 26)
                    .background {
                        if on { InsetBackground(shape: Circle(), depth: 2) }
                        else { Circle().fill(Theme.surface).modifier(Raised(shape: Circle(), depth: 2)) }
                    }
                    .contentShape(Circle())
                    .onTapGesture { s.symbol = sym }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            content()
        }
        .padding(12)
        .raised(radius: 14, depth: 4)
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) {
            label(title).frame(width: 64, alignment: .leading)
            content()
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
    }
}

// MARK: - 설정 탭

struct SettingsTab: View {
    @EnvironmentObject var store: Store

    @AppStorage("autoSync") private var autoSync = true
    @AppStorage("autoRate") private var autoRate = true
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("schoolEmail") private var schoolEmail = ""
    @AppStorage("personalEmail") private var personalEmail = ""

    private var rate: Binding<Double> {
        Binding(get: { store.usdKrw }, set: { store.usdKrw = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                SectionLabel(text: "일반")
                Toggle(isOn: $alwaysOnTop) { t("항상 위에 표시") }
                Toggle(isOn: $showMenuBar) { t("메뉴 막대에 사용률 표시") }
                Toggle(isOn: $autoSync) { t("자동 새로고침 (3분)") }
                Toggle(isOn: $autoRate) { t("환율 자동 갱신") }
            }
            .toggleStyle(NeuToggleStyle())

            card {
                SectionLabel(text: "구글 SSO 계정")
                emailRow(.school, $schoolEmail)
                emailRow(.personal, $personalEmail)
            }

            card {
                SectionLabel(text: "환율")
                HStack {
                    t("USD → KRW")
                    Spacer()
                    NeuNumberField(title: "1400", value: rate).frame(width: 90)
                    IconButton(symbol: "arrow.clockwise", size: 24, help: "지금 갱신") {
                        Task { await store.refreshRateIfNeeded(force: true) }
                    }
                }
                if let at = store.rateUpdatedAt {
                    Text("갱신 \(Fmt.date(at)) \(Fmt.time(at)) · open.er-api.com")
                        .font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
                }
            }

            card {
                SectionLabel(text: "연결 방식")
                info("Claude", "Claude Code 로그인 토큰(키체인)으로 api.anthropic.com 에서 조회")
                info("Codex", "~/.codex/auth.json 으로 chatgpt.com 에서 조회 · 실패 시 Codex 로그")
                info("Gemini", "공개 API 없음 · Gemini CLI 기록(~/.gemini)으로 추정")
                info("Lovable·Genspark", "공개 API 없음 · 직접 입력")
                Text("토큰은 이 Mac 에서 해당 서비스로만 전송되며 앱이 따로 저장하지 않습니다.")
                    .font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
            }

            HStack {
                Button {
                    NSWorkspace.shared.open(store.dataFolder)
                } label: {
                    Text("데이터 폴더 열기").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 8))
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Text("종료").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 8))
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 11) { content() }
            .padding(14)
            .raised(radius: 16, depth: 5)
    }

    private func emailRow(_ a: Account, _ text: Binding<String>) -> some View {
        HStack {
            Label(a.label, systemImage: a.symbol)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink)
                .frame(width: 56, alignment: .leading)
            NeuField(title: "\(a.label) 지메일", text: text)
        }
    }

    private func info(_ name: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 92, alignment: .leading)
            Text(desc).font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func t(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink)
    }
}
