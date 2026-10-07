import AppKit
import QuartzCore

/// Shared underline drawing used by both the on-screen overlay
/// (`UnderlineView`) and the settings preview so they can never drift.
enum UnderlineDrawing {
    /// Underline baseline y for a glyph rect. `offset` is a position knob
    /// where the default (1) reproduces the historical `rect.minY + 1`;
    /// y = rect.minY + 2 - offset.
    static func underlineY(rect: CGRect, offset: Double) -> CGFloat {
        rect.minY + 2 - CGFloat(offset)
    }

    /// Layers for one glyph rect: an optional translucent fill plus the
    /// stroked underline. Order = fill first, stroke on top.
    static func layers(
        for finding: Finding,
        rect: CGRect,
        appearance: UnderlineAppearance
    ) -> [CALayer] {
        let a = appearance.normalized
        let style = a.style(for: finding.category)
        let baseColor = NSColor(hex: style.colorHex)
            ?? NSColor(hex: UnderlineAppearance.default.styles[
                UnderlineAppearance.key(for: finding.category)]!.colorHex)!
        let thickness = CGFloat(a.thickness)

        // tier 3 = low confidence: drawn dashed when `dimLowConfidence`
        // is on, otherwise with the category's configured shape
        let shape: UnderlineShape = (finding.tier == 3 && a.dimLowConfidence)
            ? .dashed : style.shape

        var out: [CALayer] = []
        if a.highlightFill {
            let fill = CAShapeLayer()
            let fillPath = CGPath(rect: rect, transform: nil)
            fill.path = fillPath
            fill.fillColor = baseColor.withAlphaComponent(0.12 * a.opacity).cgColor
            out.append(fill)
        }

        let y = underlineY(rect: rect, offset: a.offset)
        let line = CAShapeLayer()
        line.strokeColor = baseColor.withAlphaComponent(CGFloat(a.opacity)).cgColor
        line.fillColor = .clear
        line.lineWidth = thickness
        line.lineCap = .round
        switch shape {
        case .wavy:
            line.path = wavyPath(rect: rect, y: y, thickness: thickness)
        case .straight, .dashed, .dotted:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            line.path = path
            if shape == .dashed {
                // 2.5 * thickness so the default 1.2 reproduces the
                // historical [3, 3] dash exactly
                line.lineDashPattern = [
                    NSNumber(value: 2.5 * thickness), NSNumber(value: 2.5 * thickness),
                ]
            } else if shape == .dotted {
                // 0-length dashes + round cap render as dots
                line.lineDashPattern = [0, NSNumber(value: 2.5 * thickness)]
            }
        }
        out.append(line)
        return out
    }

    /// Wavy path; amplitude scales mildly with thickness.
    static func wavyPath(rect: CGRect, y: CGFloat, thickness: CGFloat) -> CGPath {
        let amp = max(1.6, thickness * 1.2)
        let wavelength: CGFloat = 4
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: y))
        var x = rect.minX
        var up = true
        while x < rect.maxX {
            let nx = min(x + wavelength / 2, rect.maxX)
            path.addQuadCurve(
                to: CGPoint(x: nx, y: y),
                control: CGPoint(x: (x + nx) / 2, y: y + (up ? amp : -amp))
            )
            up.toggle()
            x = nx
        }
        return path
    }
}

/// Layer-backed NSView that draws underlines as CAShapeLayers.
/// Coordinates are Cocoa (bottom-left origin) screen coordinates; the view is
/// placed in a per-screen panel whose frame equals the screen frame.
final class UnderlineView: NSView {
    /// Category colors per spec (kept for hit-testing/card tint callers that
    /// still want the canonical category color).
    static func color(for category: Category) -> CGColor {
        let style = UnderlineAppearance.default.style(for: category)
        return (NSColor(hex: style.colorHex) ?? .black).cgColor
    }

    /// Screen-space panel origin (the panel's frame origin in Cocoa coords).
    var panelOrigin: CGPoint = .zero

    /// Current drawing style; setting it repaints existing findings.
    /// (Named `underlineAppearance` — `appearance` is NSView's own property.)
    var underlineAppearance: UnderlineAppearance = .default {
        didSet { rebuildLayers() }
    }

    private var positioned: [PositionedFinding] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func render(_ items: [PositionedFinding]) {
        positioned = items
        rebuildLayers()
    }

    func clear() {
        positioned = []
        rebuildLayers()
    }

    /// Underline hit-rects (glyph rect + 2 pt) in screen coords, for click
    /// hit-testing.
    func hitRects() -> [(CGRect, PositionedFinding)] {
        var out: [(CGRect, PositionedFinding)] = []
        for item in positioned {
            for r in item.rects {
                out.append((r.insetBy(dx: -2, dy: -2), item))
            }
        }
        return out
    }

    private func rebuildLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        for item in positioned {
            for screenRect in item.rects {
                let local = screenRect.offsetBy(dx: -panelOrigin.x, dy: -panelOrigin.y)
                for sub in UnderlineDrawing.layers(
                    for: item.finding, rect: local, appearance: underlineAppearance
                ) {
                    layer?.addSublayer(sub)
                }
            }
        }
        CATransaction.commit()
    }
}
