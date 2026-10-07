import AppKit

/// Watches global left-mouse-down events; when the click lands inside an
/// underline hit-rect, fires `onUnderlineClick` after ~80 ms so the target app
/// can place its caret first. Main-thread confined.
final class ClickMonitor {
    private var monitor: Any?
    private var pending: DispatchWorkItem?
    var onUnderlineClick: ((PositionedFinding, CGRect) -> Void)?
    var onOtherClick: (() -> Void)?

    /// Current hit rects (screen coords), updated on each render.
    private var hitRects: [(CGRect, PositionedFinding)] = []

    func setHitRects(_ rects: [(CGRect, PositionedFinding)]) {
        hitRects = rects
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            // for windowless events locationInWindow is in screen coordinates
            let loc = e.locationInWindow
            Task { @MainActor [weak self] in
                self?.handleClick(at: loc)
            }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        pending?.cancel()
        pending = nil
    }

    private func handleClick(at loc: CGPoint) {
        for (rect, item) in hitRects where rect.contains(loc) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onUnderlineClick?(item, rect)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
            return
        }
        onOtherClick?()
    }
}
