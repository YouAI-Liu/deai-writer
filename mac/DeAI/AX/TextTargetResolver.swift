import ApplicationServices
import OSLog

/// Finds the editable text element(s) inside the frontmost app.
///
/// Fast path: AXFocusedUIElement with role AXTextArea/AXTextField/AXComboBox
/// and a String AXValue. Otherwise BFS the focused window's descendants
/// (≤3000 nodes, depth ≤14) collecting AXTextArea elements — Word puts the
/// body at depth ~10 (AXDescription "页面 N 内容", one per page), preferring
/// AXFocused == true, else all text areas intersecting the focused window
/// frame (cap 6).
///
/// Word special case (documented in AGENTS.md): Word's AX tree doesn't
/// materialize the document body until accessibility is nudged. We set
/// AXManualAccessibility + AXEnhancedUserInterface on the app element for
/// com.microsoft.Word only, then retry with backoff.
final class TextTargetResolver {
    private let log = Logger(subsystem: "com.local.deai", category: "ax")

    private static let wordBundleId = "com.microsoft.Word"
    private static let editableRoles: Set<String> = [
        kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole,
    ]
    private static let retryDelays: [TimeInterval] = [0.15, 0.5, 1.5]
    private static let maxNodes = 3000
    private static let maxDepth = 14
    private static let maxTargets = 6

    /// Synchronous resolve (no retry). Retries are driven by `resolveAsync`.
    func resolve(appElement: AXElement, bundleId: String) -> [TextTarget] {
        let pid = appElement.pid ?? 0
        if let t = focusedEditable(appElement: appElement, bundleId: bundleId, pid: pid) {
            // A focused page slice that scrolled out of the viewport must not
            // keep the target slot (BUG-04): Word keeps AX focus on the last
            // interacted page while it is off-screen. Fall through to the
            // viewport-based scan in that case.
            let stale = isSharedSlice(t.element) && !inViewport(
                t.element, appElement: appElement
            )
            if !stale { return [t] }
        }
        return scanTextAreas(appElement: appElement, bundleId: bundleId, pid: pid)
    }

    /// Resolve with Word's accessibility nudge + retries.
    func resolveAsync(
        appElement: AXElement,
        bundleId: String,
        completion: @escaping @MainActor ([TextTarget]) -> Void
    ) {
        let first = resolve(appElement: appElement, bundleId: bundleId)
        if !first.isEmpty || bundleId != Self.wordBundleId {
            Task { @MainActor in completion(first) }
            return
        }
        // Word: prod the app into building its accessibility tree. This is
        // deliberately scoped to com.microsoft.Word — setting these on other
        // apps can be expensive or alter behavior.
        _ = appElement.set("AXManualAccessibility", kCFBooleanTrue!)
        _ = appElement.set("AXEnhancedUserInterface", kCFBooleanTrue!)
        log.info("Word: set AXManualAccessibility/AXEnhancedUserInterface, retrying")
        retryWord(appElement: appElement, bundleId: bundleId, attempt: 0, completion: completion)
    }

