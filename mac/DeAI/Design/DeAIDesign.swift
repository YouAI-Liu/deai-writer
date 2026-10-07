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
    // Claude-style palette (tokens mirror the Claude desktop theme) —
    // every surface follows the system appearance.
    static let background = adaptive("background", light: rgb(0xFAF9F5), dark: rgb(0x262624))
    static let sidebar = adaptive("sidebar", light: rgb(0xF5F4ED), dark: rgb(0x1F1E1D))
    static let track = adaptive("track", light: rgb(0xF0EEE6), dark: rgb(0x141413))
    static let surface = adaptive("surface", light: rgb(0xFFFFFF), dark: rgb(0x30302E))
    static let border = adaptive("border", light: rgb(0x1F1E1D).withAlphaComponent(0.15), dark: rgb(0xDEDCD1).withAlphaComponent(0.15))
    static let text = adaptive("text", light: rgb(0x141413), dark: rgb(0xFAF9F5))
    static let secondaryText = adaptive("secondaryText", light: rgb(0x3D3D3A), dark: rgb(0xC2C0B6))
    static let muted = adaptive("muted", light: rgb(0x73726C), dark: rgb(0x9C9A92))
    static let accent = adaptive("accent", light: rgb(0xC6613F), dark: rgb(0xD97757))
    static let danger = adaptive("danger", light: rgb(0xB53333), dark: rgb(0xDD5353))
    static let onAccent = Color.white
    static let inactiveTrack = adaptive("inactiveTrack", light: rgb(0x141413).withAlphaComponent(0.15), dark: rgb(0xFAF9F5).withAlphaComponent(0.15))
    /// Accent green for the card's accept check (Office-style).
    static let acceptGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let radius: CGFloat = 12
    static let controlRadius: CGFloat = 8
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

    static func titleFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
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

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(DeAIDesign.font(11))
            .foregroundStyle(DeAIDesign.muted)
    }
}

struct DeAIButtonStyle: ButtonStyle {
    var secondary = false
    var compact = false
    @DeAIReducedMotion private var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DeAIDesign.font(12, weight: .medium))
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 8 : 12)
            .foregroundStyle(secondary ? DeAIDesign.text : DeAIDesign.onAccent)
            .background(secondary ? DeAIDesign.surface : DeAIDesign.accent, in: Capsule())
            .overlay {
                if secondary {
                    Capsule().strokeBorder(DeAIDesign.border, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(DeAIDesign.motion(reduceMotion), value: configuration.isPressed)
    }
}

struct DeAIToggleStyle: ToggleStyle {
    /// Set false for rows that lay out their own label — unlike
    /// `.labelsHidden()` (which only affects macOS 15+ environments), this
    /// reliably suppresses the label on our deployment target (14.0).
    var showsLabel = true
    @DeAIReducedMotion private var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            if showsLabel {
                configuration.label
            }
            Spacer(minLength: 12)
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? DeAIDesign.accent : DeAIDesign.inactiveTrack)
                    .frame(width: 38, height: 23)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(DeAIDesign.onAccent)
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

/// Small capsule chip toggle for the per-kind check selectors,
/// unlike the system .checkbox which renders a fixed accent-blue.
struct DeAIChipToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @DeAIReducedMotion private var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(DeAIDesign.font(9, weight: .bold))
                }
                configuration.label
            }
            .font(DeAIDesign.font(11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // disabled: neutral track fill + muted text instead of fading
            // the accent (white-on-pale-accent was unreadable)
            .foregroundStyle(
                !isEnabled ? DeAIDesign.text
                    : configuration.isOn ? DeAIDesign.onAccent : DeAIDesign.muted
            )
            .background(
                !isEnabled ? DeAIDesign.track
                    : configuration.isOn ? DeAIDesign.accent : DeAIDesign.surface,
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    DeAIDesign.border,
                    lineWidth: isEnabled && configuration.isOn ? 0 : 1
                )
            }
        }
        .buttonStyle(.plain)
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
                        .foregroundStyle(selection == index + 1 ? DeAIDesign.text : DeAIDesign.secondaryText)
                        .background {
                            if selection == index + 1 {
                                let capsule = Capsule().fill(DeAIDesign.surface)
                                if reduceMotion {
                                    capsule.transition(.opacity)
                                } else {
                                    capsule.matchedGeometryEffect(id: "selection", in: highlight)
                                }
                            }
                        }
                        .overlay {
                            if selection == index + 1 {
                                Capsule().strokeBorder(DeAIDesign.border, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selection == index + 1 ? .isSelected : [])
            }
        }
        .padding(5)
        .background(DeAIDesign.track, in: Capsule())
    }
}
