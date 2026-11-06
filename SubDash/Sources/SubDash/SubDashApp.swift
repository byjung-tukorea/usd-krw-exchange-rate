import SwiftUI
import AppKit

@main
struct SubDashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("SubDash", id: "main") {
            DashboardView()
                .environmentObject(store)
                .onAppear { applyAppearance(appearance) }
                .onChange(of: appearance) { applyAppearance($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("구독") {
                Button("지금 동기화") { Task { await store.syncLocal() } }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel().environmentObject(store)
        } label: {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
        .menuBarExtraStyle(.window)
    }

    private func applyAppearance(_ raw: String) {
        switch AppearanceOption(rawValue: raw) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 메뉴 막대 아이콘을 쓰지 않으면 창을 닫을 때 종료
        !(UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true)
    }
}

// MARK: - 메뉴 막대 패널 (요약)

struct MenuBarPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SubDash").font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(Fmt.won(store.monthlyTotalKRW) + "/월")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
            }
            .foregroundStyle(Theme.ink)

            VStack(spacing: 9) {
                ForEach(store.active) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: s.symbol).font(.system(size: 9)).frame(width: 12)
                            Text(s.name).font(.system(size: 11, weight: .medium))
                            Spacer()
                            if s.limit > 0 {
                                Text("\(Int((s.ratio * 100).rounded()))%")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            }
                            Text(Fmt.dday(s.daysUntilRenewal))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(Theme.inkSoft)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .foregroundStyle(Theme.ink)
                        NeuProgress(value: s.ratio, height: 5)
                    }
                }
            }
            .padding(10)
            .inset(radius: 12, depth: 2.5)

            HStack(spacing: 8) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Text("대시보드 열기").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(NeuButtonStyle(radius: 8))

                IconButton(symbol: "arrow.triangle.2.circlepath", size: 26, help: "동기화") {
                    Task { await store.syncLocal() }
                }
                Spacer()
                IconButton(symbol: "power", size: 26, help: "종료") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(Theme.surface)
    }
}
