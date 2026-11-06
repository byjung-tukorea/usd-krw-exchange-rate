import SwiftUI
import AppKit

@main
struct SubDashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some Scene {
        Window("SubDash", id: "main") {
            DashboardView()
                .environmentObject(store)
                .onAppear { NSApp.appearance = NSAppearance(named: .darkAqua) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("구독") {
                Button("지금 새로고침") { Task { await store.sync(); await store.refreshDaily(force: true) } }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel().environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 메뉴 막대 아이콘을 쓰지 않으면 창을 닫을 때 종료
        !(UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true)
    }
}

/// 메뉴 막대: 아이콘 + Claude/Codex 5시간 사용률
struct MenuBarLabel: View {
    @ObservedObject var store: Store

    var body: some View {
        let parts = [UsageSource.claudeCodeLogs, .codexLogs].compactMap { src -> String? in
            guard let s = store.sub(for: src), s.isActive, let w = s.primaryWindow else { return nil }
            let mark = s.state == .live ? "" : "·"
            return (src == .claudeCodeLogs ? "C " : "X ") + Fmt.pct(w.percent) + mark
        }
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.67percent")
            if !parts.isEmpty { Text(parts.joined(separator: "  ")) }
        }
    }
}

// MARK: - 메뉴 막대 패널

struct MenuBarPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SubDash").font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(Fmt.won(store.monthlyTotalKRW) + "/월")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
            }
            .foregroundStyle(Theme.ink)

            VStack(spacing: 10) {
                ForEach(store.active) { s in
                    let st = s.state
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Circle().fill(st.dotColor).frame(width: 5, height: 5)
                            Text(s.name).font(.system(size: 11, weight: .medium))
                            Image(systemName: s.acct.symbol).font(.system(size: 8))
                                .foregroundStyle(Theme.inkFaint)
                            Spacer()
                            if s.primaryWindow != nil || s.limit > 0 {
                                Text(Fmt.pct(s.ratio * 100))
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            }
                            Text(s.hasRenewal ? Fmt.dday(s.daysUntilRenewal) : "D-?")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(Theme.inkSoft)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .foregroundStyle(Theme.ink)
                        NeuProgress(value: s.ratio, height: 5, state: st)
                    }
                }
            }
            .padding(11)
            .inset(radius: 12, depth: 2.5)

            HStack(spacing: 8) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Text("대시보드 열기").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(NeuButtonStyle(radius: 8, prominent: true))

                IconButton(symbol: "arrow.triangle.2.circlepath", size: 26, help: "새로고침",
                           spinning: store.isSyncing) {
                    Task { await store.sync() }
                }
                Spacer()
                IconButton(symbol: "power", size: 26, help: "종료") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 290)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}
