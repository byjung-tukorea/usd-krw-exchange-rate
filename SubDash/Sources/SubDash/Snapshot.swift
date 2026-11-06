import SwiftUI
import AppKit

/// `SubDash --snapshot <폴더>` : 화면을 PNG 로 그려 저장하고 종료 (빌드 서버에서 화면 점검용).
/// 아래 값은 레이아웃 확인용 샘플이며 앱 실행 시에는 쓰이지 않는다.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()

        let live = demoStore(now: now, claudeState: .live)
        let failed = demoStore(now: now, claudeState: .failed)

        write(page(live, now: now) { ProviderDetailView(source: .claudeCodeLogs, now: now) },
              to: dir.appendingPathComponent("1-claude-live.png"))
        write(page(failed, now: now) { ProviderDetailView(source: .claudeCodeLogs, now: now) },
              to: dir.appendingPathComponent("2-claude-failed.png"))
        write(page(live, now: now, tab: .codex) { ProviderDetailView(source: .codexLogs, now: now) },
              to: dir.appendingPathComponent("3-codex.png"))
        write(page(live, now: now, tab: .overview) {
            OverviewTab(now: now, onEdit: { _ in }, onOpen: { _ in })
        }, to: dir.appendingPathComponent("4-overview.png"))
        write(page(live, now: now, tab: .settings) { SettingsTab() }, to: dir.appendingPathComponent("5-settings.png"))
        exit(0)
    }

    private static func page<V: View>(_ store: Store, now: Date, tab: Tab = .claude, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 22)
                    .background(Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                              startPoint: .top, endPoint: .bottom))
                        .shadow(color: Theme.accentGlow, radius: 6))
                Text("SubDash").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Spacer()
            }
            HStack {
                NeuSegmented(options: Tab.allCases, selection: .constant(tab)) { $0.label }
                    .frame(width: 280)
                Spacer()
            }
            content().padding(.horizontal, 8).padding(.vertical, 10).padding(.horizontal, -8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(width: 440)
        .background(Theme.bg)
        .environmentObject(store)
        .environment(\.colorScheme, .dark)
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("snapshot failed: \(url.lastPathComponent)"); return
        }
        try? png.write(to: url)
        print("snapshot: \(url.path)")
    }

    private static func demoStore(now: Date, claudeState: LiveState) -> Store {
        let s = Store(demo: true)
        var list = Subscription.defaults
        func h(_ x: Double) -> Date { now.addingTimeInterval(x * 3600) }

        list[0].windows = [
            UsageWindow(id: "five_hour", title: "5시간 세션", percent: 1, resetsAt: h(4.7)),
            UsageWindow(id: "seven_day", title: "전체 모델", percent: 23, resetsAt: h(131), isWeekly: true),
            UsageWindow(id: "seven_day_opus", title: "Opus", percent: 8, resetsAt: h(131), isWeekly: true),
        ]
        list[0].liveState = claudeState
        list[0].liveMessage = claudeState == .live ? "Claude 계정 연결됨" : "인증 거부 (다시 로그인 필요)"
        list[0].liveAt = now.addingTimeInterval(claudeState == .live ? -43 : -5400)
        list[0].detectedPlan = "Max"
        list[0].renewalConfirmed = true
        list[0].renewalDate = Calendar.current.date(byAdding: .day, value: 12, to: now)!

        list[1].windows = [
            UsageWindow(id: "primary_window", title: "5시간 세션", percent: 37, resetsAt: h(2.2)),
            UsageWindow(id: "secondary_window", title: "전체", percent: 61, resetsAt: h(70), isWeekly: true),
        ]
        list[1].liveState = .live
        list[1].liveAt = now.addingTimeInterval(-60)
        list[1].detectedPlan = "Plus"
        list[1].account = .school

        list[2].used = 46; list[2].renewalConfirmed = true
        list[2].renewalDate = Calendar.current.date(byAdding: .day, value: 2, to: now)!
        list[3].used = 3_200
        list[4].used = 18; list[4].liveState = .fallback
        list[4].liveMessage = "Gemini CLI 기록 기준 (웹·앱 사용 미포함)"; list[4].account = .school
        s.subs = list
        s.lastSync = now

        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        var daily: [Date: Double] = [:]
        for d in 0..<180 {
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -d, to: now)!)
            if d > 105 { continue }                    // 오래된 기간은 기록 없음
            let v = (sin(Double(d) * 1.7) + 1) / 2
            if v > 0.15 { daily[day] = v }
        }
        s.daily = [.claude: daily, .codex: daily.filter { $0.value > 0.4 }]
        s.dailyCalibrated = [.claude: true, .codex: false]
        return s
    }
}
