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

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(isNew ? "구독 추가" : "구독 편집")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    section("기본") {
                        row("서비스") { NeuField(title: "예: Claude Code", text: $s.name) }
                        row("플랜") { NeuField(title: "예: Max 5x", text: $s.plan) }
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
                        row("다음 결제일") {
                            DatePicker("", selection: $s.renewalDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Toggle(isOn: $s.autoRenew) { label("결제일 자동 연장 (매월)") }
                            .toggleStyle(NeuToggleStyle())
                    }

                    section("한도") {
                        row("집계 방식") {
                            Picker("", selection: $s.source) {
                                ForEach(UsageSource.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        row("단위") {
                            Picker("", selection: $s.limitUnit) {
                                ForEach(LimitUnit.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        row("리셋 주기") {
                            Picker("", selection: $s.resetCycle) {
                                ForEach(ResetCycle.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        row("한도") { NeuNumberField(title: "0 = 미정", value: $s.limit) }
                        row("사용량") {
                            HStack(spacing: 6) {
                                NeuNumberField(title: "0", value: $s.used)
                                    .disabled(s.source != .manual)
                                IconButton(symbol: "minus", size: 24) { s.used = max(0, s.used - 1) }
                                    .disabled(s.source != .manual)
                                IconButton(symbol: "plus", size: 24) { s.used += 1 }
                                    .disabled(s.source != .manual)
                            }
                        }
                        if s.source != .manual {
                            Text("사용량은 로컬 로그에서 자동으로 채워집니다.")
                                .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    section("메모") {
                        NeuField(title: "메모", text: $s.notes)
                    }
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
                    store.upsert(s)
                    dismiss()
                    if s.source != .manual { Task { await store.syncLocal() } }
                } label: {
                    Text("저장").font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 8))
                .keyboardShortcut(.defaultAction)
                .disabled(s.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340, height: 560)
        .background(Theme.surface)
    }

    private var symbolPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 6), spacing: 6) {
            ForEach(symbols, id: \.self) { sym in
                let on = sym == s.symbol
                Image(systemName: sym)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
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
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.inkFaint)
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

// MARK: - 설정

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("autoSync") private var autoSync = true
    @AppStorage("autoRate") private var autoRate = true
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("appearance") private var appearance = "system"

    private var rate: Binding<Double> {
        Binding(get: { store.usdKrw }, set: { store.usdKrw = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("설정")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            VStack(spacing: 12) {
                Toggle(isOn: $alwaysOnTop) { t("항상 위에 표시") }
                Toggle(isOn: $showMenuBar) { t("메뉴 막대 아이콘") }
                Toggle(isOn: $autoSync) { t("로컬 로그 자동 동기화 (2분)") }
                Toggle(isOn: $autoRate) { t("환율 자동 갱신") }
            }
            .toggleStyle(NeuToggleStyle())
            .padding(12)
            .raised(radius: 14, depth: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    t("화면")
                    Spacer()
                    NeuSegmented(options: AppearanceOption.allCases,
                                 selection: Binding(get: { AppearanceOption(rawValue: appearance) ?? .system },
                                                    set: { appearance = $0.rawValue })) { $0.label }
                        .frame(width: 170)
                }
                HStack {
                    t("USD → KRW")
                    Spacer()
                    NeuNumberField(title: "1400", value: rate).frame(width: 90)
                    IconButton(symbol: "arrow.clockwise", size: 24, help: "지금 갱신") {
                        Task { await store.refreshRateIfNeeded(force: true) }
                    }
                }
                if let at = store.rateUpdatedAt {
                    Text("환율 갱신 \(Fmt.date(at)) \(Fmt.time(at)) · open.er-api.com")
                        .font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(12)
            .raised(radius: 14, depth: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("데이터는 이 Mac 에만 저장됩니다.")
                Text("Claude Code: ~/.claude/projects · Codex: ~/.codex/sessions 로그를 읽기만 합니다.")
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.inkFaint)

            HStack {
                Button {
                    NSWorkspace.shared.open(store.dataFolder)
                } label: {
                    Text("데이터 폴더 열기").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 8))
                Spacer()
                Button { dismiss() } label: {
                    Text("완료").font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 16).padding(.vertical, 7)
                }
                .buttonStyle(NeuButtonStyle(radius: 8))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 330)
        .background(Theme.surface)
    }

    private func t(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink)
    }
}

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "자동"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
