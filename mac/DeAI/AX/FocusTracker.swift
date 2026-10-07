import AppKit
import ApplicationServices
import OSLog

/// What the tracker is currently following.
struct TextTarget {
    let element: AXElement
    let appBundleId: String
    let pid: pid_t
    /// The element's start offset in the shared document text (0 for
    /// full-text elements). Word pages expose their page slice via
    /// `AXSharedCharacterRange` while all range APIs use shared offsets.
    let baseOffset: Int
}

/// Events the AppController consumes (always invoked on the main actor).
protocol FocusTrackerDelegate: AnyObject {
    /// The set of text targets changed (new app / new focused element / Word
    /// lazy-load retry).
    func focusTargetsChanged(_ targets: [TextTarget])
    /// The text of an active target changed (AXValueChanged or key fallback).
    func focusTextMayHaveChanged(_ target: TextTarget)
    /// The selection/caret of an active target changed
    /// (AXSelectedTextChanged). The text may or may not have changed too.
    func focusSelectionMayHaveChanged(_ target: TextTarget)
    /// Geometry inputs changed (move/resize/scroll) — recompute rects.
    func focusGeometryDirty()
    /// Scroll input: AX bounds read at event time are pre-scroll (the app
    /// redraws after the event), so the controller hides underlines and
    /// re-measures on a trailing debounce instead.
    func focusScrolled()
    /// Cheap per-tick hook for the safety timer — the controller uses it to
    /// spot stale underlines without a full re-check.
    func focusSafetyTick()
    /// Everything torn down (app switch to an app we don't serve).
    func focusLost()
    /// The tracked window was (de)miniaturized — hide/show overlay.
    func focusWindowMiniaturized(_ miniaturized: Bool)
}

/// Follows the frontmost application and its focused text element(s).
///
/// Reliability strategy: real AX observers where they work (AXValueChanged /
/// AXFocusedUIElementChanged / move / resize), plus global event monitor
/// fallbacks (keyUp → text re-read, scrollWheel/leftMouseUp → geometry) and a
/// 750 ms safety timer that re-validates geometry cheaply. No other polling —
/// idle CPU stays ~0. Main-thread confined: all entry points run on main.
final class FocusTracker {
    private let log = Logger(subsystem: "com.local.deai", category: "ax")

    weak var delegate: FocusTrackerDelegate?
    var shouldServe: (String) -> Bool = { _ in true }

    private(set) var currentApp: NSRunningApplication?
    private(set) var targets: [TextTarget] = []

    private var observer: AXObserver?
    private var observedElements: [AXUIElement] = []
    private var workspaceObserver: NSObjectProtocol?
    private var eventMonitors: [Any] = []
    private var safetyTimer: Timer?
    private var lastElementFrames: [CGRect] = []
    private var lastWindowFrame: CGRect?

