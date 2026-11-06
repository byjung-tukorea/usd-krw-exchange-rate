import SwiftUI
import AppKit

// MARK: - 팔레트: 검정 바탕 + 코발트 블루 강조 (다크 전용)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    static let bg = Color(hex: 0x08090B)            // 창 바탕 (거의 검정)
    static let surface = Color(hex: 0x15171C)       // 양각 카드
    static let surfaceHi = Color(hex: 0x1D2027)     // 카드 윗면 하이라이트
    static let well = Color(hex: 0x050608)          // 음각 홈
    static let lightShadow = Color.white.opacity(0.07)
    static let darkShadow = Color.black.opacity(0.9)
    static let bevel = Color.white.opacity(0.09)    // 양각 윗모서리 반사광

    static let ink = Color(hex: 0xF3F5F9)
    static let inkSoft = Color(hex: 0xA6ADBB)
    static let inkFaint = Color(hex: 0x666D7A)

    // 코발트 블루
    static let accent = Color(hex: 0x3D74FF)        // 밝은 코발트 (검정 위 시인성)
    static let accentDeep = Color(hex: 0x0047AB)    // 정통 코발트
    static let accentGlow = Color(hex: 0x3D74FF, alpha: 0.55)
    static let accentMuted = Color(hex: 0x3A4763)   // 로그 기준(대체 값)
    static let dead = Color(hex: 0x34373F)          // 연결 실패 / 수동

    // 하위 호환용 이름
    static var graphite: Color { accent }
    static var warn: Color { accent }
}

/// 실시간 연결 상태
enum LiveState: String, Codable {
    case live       // 서비스에서 실제 값 수신
    case fallback   // 로컬 기록 기반 (추정/대체)
    case failed     // 연결 실패 (마지막 값 표시)
    case manual     // 직접 입력

    var barStyle: AnyShapeStyle {
        switch self {
        case .live: return AnyShapeStyle(LinearGradient(colors: [Theme.accentDeep, Theme.accent],
                                                        startPoint: .leading, endPoint: .trailing))
        case .fallback: return AnyShapeStyle(Theme.accentMuted)
        case .failed, .manual: return AnyShapeStyle(Theme.dead)
        }
    }

    var dotColor: Color {
        switch self {
        case .live: return Theme.accent
        case .fallback: return Theme.accentMuted
        case .failed: return Color(hex: 0x5A5F6A)
        case .manual: return Theme.dead
        }
    }

    var label: String {
        switch self {
        case .live: return "실시간"
        case .fallback: return "로컬 기록"
        case .failed: return "연결 끊김"
        case .manual: return "수동"
        }
    }
}

// MARK: - 양각 (Raised)

struct Raised<S: Shape>: ViewModifier {
    var shape: S
    var depth: CGFloat = 5

