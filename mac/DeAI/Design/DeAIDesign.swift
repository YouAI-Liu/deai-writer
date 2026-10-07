import SwiftUI

private struct ReducedMotionOverride: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var deaiReducedMotionOverride: Bool? {
        get { self[ReducedMotionOverride.self] }
        set { self[ReducedMotionOverride.self] = newValue }
    }
}

@propertyWrapper
struct DeAIReducedMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemValue
    @Environment(\.deaiReducedMotionOverride) private var override
    var wrappedValue: Bool { override ?? systemValue }
}

enum DeAIDesign {
    static let canvas = Color(red: 236 / 255, green: 235 / 255, blue: 232 / 255)
    static let ink = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    static let paper = Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255)
    static let muted = Color(red: 108 / 255, green: 107 / 255, blue: 103 / 255)
    static let accent = Color(red: 168 / 255, green: 105 / 255, blue: 68 / 255)
    static let radius: CGFloat = 24
    static let contentDuration = 0.15

    static func font(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func motion(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: contentDuration) : .spring(response: 0.38, dampingFraction: 0.88)
    }

    static func contentTransition(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .modifier(
            active: BlurFade(blur: 5, opacity: 0),
            identity: BlurFade(blur: 0, opacity: 1)
        )
    }
}

private struct BlurFade: ViewModifier {
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity)
    }
}

struct SecondaryLabel: View {
    let text: String
    var light = false

    init(_ text: String, light: Bool = false) {
        self.text = text
        self.light = light
    }

    var body: some View {
        Text(text)
            .font(DeAIDesign.font(11))
            .foregroundStyle(light ? Color.white.opacity(0.55) : DeAIDesign.muted)
    }
}

struct DeAIButtonStyle: ButtonStyle {
    var inverted = false
    var compact = false
    @DeAIReducedMotion private var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DeAIDesign.font(12, weight: .medium))
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 8 : 12)
            .foregroundStyle(inverted ? DeAIDesign.ink : DeAIDesign.paper)
            .background(inverted ? DeAIDesign.paper : DeAIDesign.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(DeAIDesign.motion(reduceMotion), value: configuration.isPressed)
    }
}

struct DeAIToggleStyle: ToggleStyle {
    var inverted = false
    @DeAIReducedMotion private var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? (inverted ? DeAIDesign.paper : DeAIDesign.ink) : (inverted ? Color.white.opacity(0.2) : DeAIDesign.ink.opacity(0.15)))
                    .frame(width: 38, height: 23)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(inverted ? DeAIDesign.ink : DeAIDesign.paper)
                            .frame(width: 17, height: 17).padding(3)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(configuration.isOn ? "关闭" : "开启")
            .accessibilityValue(configuration.isOn ? "已开启" : "已关闭")
        }
        .animation(reduceMotion ? nil : DeAIDesign.motion(false), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

struct SensitivityControl: View {
    @Binding var selection: Int
    @DeAIReducedMotion private var reduceMotion: Bool
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(["严格", "标准", "敏感"].enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(DeAIDesign.motion(reduceMotion)) { selection = index + 1 }
                } label: {
                    Text(title)
                        .font(DeAIDesign.font(12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(selection == index + 1 ? DeAIDesign.ink : DeAIDesign.paper)
                        .background {
                            if selection == index + 1 {
                                if reduceMotion {
                                    Capsule().fill(DeAIDesign.paper).transition(.opacity)
                                } else {
                                    Capsule().fill(DeAIDesign.paper)
                                        .matchedGeometryEffect(id: "selection", in: highlight)
                                }
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selection == index + 1 ? .isSelected : [])
            }
        }
        .padding(5)
        .background(DeAIDesign.ink, in: Capsule())
    }
}
