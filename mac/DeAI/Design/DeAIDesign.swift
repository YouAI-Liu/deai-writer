import AppKit
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
    // Fixed colors for the suggestion card and menu panel.
    static let ink = Color(nsColor: rgb(0x111111))
    static let paper = Color(nsColor: rgb(0xFAFAF8))
    static let canvas = adaptive("canvas", light: rgb(0xECEBE8), dark: rgb(0x161615))
    static let surface = adaptive("surface", light: rgb(0xFAFAF8), dark: rgb(0x1F1F1E))
    static let text = adaptive("text", light: rgb(0x111111), dark: rgb(0xFAFAF8))
    static let muted = adaptive("muted", light: rgb(0x6C6B67), dark: NSColor.white.withAlphaComponent(0.6))
    static let controlBackground = adaptive("controlBackground", light: rgb(0x111111), dark: rgb(0xFAFAF8))
    static let controlForeground = adaptive("controlForeground", light: rgb(0xFAFAF8), dark: rgb(0x111111))
    static let inactiveTrack = adaptive("inactiveTrack", light: rgb(0x111111).withAlphaComponent(0.15), dark: NSColor.white.withAlphaComponent(0.2))
    static let componentOutline = Color.white.opacity(0.10)
    static let darkHost = Color(nsColor: rgb(0x2B2B2B))
    static let radius: CGFloat = 24
    static let contentDuration = 0.15

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("DeAI." + name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static func underlineColor(for category: Category, appearance: NSAppearance? = nil) -> NSColor {
        let dark = (appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        switch category {
        case .grammar: return rgb(dark ? 0xC98D93 : 0xAA6970)
        case .aiToneZh: return rgb(dark ? 0xB69FC8 : 0x8D769F)
        case .aiToneEn: return rgb(dark ? 0x8FB3CB : 0x5E859F)
        case .markdown: return rgb(dark ? 0xAFB1AB : 0x82847F)
        }
    }

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
            .foregroundStyle(inverted ? DeAIDesign.ink : DeAIDesign.controlForeground)
            .background(inverted ? DeAIDesign.paper : DeAIDesign.controlBackground, in: Capsule())
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
                    .fill(configuration.isOn ? (inverted ? DeAIDesign.paper : DeAIDesign.controlBackground) : (inverted ? Color.white.opacity(0.2) : DeAIDesign.inactiveTrack))
                    .frame(width: 38, height: 23)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(inverted ? DeAIDesign.ink : DeAIDesign.controlForeground)
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
                        .foregroundStyle(selection == index + 1 ? DeAIDesign.controlBackground : DeAIDesign.controlForeground)
                        .background {
                            if selection == index + 1 {
                                if reduceMotion {
                                    Capsule().fill(DeAIDesign.controlForeground).transition(.opacity)
                                } else {
                                    Capsule().fill(DeAIDesign.controlForeground)
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
        .background(DeAIDesign.controlBackground, in: Capsule())
    }
}
