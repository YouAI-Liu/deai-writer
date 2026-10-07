import AppKit
import OSLog

/// Manages one borderless, transparent, non-activating NSPanel per screen that
/// currently has underline rects. Panels are reused across renders.
/// Main-thread confined.
final class OverlayWindow {
    private let log = Logger(subsystem: "com.local.deai", category: "overlay")

    private var panels: [NSScreen: (panel: NSPanel, view: UnderlineView)] = [:]
    private(set) var rendered: [PositionedFinding] = []

    /// Pushed into every `UnderlineView`; a change repaints existing
    /// underlines without re-checking.
    var appearance: UnderlineAppearance = .default {
        didSet {
            for (_, entry) in panels { entry.view.underlineAppearance = appearance }
        }
    }

    /// Redraw underlines for `items` (screen-space Cocoa rects).
    /// Returns hit-rects in screen coordinates for click handling.
    @discardableResult
    func render(_ items: [PositionedFinding]) -> [(CGRect, PositionedFinding)] {
        rendered = items
        let t0 = CFAbsoluteTimeGetCurrent()

        // group rects by the screen they land on
        var byScreen: [NSScreen: [PositionedFinding]] = [:]
        let screens = Set(NSScreen.screens)
        for item in items {
            var perScreen: [NSScreen: [CGRect]] = [:]
            for r in item.rects {
                for screen in screens where screen.frame.intersects(r) {
                    perScreen[screen, default: []].append(r)
                }
            }
            for (screen, rects) in perScreen {
                byScreen[screen, default: []].append(
                    PositionedFinding(finding: item.finding, rects: rects)
                )
            }
        }

        var used: Set<NSScreen> = []
        var hitRects: [(CGRect, PositionedFinding)] = []
        for (screen, list) in byScreen {
            let entry = panel(for: screen)
            entry.view.panelOrigin = screen.frame.origin
            entry.view.render(list)
            entry.panel.orderFront(nil)
            used.insert(screen)
            hitRects += entry.view.hitRects().map { ($0.0, $0.1) }
        }
        // hide panels on screens that no longer have rects
        for (screen, entry) in panels where !used.contains(screen) {
            entry.panel.orderOut(nil)
            entry.view.clear()
        }

        log.debug("render: \(items.count) findings -> \(byScreen.count) panels in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        return hitRects
    }

    func hideAll() {
        rendered = []
        for (_, entry) in panels {
            entry.panel.orderOut(nil)
            entry.view.clear()
        }
    }

    /// Debug/QA: render each panel's underline view to PNG files plus a
    /// `manifest.json` (panel frames + item counts) inside `dir`.
    /// Own-window rendering — needs no screen-recording permission.
    func dumpPanelImages(to dir: URL) {
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        var manifest: [[String: Any]] = []
        for (i, (screen, entry)) in panels.enumerated() {
            let view = entry.view
            let size = view.bounds.size
            guard size.width > 0, size.height > 0,
                  let rep = NSBitmapImageRep(
                      bitmapDataPlanes: nil,
                      pixelsWide: Int(size.width),
                      pixelsHigh: Int(size.height),
                      bitsPerSample: 8,
                      samplesPerPixel: 4,
                      hasAlpha: true,
                      isPlanar: false,
                      colorSpaceName: .deviceRGB,
                      bytesPerRow: 0,
                      bitsPerPixel: 0
                  ),
                  let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext
            else { continue }
            // flip so the PNG matches top-down screen orientation
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            view.layer?.render(in: ctx)
            let url = dir.appendingPathComponent("panel-\(i).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            manifest.append([
                "panel": i,
                "screenFrame": [
                    screen.frame.origin.x, screen.frame.origin.y,
                    screen.frame.width, screen.frame.height,
                ],
            ])
        }
        if let data = try? JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted]
        ) {
            try? data.write(to: dir.appendingPathComponent("manifest.json"))
        }
    }

    private func panel(for screen: NSScreen) -> (panel: NSPanel, view: UnderlineView) {
        if let existing = panels[screen] {
            if existing.panel.frame != screen.frame {
                existing.panel.setFrame(screen.frame, display: false)
                existing.view.frame = NSRect(origin: .zero, size: screen.frame.size)
            }
            return existing
        }
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        let view = UnderlineView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.underlineAppearance = appearance
        panel.contentView = view
        panels[screen] = (panel, view)
        return (panel, view)
    }
}