    // For the C callback — the tracker is a stable, app-lifetime object.
    private var refconProxy: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    func start() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            Task { @MainActor in self?.appActivated(app) }
        }

        // Fallbacks for apps where AX notifications are unreliable.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyUp, handler: { [weak self] _ in
            Task { @MainActor in self?.scheduleTextReread() }
        }) {
            eventMonitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.scrollWheel, .leftMouseUp],
            handler: { [weak self] event in
                // delivered on the registering (main) thread — no async hop:
                // the scroll hide must beat the target app's repaint
                if event.type == .scrollWheel {
                    self?.scrollDirty()
                } else {
                    self?.geometryDirty()
                }
            }
        ) {
            eventMonitors.append(m)
        }

        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.safetyTick() }
        }

        if let front = NSWorkspace.shared.frontmostApplication {
            appActivated(front)
        }
    }

    /// Re-evaluate the frontmost app (e.g. after the user toggles the current
    /// app's enabled state).
    func refresh() {
        if let front = NSWorkspace.shared.frontmostApplication {
            appActivated(front)
        }
    }

    func stop() {
        if let o = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        workspaceObserver = nil
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
        safetyTimer?.invalidate()
        safetyTimer = nil
        tearDownApp()
    }

    // MARK: - app switching

    private func appActivated(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return // never follow ourselves
        }
        tearDownApp()
        currentApp = app
        let bundleId = app.bundleIdentifier ?? ""
        guard shouldServe(bundleId) else {
            delegate?.focusLost()
            return
        }
        let appEl = AXElement.application(pid: app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl.raw, 0.25)

        var observer: AXObserver?
        // (observer is created on the main thread; callback hops back to main)
        let err = AXObserverCreate(app.processIdentifier, axCallback, &observer)
        guard err == .success, let observer else {
            log.error("AXObserverCreate failed for \(bundleId): \(err.rawValue)")
            delegate?.focusLost()
            return
        }
        self.observer = observer
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        subscribe(appEl, notifications: [
            kAXFocusedUIElementChangedNotification,
            kAXFocusedWindowChangedNotification,
        ])
        observedElements.append(appEl.raw)
        resolveTargets()
    }

    private func tearDownApp() {
        if let observer {
            for el in observedElements {
                for name in Self.elementNotifications + Self.appNotifications
                    + Self.windowNotifications {
                    AXObserverRemoveNotification(observer, el, name as CFString)
                }
            }
            CFRunLoopGetMain().map {
                CFRunLoopRemoveSource(
                    $0,
                    AXObserverGetRunLoopSource(observer),
                    .defaultMode
                )
            }
        }
        observer = nil
        observedElements = []
        targets = []
        mayPageTargets = false
        resolveWorkItem?.cancel()
        resolveWorkItem = nil
        lastElementFrames = []
        lastWindowFrame = nil
    }

    private static let appNotifications = [
        kAXFocusedUIElementChangedNotification,
        kAXFocusedWindowChangedNotification,
    ]
    private static let elementNotifications = [
        kAXValueChangedNotification,
        kAXSelectedTextChangedNotification,
        kAXUIElementDestroyedNotification,
    ]
    private static let windowNotifications = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private func subscribe(_ el: AXElement, notifications: [String]) {
        guard let observer else { return }
        for name in notifications {
            let err = AXObserverAddNotification(
                observer, el.raw, name as CFString, refconProxy
            )
            if err != .success && err != .notificationAlreadyRegistered {
                log.debug("subscribe \(name) failed: \(err.rawValue)")
            }
        }
    }

    /// Called from the AXObserver callback (arbitrary thread) — hops
    /// straight to the main queue.
    fileprivate func handleAXNotification(_ element: AXUIElement, name: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch name {
            case kAXFocusedUIElementChangedNotification,
                 kAXFocusedWindowChangedNotification:
                self.resolveTargets()
            case kAXValueChangedNotification:
                if let t = self.targets.first(where: {
                    CFEqual($0.element.raw, element)
                }) {
                    self.delegate?.focusTextMayHaveChanged(t)
                } else {
                    self.resolveTargets()
                }
            case kAXSelectedTextChangedNotification:
                if let t = self.targets.first(where: {
                    CFEqual($0.element.raw, element)
                }) {
                    self.delegate?.focusSelectionMayHaveChanged(t)
                } else {
                    self.resolveTargets()
                }
            case kAXMovedNotification, kAXResizedNotification:
                self.geometryDirty()
            case kAXUIElementDestroyedNotification:
                self.resolveTargets()
            case kAXWindowMiniaturizedNotification:
                self.delegate?.focusWindowMiniaturized(true)
            case kAXWindowDeminiaturizedNotification:
                self.delegate?.focusWindowMiniaturized(false)
            default:
                break
            }
        }
    }

    // MARK: - target resolution

    /// Re-resolve text targets for the current app and subscribe to the
    /// element-level notifications on each. Word gets the async path
    /// (accessibility nudge + retries).
    func resolveTargets() {
        guard let app = currentApp,
              let bundleId = app.bundleIdentifier,
              let pid = currentApp?.processIdentifier else { return }
        let appEl = AXElement.application(pid: pid)
        let resolver = TextTargetResolver()
        resolver.resolveAsync(appElement: appEl, bundleId: bundleId) {
            [weak self] resolved in
            guard let self, self.currentApp?.processIdentifier == pid else { return }
            let win: AXUIElement? = appEl.attribute(kAXFocusedWindowAttribute)

            // Prune subscriptions on elements that are gone (e.g. Word page
            // elements destroyed by reflow) — otherwise `observedElements`
            // grows unboundedly over a long session.
            if let observer = self.observer {
                let keep = self.observedElements.filter { el in
                    CFEqual(el, appEl.raw)
                        || (win.map { CFEqual(el, $0) } ?? false)
                        || resolved.contains { CFEqual($0.element.raw, el) }
                }
                for el in self.observedElements
                where !keep.contains(where: { CFEqual($0, el) }) {
                    for name in Self.elementNotifications + Self.windowNotifications {
                        AXObserverRemoveNotification(observer, el, name as CFString)
                    }
                }
                self.observedElements = keep
            }

            for t in resolved {
                self.subscribe(t.element, notifications: Self.elementNotifications)
                if !self.observedElements.contains(where: { CFEqual($0, t.element.raw) }) {
                    self.observedElements.append(t.element.raw)
                }
            }
            // window move/resize → geometry refresh
            if let win {
                self.subscribe(AXElement(win), notifications: Self.windowNotifications)
                if !self.observedElements.contains(where: { CFEqual($0, win) }) {
                    self.observedElements.append(win)
                }
            }
            self.targets = resolved
            // scrolling can bring different pages into view in sliced-text
            // apps (Word) — those need periodic target re-resolution
            self.mayPageTargets = bundleId == Self.wordBundleId
                || resolved.count > 1
                || resolved.contains { $0.baseOffset > 0 }
            self.snapshotGeometry()
            self.delegate?.focusTargetsChanged(resolved)
        }
    }

    // MARK: - fallbacks

    private static let wordBundleId = "com.microsoft.Word"
    private var mayPageTargets = false
    private var resolveWorkItem: DispatchWorkItem?

    /// Geometry changed (move/resize/mouse-up): refresh rects, and in apps
    /// whose targets are slices of a shared text (Word pages) re-resolve
    /// targets so newly visible pages get covered and off-screen ones are
    /// dropped (debounced 300 ms).
    private func geometryDirty() {
        delegate?.focusGeometryDirty()
        scheduleTargetResolve()
    }

    /// Scroll input: bounds read right now are pre-scroll, so the delegate
    /// hides + re-measures on a trailing debounce; sliced-text targets are
    /// still re-resolved after 300 ms (the resolve is followed by a
    /// re-measure in `focusTargetsChanged`).
    private func scrollDirty() {
        delegate?.focusScrolled()
        scheduleTargetResolve()
    }

    private func scheduleTargetResolve() {
        guard mayPageTargets else { return }
        resolveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.resolveTargets()
        }
        resolveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private var rereadWorkItem: DispatchWorkItem?

    private func scheduleTextReread() {
        rereadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for t in self.targets {
                self.delegate?.focusTextMayHaveChanged(t)
            }
        }
        rereadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func snapshotGeometry() {
        lastElementFrames = targets.compactMap { $0.element.frame }
        if let app = currentApp {
            let win: AXElement? = AXElement.application(pid: app.processIdentifier)
                .attribute(kAXFocusedWindowAttribute)
            lastWindowFrame = win?.frame
        }
    }

    /// 750 ms safety net: recompute geometry only when the element/window
    /// frames actually moved.
    private func safetyTick() {
        guard !targets.isEmpty else { return }
        let frames = targets.compactMap { $0.element.frame }
        var windowFrame: CGRect?
        if let app = currentApp {
            let win: AXElement? = AXElement.application(pid: app.processIdentifier)
                .attribute(kAXFocusedWindowAttribute)
            windowFrame = win?.frame
        }
        if frames != lastElementFrames || windowFrame != lastWindowFrame {
            lastElementFrames = frames
            lastWindowFrame = windowFrame
            geometryDirty()
        }
        // Element/window frames don't move during scroll — let the
        // controller spot stale underline rects per target.
        delegate?.focusSafetyTick()
    }
}

private func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon)
        .takeUnretainedValue()
    tracker.handleAXNotification(element, name: notification as String)
}
