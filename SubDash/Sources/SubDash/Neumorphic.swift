import SwiftUI
import AppKit

// MARK: - 무채색 팔레트 (라이트/다크 자동 대응)

enum Theme {
    private static func dyn(light: CGFloat, dark: CGFloat, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { app in
            let isDark = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: isDark ? alpha.1 : alpha.0)
        })
    }

    static let surface = dyn(light: 0.894, dark: 0.165)          // 바탕
    static let surfaceHi = dyn(light: 0.925, dark: 0.190)        // 살짝 밝은 면
    static let lightShadow = dyn(light: 1.0, dark: 0.30, alpha: (0.95, 0.35))
    static let darkShadow = dyn(light: 0.62, dark: 0.0, alpha: (0.55, 0.75))
    static let ink = dyn(light: 0.17, dark: 0.90)                // 주 글자
    static let inkSoft = dyn(light: 0.45, dark: 0.60)            // 보조 글자
    static let inkFaint = dyn(light: 0.62, dark: 0.42)
    static let graphite = dyn(light: 0.30, dark: 0.78)           // 강조(무채색)
    static let warn = dyn(light: 0.12, dark: 0.98)               // 임박 표시
}

// MARK: - 양각 (Raised)

struct Raised<S: Shape>: ViewModifier {
    var shape: S
    var depth: CGFloat = 5

    func body(content: Content) -> some View {
        content.background(
            shape.fill(
                LinearGradient(colors: [Theme.surfaceHi, Theme.surface],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .shadow(color: Theme.darkShadow, radius: depth, x: depth * 0.6, y: depth * 0.6)
            .shadow(color: Theme.lightShadow, radius: depth, x: -depth * 0.6, y: -depth * 0.6)
        )
    }
}

// MARK: - 음각 (Inset)

struct InsetBackground<S: Shape>: View {
    var shape: S
    var depth: CGFloat = 3

    var body: some View {
        shape.fill(Theme.surface)
            .overlay(
                shape.stroke(Theme.darkShadow, lineWidth: depth * 1.6)
                    .blur(radius: depth)
                    .offset(x: depth * 0.7, y: depth * 0.7)
                    .mask(shape.fill(LinearGradient(colors: [.black, .clear],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            )
            .overlay(
                shape.stroke(Theme.lightShadow, lineWidth: depth * 1.6)
                    .blur(radius: depth)
                    .offset(x: -depth * 0.7, y: -depth * 0.7)
                    .mask(shape.fill(LinearGradient(colors: [.clear, .black],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            )
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

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(Theme.ink)
            .background {
                if circle {
                    if pressed { InsetBackground(shape: Circle(), depth: 2.5) }
                    else { Circle().fill(Theme.surface).modifier(Raised(shape: Circle(), depth: 3.5)) }
                } else {
                    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                    if pressed { InsetBackground(shape: shape, depth: 2.5) }
                    else { shape.fill(Theme.surface).modifier(Raised(shape: shape, depth: 3.5)) }
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(NeuButtonStyle(circle: true))
        .help(help)
    }
}

// MARK: - 토글: 음각 트랙 + 양각 손잡이

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
                            .fill(Theme.graphite.opacity(configuration.isOn ? 0.85 : 0))
                            .padding(3)
                    )
                Circle()
                    .fill(Theme.surface)
                    .modifier(Raised(shape: Circle(), depth: 2))
                    .padding(3)
                    .overlay(
                        Circle().fill(Theme.inkFaint.opacity(configuration.isOn ? 0 : 0.5))
                            .frame(width: 4, height: 4)
                    )
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
                    .font(.system(size: 11, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if on {
                            Capsule().fill(Theme.surface)
                                .modifier(Raised(shape: Capsule(), depth: 2.5))
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

// MARK: - 진행 막대: 음각 트랙 + 양각 채움

struct NeuProgress: View {
    var value: Double        // 0...1
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                InsetBackground(shape: Capsule(), depth: 2)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.graphite.opacity(0.75), Theme.graphite],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(value > 0 ? height : 0, geo.size.width * value))
                    .shadow(color: Theme.darkShadow.opacity(0.6), radius: 1.5, x: 1, y: 1)
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
