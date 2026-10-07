import AppKit
import QuartzCore

/// Layer-backed NSView that draws underlines as CAShapeLayers.
/// Coordinates are Cocoa (bottom-left origin) screen coordinates; the view is
/// placed in a per-screen panel whose frame equals the screen frame.
final class UnderlineView: NSView {
    static func color(for category: Category, appearance: NSAppearance? = nil) -> CGColor {
        DeAIDesign.underlineColor(for: category, appearance: appearance).cgColor
    }

    /// Screen-space panel origin (the panel's frame origin in Cocoa coords).
    var panelOrigin: CGPoint = .zero

    private var positioned: [PositionedFinding] = []
    private var appearanceObservation: NSKeyValueObservation?
    #if DEBUG
    var previewAppearance: NSAppearance? { didSet { refreshColors() } }
    #endif

    private var colorAppearance: NSAppearance? {
        #if DEBUG
        return previewAppearance
        #else
        return nil
        #endif
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            if Thread.isMainThread {
                self?.refreshColors()
            } else {
                DispatchQueue.main.async { [weak self] in self?.refreshColors() }
            }
        }
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

    private func refreshColors() {
        let categories = positioned.flatMap { item in item.rects.map { _ in item.finding.category } }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, category) in zip(layer?.sublayers ?? [], categories) {
            (layer as? CAShapeLayer)?.strokeColor = Self.color(for: category, appearance: colorAppearance)
        }
        CATransaction.commit()
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
        shape.strokeColor = Self.color(for: f.category, appearance: colorAppearance)
        shape.fillColor = .clear
        shape.lineWidth = 1.4
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
