import AppKit
import QuartzCore

/// Layer-backed NSView that draws underlines as CAShapeLayers.
/// Coordinates are Cocoa (bottom-left origin) screen coordinates; the view is
/// placed in a per-screen panel whose frame equals the screen frame.
final class UnderlineView: NSView {
    /// Category colors per spec.
    static func color(for category: Category) -> CGColor {
        switch category {
        case .grammar: return NSColor(srgbRed: 0.898, green: 0.282, blue: 0.302, alpha: 1).cgColor // #E5484D
        case .aiToneZh: return NSColor(srgbRed: 0.557, green: 0.306, blue: 0.776, alpha: 1).cgColor // #8E4EC6
        case .aiToneEn: return NSColor(srgbRed: 0.0, green: 0.565, blue: 1.0, alpha: 1).cgColor // #0090FF
        case .markdown: return NSColor(srgbRed: 0.545, green: 0.553, blue: 0.596, alpha: 1).cgColor // #8B8D98
        }
    }

    /// Screen-space panel origin (the panel's frame origin in Cocoa coords).
    var panelOrigin: CGPoint = .zero

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
                let layer = underlineLayer(for: item.finding, rect: local)
                self.layer?.addSublayer(layer)
            }
        }
        CATransaction.commit()
    }

    private func underlineLayer(for f: Finding, rect: CGRect) -> CALayer {
        // underline 2pt high at the bottom of the rect (rect.minY + 1, Cocoa)
        let y = rect.minY + 1
        let path = CGMutablePath()
        let shape = CAShapeLayer()
        shape.strokeColor = Self.color(for: f.category)
        shape.fillColor = .clear
        shape.lineWidth = 1.2
        shape.lineCap = .round
        if f.tier == 3 {
            shape.lineDashPattern = [3, 3]
        }
        if f.category == .grammar {
            // wavy underline
            let amp: CGFloat = 1.6
            let wavelength: CGFloat = 4
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
        } else {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        shape.path = path
        return shape
    }
}