    func body(content: Content) -> some View {
        content.background(
            shape.fill(LinearGradient(colors: [Theme.surfaceHi, Theme.surface],
                                      startPoint: .top, endPoint: .bottom))
                .overlay(shape.stroke(LinearGradient(colors: [Theme.bevel, .clear, .black.opacity(0.4)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 0.8))
                .shadow(color: Theme.darkShadow, radius: depth, x: depth * 0.6, y: depth * 0.7)
                .shadow(color: Theme.lightShadow, radius: depth * 0.8, x: -depth * 0.35, y: -depth * 0.35)
        )
    }
}

// MARK: - 음각 (Inset)

struct InsetBackground<S: Shape>: View {
    var shape: S
    var depth: CGFloat = 3

    var body: some View {
        shape.fill(Theme.well)
            .overlay(
                shape.stroke(Color.black, lineWidth: depth * 1.8)
                    .blur(radius: depth)
                    .offset(x: depth * 0.7, y: depth * 0.7)
                    .mask(shape.fill(LinearGradient(colors: [.black, .clear],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.08), lineWidth: depth)
                    .blur(radius: depth * 0.8)
                    .offset(x: -depth * 0.5, y: -depth * 0.5)
                    .mask(shape.fill(LinearGradient(colors: [.clear, .black],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            )
            .overlay(shape.stroke(Color.white.opacity(0.04), lineWidth: 0.6))
            .clipShape(shape)
    }
}

extension View {
    func raised(radius: CGFloat = 14, depth: CGFloat = 5) -> some View {
        modifier(Raised(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), depth: depth))
    }

    func raisedCircle(depth: CGFloat = 4) -> some View {
        modifier(Raised(shape: Circle(), depth: depth))
    }

    func inset(radius: CGFloat = 12, depth: CGFloat = 3) -> some View {
        background(InsetBackground(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), depth: depth))
    }

    func insetCircle(depth: CGFloat = 3) -> some View {
        background(InsetBackground(shape: Circle(), depth: depth))
    }
}

// MARK: - 버튼: 평소 양각, 누르면 음각

struct NeuButtonStyle: ButtonStyle {
    var circle = false
    var radius: CGFloat = 10
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(prominent ? Color.white : Theme.ink)
            .background {
                if circle {
                    if pressed { InsetBackground(shape: Circle(), depth: 2.5) }
                    else { Circle().fill(Theme.surface).modifier(Raised(shape: Circle(), depth: 3.5)) }
                } else {
                    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                    if pressed {
                        InsetBackground(shape: shape, depth: 2.5)
                    } else if prominent {
                        shape.fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                  startPoint: .top, endPoint: .bottom))
                            .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                            .shadow(color: Theme.accentGlow, radius: 6, y: 2)
                    } else {
                        shape.fill(Theme.surface).modifier(Raised(shape: shape, depth: 3.5))
                    }
                }
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

struct IconButton: View {
    var symbol: String
    var size: CGFloat = 28
    var help: String = ""
    var spinning = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                           value: spinning)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(NeuButtonStyle(circle: true))
        .help(help)
    }
}

// MARK: - 토글: 음각 트랙 + 양각 손잡이, 켜지면 코발트

struct NeuToggleStyle: ToggleStyle {
    var width: CGFloat = 38
    var height: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                InsetBackground(shape: Capsule(), depth: 2.2)
                    .overlay(
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.accentDeep, Theme.accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .opacity(configuration.isOn ? 1 : 0)
                            .shadow(color: Theme.accentGlow, radius: configuration.isOn ? 4 : 0)
                            .padding(2.5)
                    )
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xE9ECF2), Color(hex: 0xA9AFBB)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1.5)
                    .padding(3.5)
            }
            .frame(width: width, height: height)
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { configuration.isOn.toggle() }
            }
        }
    }
}

// MARK: - 세그먼트: 음각 홈 안에서 양각 알약이 이동

struct NeuSegmented<T: Hashable & Identifiable>: View {
    var options: [T]
    @Binding var selection: T
    var label: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { opt in
                let on = opt == selection
                Text(label(opt))
                    .font(.system(size: 11, weight: on ? .bold : .medium))
                    .foregroundStyle(on ? Theme.ink : Theme.inkFaint)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if on {
                            Capsule().fill(Theme.surface)
                                .modifier(Raised(shape: Capsule(), depth: 2.5))
                                .overlay(Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 14)
                                    .shadow(color: Theme.accentGlow, radius: 3),
                                         alignment: .bottom)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = opt }
                    }
            }
        }
        .padding(4)
        .background(InsetBackground(shape: Capsule(), depth: 2.5))
    }
}

// MARK: - 진행 막대: 음각 트랙 + 상태별 채움

struct NeuProgress: View {
    var value: Double        // 0...1
    var height: CGFloat = 8
    var state: LiveState = .live

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                InsetBackground(shape: Capsule(), depth: 2)
                Capsule()
                    .fill(state.barStyle)
                    .frame(width: max(value > 0 ? height : 0, geo.size.width * min(max(value, 0), 1)))
                    .shadow(color: state == .live ? Theme.accentGlow : .clear, radius: 4)
                    .animation(.easeOut(duration: 0.4), value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 음각 입력칸

struct NeuField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .inset(radius: 8, depth: 2.2)
    }
}

struct NeuNumberField: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        TextField(title, value: $value, format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .rounded).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .inset(radius: 8, depth: 2.2)
    }
}

/// 카드 안 소제목
struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Theme.inkFaint)
    }
}