    private func retryWord(
        appElement: AXElement,
        bundleId: String,
        attempt: Int,
        completion: @escaping @MainActor ([TextTarget]) -> Void
    ) {
        let delay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            materializeWordPages(appElement: appElement)
            let found = resolve(appElement: appElement, bundleId: bundleId)
            if !found.isEmpty || attempt + 1 >= Self.retryDelays.count {
                completion(found)
            } else {
                retryWord(
                    appElement: appElement,
                    bundleId: bundleId,
                    attempt: attempt + 1,
                    completion: completion
                )
            }
        }
    }

    // MARK: - internals

    /// Word materializes its per-page AXTextArea elements lazily: the
    /// document AXLayoutArea reports no AXChildren until something probes
    /// inside the viewport (verified: hit-testing a point in the window
    /// materializes "页面 N 内容" elements, which then also appear under
    /// AXChildren). Hit-test a small grid in the lower half of the focused
    /// window — the document body lives there, below the ribbon.
    private func materializeWordPages(appElement: AXElement) {
        guard let window: AXUIElement = appElement.attribute(kAXFocusedWindowAttribute),
              let frame = AXElement(window).frame else { return }
        let system = AXUIElementCreateSystemWide()
        for fy in stride(from: 0.45, through: 0.85, by: 0.1) {
            for fx in stride(from: 0.3, through: 0.7, by: 0.1) {
                var out: AXUIElement?
                let px = Float(frame.minX + frame.width * fx)
                let py = Float(frame.minY + frame.height * fy)
                guard AXUIElementCopyElementAtPosition(system, px, py, &out) == .success,
                      let hit = out else { continue }
                var hitPid: pid_t = 0
                guard AXUIElementGetPid(hit, &hitPid) == .success,
                      hitPid == appElement.pid else { continue }
                if AXElement(hit).role == kAXTextAreaRole { return }
            }
        }
    }

    private func focusedEditable(appElement: AXElement, bundleId: String, pid: pid_t)
        -> TextTarget?
    {
        guard let focused: AXUIElement = appElement.attribute(kAXFocusedUIElementAttribute)
        else { return nil }
        let el = AXElement(focused)
        // descend through simple containers (e.g. text field inside a cell)
        var current = el
        for _ in 0..<4 {
            guard let role = current.role else { return nil }
            if Self.editableRoles.contains(role) {
                // never touch secure fields
                if current.subrole == "AXSecureTextField" { return nil }
                if current.stringValue != nil {
                    return TextTarget(
                        element: current,
                        appBundleId: bundleId,
                        pid: pid,
                        baseOffset: baseOffset(of: current)
                    )
                }
                return nil
            }
            guard let next: AXUIElement = current.attribute(kAXFocusedUIElementAttribute),
                  !CFEqual(next, current.raw) else { return nil }
            current = AXElement(next)
        }
        return nil
    }

    /// BFS for AXTextArea elements under the focused window.
    private func scanTextAreas(appElement: AXElement, bundleId: String, pid: pid_t)
        -> [TextTarget]
    {
        guard let window: AXUIElement = appElement.attribute(kAXFocusedWindowAttribute)
        else { return [] }
        let windowEl = AXElement(window)
        // a missing frame means "unknown", not empty — pass nil
        let windowFrame = windowEl.frame.flatMap { $0.isNull ? nil : $0 }

        var areas: [AXElement] = []
        var visited = 0
        var queue: [(AXElement, Int)] = [(windowEl, 0)]
        var head = 0
        while head < queue.count, visited < Self.maxNodes {
            let (el, depth) = queue[head]
            head += 1
            visited += 1
            if el.subrole == "AXSecureTextField" { continue }
            if el.role == kAXTextAreaRole, el.stringValue != nil {
                areas.append(el)
                continue // don't descend into a text area
            }
            guard depth < Self.maxDepth else { continue }
            for child in el.children {
                queue.append((child, depth + 1))
            }
        }

        // Pages whose frame intersects the visible viewport (nearest
        // AXScrollArea ancestor ∩ window) become targets regardless of AX
        // focus — scrolling a Word doc brings new pages into view while the
        // AX-focused page may already be off screen (BUG-04). The focused
        // page is kept only if it is still visible. Elements without any
        // frame are kept only when focused (no geometry to judge).
        var chosen: [AXElement] = []
        var focusedVisible: [AXElement] = []
        for area in areas {
            let visible: Bool
            if let f = area.frame {
                let vp = area.viewportFrame(windowFrame: windowFrame)
                visible = vp.map { f.intersects($0) } ?? true
            } else {
                visible = area.isFocused
            }
            guard visible else { continue }
            if area.isFocused {
                focusedVisible.append(area)
            } else {
                chosen.append(area)
            }
        }
        return (focusedVisible + chosen).prefix(Self.maxTargets).map {
            TextTarget(
                element: $0,
                appBundleId: bundleId,
                pid: pid,
                baseOffset: baseOffset(of: $0)
            )
        }
    }

    /// Start of the element's slice in its shared document text
    /// (`AXSharedCharacterRange.location`); 0 for full-text elements.
    private func baseOffset(of el: AXElement) -> Int {
        el.sharedCharacterRange?.location ?? 0
    }

    /// True when the element's AXValue is a slice of a larger shared text
    /// (Word pages): `AXSharedCharacterRange` length < `AXNumberOfCharacters`.
    private func isSharedSlice(_ el: AXElement) -> Bool {
        guard let s = el.sharedCharacterRange else { return false }
        if let n = el.numberOfCharacters { return s.length < n }
        return true
    }

    /// Whether the element's frame intersects its visible viewport
    /// (nearest AXScrollArea ancestor ∩ focused window, AX coordinates).
    private func inViewport(_ el: AXElement, appElement: AXElement) -> Bool {
        guard let f = el.frame else { return true }
        let win: AXUIElement? = appElement.attribute(kAXFocusedWindowAttribute)
        let winFrame = win.flatMap { AXElement($0).frame }
            .flatMap { $0.isNull ? nil : $0 }
        guard let vp = el.viewportFrame(windowFrame: winFrame) else { return true }
        return f.intersects(vp)
    }
}
