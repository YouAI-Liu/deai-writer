import AppKit
import SwiftUI

/// Underline stroke shapes selectable per check category.
public enum UnderlineShape: String, Codable, CaseIterable {
    case straight
    case wavy
    case dashed
    case dotted

    public var displayName: String {
        switch self {
        case .straight: return "直线"
        case .wavy: return "波浪线"
        case .dashed: return "虚线"
        case .dotted: return "点线"
        }
    }
}

/// Color (sRGB hex, e.g. "#E5484D") plus shape for one category.
public struct UnderlineStyle: Codable, Equatable {
    public var colorHex: String
    public var shape: UnderlineShape

    public init(colorHex: String, shape: UnderlineShape) {
        self.colorHex = colorHex
        self.shape = shape
    }
}

/// Everything user-tunable about how underlines are drawn. Persisted inside
/// `deai.settings.v1`; `style(for:)` falls back per key so partial/stale
/// dictionaries still produce the classic look.
public struct UnderlineAppearance: Codable, Equatable {
    /// Keys: "grammar", "aiToneZh", "aiToneEn", "markdown".
    public var styles: [String: UnderlineStyle]
    /// Stroke width, 0.5...4.
    public var thickness: Double
    /// Stroke alpha, 0.2...1.
    public var opacity: Double
    /// Vertical position knob, -2...4. The line is drawn at
    /// `rect.minY + 2 - offset`, so the default (1) reproduces the historical
    /// `minY + 1`; larger values pull the line down below the glyph rect.
    public var offset: Double
    /// When true (default), tier-3 (低置信度) findings are always drawn
    /// dashed regardless of their category shape.
    public var dimLowConfidence: Bool
    /// Also paint a translucent fill (category color at 0.12*opacity) over
    /// the glyph rect.
    public var highlightFill: Bool

    public init(
        styles: [String: UnderlineStyle],
        thickness: Double = 1.2,
        opacity: Double = 1,
        offset: Double = 1,
        dimLowConfidence: Bool = true,
        highlightFill: Bool = false
    ) {
        self.styles = styles
        self.thickness = thickness
        self.opacity = opacity
        self.offset = offset
        self.dimLowConfidence = dimLowConfidence
        self.highlightFill = highlightFill
    }

    /// Default: all categories follow the theme-aware palette
    /// (`colorHex == ""` resolves to `DeAIDesign.underlineColor`); grammar
    /// stays wavy, the rest straight.
    public static let `default` = UnderlineAppearance(
        styles: [
            "grammar": UnderlineStyle(colorHex: "", shape: .wavy),
            "aiToneZh": UnderlineStyle(colorHex: "", shape: .straight),
            "aiToneEn": UnderlineStyle(colorHex: "", shape: .straight),
            "markdown": UnderlineStyle(colorHex: "", shape: .straight),
        ]
    )

    static func key(for category: Category) -> String {
        switch category {
        case .grammar: return "grammar"
        case .aiToneZh: return "aiToneZh"
        case .aiToneEn: return "aiToneEn"
        case .markdown: return "markdown"
        }
    }

    /// Style for `category`, falling back to the built-in default per key.
    public func style(for category: Category) -> UnderlineStyle {
        let key = Self.key(for: category)
        return styles[key] ?? Self.default.styles[key]!
    }

    /// Clamps the global knobs into their supported ranges.
    public var normalized: UnderlineAppearance {
        var copy = self
        copy.thickness = min(max(thickness, 0.5), 4)
        copy.opacity = min(max(opacity, 0.2), 1)
        copy.offset = min(max(offset, -2), 4)
        return copy
    }
}

public extension Category {
    var displayName: String {
        switch self {
        case .grammar: return "语法"
        case .aiToneZh: return "中文 AI 腔"
        case .aiToneEn: return "英文 AI 腔"
        case .markdown: return "Markdown 残留"
        }
    }
}

public extension NSColor {
    /// Parses "#RRGGBB" / "RRGGBB" (sRGB). Returns nil on malformed input.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// "#RRGGBB" in the sRGB space; nil when conversion fails.
    var hexString: String? {
        guard let c = usingColorSpace(.sRGB) else { return nil }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

public extension Color {
    init(hex: String) {
        self.init(NSColor(hex: hex) ?? .black)
    }

    /// "#RRGGBB" for this color in sRGB (nil on conversion failure).
    var hexString: String? {
        NSColor(self).hexString
    }
}
