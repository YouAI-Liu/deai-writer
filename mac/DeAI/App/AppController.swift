import AppKit
import ApplicationServices
import Carbon
import Combine
import OSLog
import SwiftUI

/// Owns the whole runtime: permission flow, focus tracking, checking,
/// overlay rendering, suggestion card, settings side-effects, and the
/// debug state dump. Main-thread confined: every entry point (FocusTracker
/// delegate callbacks, CheckService results, monitor handlers) already
/// arrives on the main queue.
final class AppController: NSObject, ObservableObject, FocusTrackerDelegate {
    private let log = Logger(subsystem: "com.local.deai", category: "overlay")

    let settings = AppSettings()

    /// Bundle id of the app we are currently tracking (for menu labels).
    @Published private(set) var frontmostBundleId: String?

    private let tracker = FocusTracker()
    private let checkService = CheckService()
    private let overlay = OverlayWindow()
    private let card = SuggestionCardPanel()
    private let clickMonitor = ClickMonitor()
    private let rewritePanel = RewritePanel()
    private let llmClient = LLMClient()
    private let hotkey = GlobalHotkey()

    /// What the rewrite panel is operating on. Holds the element itself —
    /// Word page keys (CFHash) change on scroll, so never re-derive it.
    private struct RewriteContext {
        let element: AXElement
        let baseOffset: Int
        /// element-local UTF-16 scope
        let start: Int
        let end: Int
        let original: String
        let hints: [RewriteHint]
        /// app the panel was opened in — closed on frontmost-app change
        let bundleId: String
    }

    private var rewriteContext: RewriteContext?
    private var rewriteTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

    private struct TargetState {
        var target: TextTarget
        var text: String = ""
        var findings: [Finding] = []
        var positioned: [PositionedFinding] = []
        var readMs: Double = 0
        var checkMs: Double = 0
        var nonGrammarMs: Double = 0
        var grammarMs: Double = 0
        var filterMs: Double = 0
        var grammarHits: Int = 0
        var grammarMisses: Int = 0
    }

    /// tag (CFHash of the AX element) -> state
    private var states: [UInt64: TargetState] = [:]
    /// last collapsed caret position per tag (element-local), for the
    /// caret-based card trigger
    private var lastCarets: [UInt64: Int] = [:]

    private var permissionWindow: NSWindow?
    private var permissionTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var lexiconCancellable: AnyCancellable?

    private var lastReplacement: (path: String, success: Bool)?
    /// Rewrite panel state for the debug JSON (nil when no panel is up).
    private var rewriteDebug:
        (state: String, original: String, result: String, error: String)?
    private var debugObserver: NSObjectProtocol?

    /// The finding an open suggestion card is bound to — a check only
    /// dismisses the card when this finding is actually gone.
    private var cardContext: (key: UInt64, ruleId: String, start: UInt32, end: UInt32)?

    /// An explicit "选中检查" run on the selection (or caret paragraph):
    /// its scoped findings get underlines and the suggestion card even when
    /// the app/group is disabled or autoUnderline is off. Esc, an outside
    /// click, focus loss or an app switch ends it.
    private struct SelectionSession {
        /// CFHash tag of the element (matching `states` keys when tracked).
        let key: UInt64
        /// Holds the element itself — Word page keys change on scroll, so
        /// the session never re-derives it.
        let target: TextTarget
        /// The text the last session check ran on.
        var text: String
        /// Element-local UTF-16 scope; `end` tracks replacements.
        var scope: (start: Int, end: Int)
        /// Findings inside the scope, ordered (from `CheckService.checkNow`).
        var findings: [Finding] = []
        /// `findings` positioned for drawing/anchoring (may skip off-screen).
        var positioned: [PositionedFinding] = []
        /// Index into `findings` shown on the card.
        var index = 0
        /// Bumped per check — stale completions are dropped.
        var generation = 0
        let bundleId: String
        /// The empty card is (or was) up — a second empty result flashes.
        var shownEmpty = false
        /// Rect the card is anchored at (scope first glyph / finding rect).
        var anchor = CGRect.zero
    }

    private var selectionSession: SelectionSession?

    private func tag(for element: AXElement) -> UInt64 {
        UInt64(CFHash(element.raw))
    }

    // MARK: - lifecycle

    func start() {
        tracker.delegate = self
        tracker.shouldServe = { [weak self] bundleId in
            self?.settings.isAppEnabled(bundleId) ?? true
        }
        checkService.onResult = { [weak self] result in
            self?.checkFinished(result)
        }
        clickMonitor.onUnderlineClick = { [weak self] item, rect in
            self?.underlineClicked(item, at: rect)
        }
        clickMonitor.onOtherClick = { [weak self] in
            self?.card.dismiss()
        }
        rewritePanel.model.onAccept = { [weak self] in self?.rewriteAccept() }
        rewritePanel.model.onRetry = { [weak self] in self?.runRewriteRequest() }
        rewritePanel.model.onCancel = { [weak self] in
            self?.rewritePanel.dismiss()
        }
        rewritePanel.model.onOpenSettings = { [weak self] in
            self?.showSettingsWindow()
        }
        rewritePanel.model.onAddLexiconPairs = { [weak self] pairs in
            self?.addLexiconPairs(pairs)
        }
        rewritePanel.onDismissed = { [weak self] in
            self?.rewriteClosed()
        }
        hotkey.onPress = { [weak self] in self?.selectionCheckPressed() }
        applyHotkeySetting()
        card.lang = settings.uiLanguage
        rewritePanel.model.lang = settings.uiLanguage
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the write lands — apply next tick
            DispatchQueue.main.async { [weak self] in self?.settingsChanged() }
        }
        // Lexicon edits (settings UI, card menus, or external file edits via
        // the watcher) must re-run checks — entries feed the personal pass.
        lexiconCancellable = settings.lexicon.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for key in self.states.keys {
                    self.scheduleCheck(key, now: true)
                }
            }
        }

        // Remote debug commands only when the debug dump is enabled —
        // same UserDefaults flag controls both.
        if UserDefaults.standard.string(forKey: "deai.debugStatePath") != nil {
            debugObserver = DistributedNotificationCenter.default().addObserver(
                forName: DebugCommand.notificationName,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let cmd = DebugCommand(userInfo: note.userInfo) else { return }
                self?.handleDebugCommand(cmd)
            }
        }

        if AXIsProcessTrusted() {
            startTracking()
        } else {
            showPermissionOnboarding()
        }
    }

    func stop() {
        tracker.stop()
        clickMonitor.stop()
        overlay.hideAll()
        card.dismiss()
        rewritePanel.dismiss()
        hotkey.unregister()
        settingsWindow?.close()
        permissionTimer?.invalidate()
        permissionWindow?.close()
        if let o = debugObserver {
            DistributedNotificationCenter.default().removeObserver(o)
            debugObserver = nil
        }
    }

    private func startTracking() {
        tracker.start()
        clickMonitor.start()
    }

    // MARK: - permission onboarding

    private func showPermissionOnboarding() {
        // Prompt the OS once; the dedicated window explains why.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t(.windowPermission, settings.uiLanguage)
        window.contentView = NSHostingView(
            rootView: LanguageScoped { PermissionView() }
                .environmentObject(settings)
        )
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        permissionWindow = window

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, AXIsProcessTrusted() else { return }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.permissionWindow?.close()
                self.permissionWindow = nil
                self.startTracking()
            }
        }
    }

    // MARK: - FocusTrackerDelegate

    func focusTargetsChanged(_ newTargets: [TextTarget]) {
        frontmostBundleId = tracker.currentApp?.bundleIdentifier
        // switching to another app closes the rewrite panel
        if let ctx = rewriteContext,
           ctx.bundleId != frontmostBundleId {
            rewritePanel.dismiss()
        }
        // …and ends a selection-check session bound to a different app
        if let s = selectionSession,
           s.bundleId != frontmostBundleId {
            endSelectionSession()
        }
        let keys = Set(newTargets.map { tag(for: $0.element) })
        for key in states.keys where !keys.contains(key) {
            states.removeValue(forKey: key)
            lastCarets.removeValue(forKey: key)
            checkService.invalidate(tag: key)
        }
        guard !newTargets.isEmpty else {
            overlay.hideAll()
            clickMonitor.setHitRects([])
            writeDebugState()
            return
        }
        for t in newTargets {
            let key = tag(for: t.element)
            if var existing = states[key] {
                // re-resolve (e.g. after a scroll): refresh the element
                // wrapper + baseOffset — text/findings carry over and the
                // check cache dedupes when nothing changed
                existing.target = t
                states[key] = existing
                scheduleCheck(key)
            } else {
                states[key] = TargetState(target: t)
                scheduleCheck(key, now: true)
            }
        }
        // A re-resolve (e.g. the post-scroll Word re-resolve) can arrive when
        // no text changed — the check cache then delivers no result, so this
        // is also the only re-measure that corrects stale underline rects.
        repositionAll()
    }

    func focusTextMayHaveChanged(_ target: TextTarget) {
        let key = tag(for: target.element)
        guard states[key] != nil else {
            states[key] = TargetState(target: target)
            scheduleCheck(key)
            return
        }
        // Read the live value on main: caret/selection moves (which fire the
        // same AX notifications, e.g. after clicking an underline) must NOT
        // trigger a re-check — that would dismiss the card we just opened.
        // A transient read failure defers to the background check instead of
        // clearing underlines.
        guard let current = target.element.stringValue else {
            scheduleCheck(key)
            return
        }
        // Unchanged text (arrows/PageUp scroll the viewport without touching
        // AXValue): the underline rects may still have moved — re-measure.
        if handleTextRead(key: key, current: current) {
            repositionAll()
        }
    }

    func focusSelectionMayHaveChanged(_ target: TextTarget) {
        let key = tag(for: target.element)
        guard states[key] != nil else {
            states[key] = TargetState(target: target)
            scheduleCheck(key)
            return
        }
        guard let current = target.element.stringValue else {
            scheduleCheck(key)
            return
        }
        // handleTextRead returns true when the text is UNCHANGED; a change
        // clears findings and schedules a check (and no card logic runs).
        let unchanged = handleTextRead(key: key, current: current)
        // Caret trigger: unchanged text + collapsed selection inside a
        // positioned finding + a jump > 1 UTF-16 unit = a click (real or
        // synthetic), not arrow-key stepping. Synthetic clicks never reach
        // the global mouse monitor — this is the card's second entry path.
        // AXSelectedTextRange is in shared-document offsets → subtract
        // baseOffset for element-local coordinates (BUG-06).
        let sel = target.element.selectedTextRange
        let prev = lastCarets[key]
        if let sel, sel.length == 0 {
            lastCarets[key] = sel.location - target.baseOffset
        }
        guard let hit = CaretCardTrigger.cardFinding(
            textUnchanged: unchanged,
            selectedRange: sel,
            baseOffset: target.baseOffset,
            previousCaret: prev,
            positioned: states[key]?.positioned ?? []
        ), let rect = hit.rects.first else { return }
        showCard(for: hit, at: rect)
    }

    /// Shared by text/selection notifications. Returns true when the text is
    /// unchanged (caller may then apply the caret trigger); false when the
    /// text changed (findings cleared, check scheduled).
    @discardableResult
    private func handleTextRead(key: UInt64, current: String) -> Bool {
        guard var state = states[key] else { return false }
        if current == state.text { return true }
        // The text really changed — drop stale findings now (Grammarly-style:
        // underlines vanish while typing rather than lingering misplaced).
        state.text = current
        state.findings = []
        state.positioned = []
        states[key] = state
        render()
        scheduleCheck(key)
        return false
    }

    func focusGeometryDirty() {
        repositionAll()
    }

    private var scrollRemeasureItem: DispatchWorkItem?
    private var scrollConfirmItem: DispatchWorkItem?
    /// During a scroll burst every render path must hide instead of draw —
    /// late AX notifications / check completions otherwise re-draw stale
    /// underlines between scroll events (BUG: overlay visible mid-scroll).
    private var scrollSuppressedUntil = CFAbsoluteTime(0)

    /// Suppression predicate for the scroll window (pure — unit-tested).
    static func scrollSuppressed(
        now: CFAbsoluteTime, until: CFAbsoluteTime
    ) -> Bool {
        now < until
    }

    /// Scroll: bounds read at event time are pre-scroll (Word and
    /// momentum scrolling redraw after the event). Hide underlines like
    /// the typing path does, then re-measure 120 ms after the last event
    /// and once more at 400 ms for late redraws.
    func focusScrolled() {
        scrollSuppressedUntil = CFAbsoluteTimeGetCurrent() + 0.12
        scrollRemeasureItem?.cancel()
        scrollConfirmItem?.cancel()
        overlay.hideAll()
        clickMonitor.setHitRects([])
        let remeasure = DispatchWorkItem { [weak self] in
            // the trailing remeasure clears suppression and draws
            self?.scrollSuppressedUntil = 0
            self?.repositionAll()
        }
        scrollRemeasureItem = remeasure
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: remeasure)
        let confirm = DispatchWorkItem { [weak self] in
            self?.repositionAll()
        }
        scrollConfirmItem = confirm
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: confirm)
    }

    /// Safety tick: element/window frames don't move on scroll, so instead
    /// re-measure one drawn finding per target and re-render when it
    /// drifted — catches any stale-rect path without a full re-check.
    func focusSafetyTick() {
        let winFrame = focusedWindowFrameAX()
        for (_, state) in states {
            guard let sample = state.positioned.first, !sample.rects.isEmpty
            else { continue }
            let fresh = TextGeometry.position(
                findings: [sample.finding],
                element: state.target.element,
                primaryMaxY: primaryMaxY,
                baseOffset: state.target.baseOffset,
                viewportAX: state.target.element.viewportFrame(
                    windowFrame: winFrame
                ),
                maxFindings: 1
            ).first?.rects ?? []
            if Self.rectsMoved(sample.rects, fresh) {
                repositionAll()
                return
            }
        }
    }

    /// True when two rect lists differ by more than `tolerance` in any
    /// component — safety-tick drift predicate.
    static func rectsMoved(
        _ a: [CGRect], _ b: [CGRect], tolerance: CGFloat = 1
    ) -> Bool {
        guard a.count == b.count else { return true }
        for (r1, r2) in zip(a, b) {
            if abs(r1.minX - r2.minX) > tolerance
                || abs(r1.minY - r2.minY) > tolerance
                || abs(r1.width - r2.width) > tolerance
                || abs(r1.height - r2.height) > tolerance {
                return true
            }
        }
        return false
    }

    func focusLost() {
        for key in states.keys { checkService.invalidate(tag: key) }
        states = [:]
        lastCarets = [:]
        // Keep tracking the frontmost app even when it is not served
        // (disabled app/group): the menu must still offer "在 X 中启用"
        // (BUG-02 — previously nil hid the current-app row entirely).
        frontmostBundleId = tracker.currentApp?.bundleIdentifier
        cardContext = nil
        selectionSession = nil
        overlay.hideAll()
        card.dismiss()
        rewritePanel.dismiss()
        clickMonitor.setHitRects([])
        writeDebugState()
    }

    func focusWindowMiniaturized(_ miniaturized: Bool) {
        if miniaturized {
            overlay.hideAll()
            card.dismiss()
        } else {
            repositionAll()
        }
    }

    // MARK: - checking pipeline

    private func scheduleCheck(_ key: UInt64, now: Bool = false) {
        guard let state = states[key] else { return }
        let element = state.target.element
        let bundleId = state.target.appBundleId
        let snapshot = settings
        let read: () -> String? = { element.stringValue }
        if now {
            checkService.scheduleNow(tag: key, readText: read,
                                     settings: snapshot, bundleId: bundleId)
        } else {
            checkService.schedule(tag: key, readText: read,
                                  settings: snapshot, bundleId: bundleId)
        }
    }

    private func checkFinished(_ result: CheckService.Result) {
        guard var state = states[result.tag] else { return }
        state.text = result.text
        state.findings = result.findings
        state.readMs = result.readMs
        state.checkMs = result.checkMs
        state.nonGrammarMs = result.nonGrammarMs
        state.grammarMs = result.grammarMs
        state.filterMs = result.filterMs
        state.grammarHits = result.grammarHits
        state.grammarMisses = result.grammarMisses
        states[result.tag] = state
        // Only dismiss the card when the finding it is bound to is actually
        // gone — a caret move or unrelated result must not close it. During
        // a selection session the card lifecycle is session-managed: the
        // pipeline result here would otherwise tear down the session card
        // right after an apply (the applied finding IS gone).
        if let ctx = cardContext, ctx.key == result.tag,
           selectionSession == nil {
            let stillThere = state.findings.contains {
                $0.ruleId == ctx.ruleId && $0.start == ctx.start && $0.end == ctx.end
            }
            if !stillThere && !card.isPresentingApplication {
                card.dismiss()
            }
        }
        repositionAll()
    }

    // MARK: - geometry + render

    private var lastGeometryMs: Double = 0
    private var lastRenderMs: Double = 0

    private var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// Focused window frame in AX coordinates (nil when unreadable) —
    /// needed to compute each target's scroll-viewport clip rect (BUG-08).
    private func focusedWindowFrameAX() -> CGRect? {
        guard let pid = tracker.currentApp?.processIdentifier else { return nil }
        let appEl = AXElement.application(pid: pid)
        let win: AXUIElement? = appEl.attribute(kAXFocusedWindowAttribute)
        return win.flatMap { AXElement($0).frame }
            .flatMap { $0.isNull ? nil : $0 }
    }

    private func repositionAll() {
        // suppressed during a scroll burst — nothing may re-draw stale
        // underlines until the trailing re-measure clears the window
        if Self.scrollSuppressed(
            now: CFAbsoluteTimeGetCurrent(), until: scrollSuppressedUntil
        ) {
            overlay.hideAll()
            clickMonitor.setHitRects([])
            return
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        let winFrame = focusedWindowFrameAX()
        for key in states.keys {
            guard var state = states[key] else { continue }
            // If the element's own live text length no longer matches the
            // text we checked, the offsets are stale — draw nothing for this
            // target rather than misplaced underlines. `ownTextLength` uses
            // the shared-range length on sliced elements (Word pages) where
            // AXNumberOfCharacters reports the whole document.
            let liveLen = state.target.element.ownTextLength
            if let liveLen, liveLen != state.text.utf16.count {
                state.positioned = []
                states[key] = state
                continue
            }
            // Word pages report glyph bounds for the whole page — clip to
            // the scroll viewport so underlines never paint over the
            // ribbon/status bar (BUG-08). Recomputed each geometry pass.
            let viewportAX = state.target.element.viewportFrame(
                windowFrame: winFrame
            )
            state.positioned = TextGeometry.position(
                findings: state.findings,
                element: state.target.element,
                primaryMaxY: primaryMaxY,
                baseOffset: state.target.baseOffset,
                viewportAX: viewportAX
            )
            states[key] = state
        }
        // selection-session underlines re-measure on the same path
        repositionSession()
        lastGeometryMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        render()
    }

    private func render() {
        // same suppression as repositionAll for callers that draw directly
        if Self.scrollSuppressed(
            now: CFAbsoluteTimeGetCurrent(), until: scrollSuppressedUntil
        ) {
            overlay.hideAll()
            clickMonitor.setHitRects([])
            return
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        overlay.appearance = settings.underline
        // A selection session forces its scoped underlines even when
        // autoUnderline is off; dedupe against the tracked ones.
        let sessionItems = selectionSession?.positioned ?? []
        guard settings.autoUnderline else {
            if sessionItems.isEmpty {
                overlay.hideAll()
                clickMonitor.setHitRects([])
            } else {
                let hits = overlay.render(sessionItems)
                clickMonitor.setHitRects(hits)
            }
            writeDebugState()
            return
        }
        var all = states.values.flatMap(\.positioned)
        for item in sessionItems
        where !all.contains(where: {
            $0.finding.ruleId == item.finding.ruleId
                && $0.finding.start == item.finding.start
                && $0.finding.end == item.finding.end
        }) {
            all.append(item)
        }
        let hits = overlay.render(all)
        clickMonitor.setHitRects(hits)
        lastRenderMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        writeDebugState()
    }

    // MARK: - suggestion card + replacement

    private func state(for item: PositionedFinding) -> (key: UInt64, state: TargetState)? {
        for (key, state) in states
        where state.findings.contains(where: {
            $0.ruleId == item.finding.ruleId && $0.start == item.finding.start
                && $0.end == item.finding.end
        }) {
            return (key, state)
        }
        return nil
    }

    /// Underline click: inside a session, route to the session card (the
    /// session's findings may belong to an element the normal pipeline has
    /// no state for); otherwise the normal card path.
    private func underlineClicked(_ item: PositionedFinding, at rect: CGRect) {
        if var s = selectionSession,
           let idx = s.findings.firstIndex(where: {
               $0.ruleId == item.finding.ruleId
                   && $0.start == item.finding.start
                   && $0.end == item.finding.end
           }) {
            s.index = idx
            selectionSession = s
            showSessionCard(anchor: rect)
            return
        }
        showCard(for: item, at: rect)
    }

    private func showCard(for item: PositionedFinding, at rect: CGRect) {
        // dedupe: mouse-monitor click AND caret trigger can both fire for one
        // click — don't reopen the same card
        if let ctx = cardContext,
           ctx.ruleId == item.finding.ruleId,
           ctx.start == item.finding.start,
           ctx.end == item.finding.end {
            return
        }
        guard let (key, state) = state(for: item) else { return }
        TextReplacer.dbgLog("showCard key=\(key) \(item.finding.ruleId) [\(item.finding.start),\(item.finding.end))")
        let finding = item.finding
        let utf16 = Array(state.text.utf16)
        let s = Int(finding.start)
        let e = min(Int(finding.end), utf16.count)
        let matched = e > s ? String(decoding: utf16[s..<e], as: UTF16.self) : ""

        cardContext = (key: key, ruleId: finding.ruleId,
                       start: finding.start, end: finding.end)
        card.show(
            finding: finding,
            matchedText: matched,
            near: rect,
            onApply: { [weak self] replacement, completion in
                self?.applyReplacement(
                    key: key, finding: finding,
                    matched: matched, replacement: replacement,
                    completion: completion
                )
            },
            onRewrite: { [weak self] in
                self?.startRewriteForFinding(
                    key: key, finding: finding, anchor: rect
                )
            },
            onIgnore: { [weak self] in
                self?.ignoreFinding(key: key, finding: finding, matched: matched)
            },
            onDisableRule: { [weak self] in
                self?.disableRule(key: key, finding: finding)
            },
            onDismiss: { [weak self] in
                self?.cardContext = nil
                self?.writeDebugState()
            },
            onAddKeep: { [weak self] in
                self?.addKeepEntry(matched, key: key)
            },
            onRememberFix: { [weak self] in
                guard let suggestion = finding.suggestions
                    .first(where: { !$0.isEmpty }) else { return }
                self?.addReplaceEntry(
                    matched, replacement: suggestion, key: key
                )
            },
            onEditLexicon: { [weak self] in
                self?.showSettingsWindow(tab: .personal)
            }
        )
        // BUG-10: the debug JSON must reflect the open card immediately,
        // whichever path opened it (mouse, caret, hook).
        writeDebugState()
    }

    /// Card … menu → 加入保留词: a keep entry suppresses overlapping
    /// findings of other categories on re-check.
    private func addKeepEntry(_ term: String, key: UInt64) {
        guard !term.isEmpty else { return }
        settings.lexicon.addEntry(
            kind: .keep, term: term, replacement: nil, match: .exact
        )
        scheduleCheck(key, now: true)
    }

    /// Card … menu → 记住此改法 / rewrite panel 记住改法.
    private func addReplaceEntry(
        _ term: String, replacement: String, key: UInt64? = nil
    ) {
        guard !term.isEmpty, !replacement.isEmpty else { return }
        settings.lexicon.addEntry(
            kind: .replace, term: term,
            replacement: replacement, match: .exact
        )
        if let key { scheduleCheck(key, now: true) }
    }

    /// Rewrite panel 记住改法 → 加入词库: checked pairs become replace
    /// entries (deletions become avoid entries — see Pair.lexiconCandidate);
    /// then re-check every served target (the fix may appear anywhere, not
    /// just in the panel's own target).
    private func addLexiconPairs(_ pairs: [RewriteDiff.Pair]) {
        for pair in pairs {
            guard let c = pair.lexiconCandidate else { continue }
            settings.lexicon.addEntry(
                kind: c.kind, term: c.term,
                replacement: c.replacement, match: .exact
            )
        }
        for key in states.keys { scheduleCheck(key, now: true) }
        rewritePanel.model.rememberSaved = true
    }

    /// Same path as the card's 忽略 button (also used by debug commands).
    private func ignoreFinding(key: UInt64, finding: Finding, matched: String) {
        settings.sessionIgnored.insert(
            AppSettings.IgnoreKey(ruleId: finding.ruleId, text: matched)
        )
        scheduleCheck(key, now: true)
    }

    /// Same path as the card's 停用此规则 button.
    private func disableRule(key: UInt64, finding: Finding) {
        settings.disabledRuleIds.insert(finding.ruleId)
        scheduleCheck(key, now: true)
    }

    private func applyReplacement(
        key: UInt64, finding: Finding, matched: String, replacement: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let state = states[key] else { completion?(false); return }
        TextReplacer.dbgLog("applyReplacement key=\(key) \(finding.ruleId) [\(finding.start),\(finding.end)) repl=\(replacement) matched=\(matched)")
        TextReplacer.apply(
            element: state.target.element,
            finding: finding,
            replacement: replacement,
            matched: matched,
            baseOffset: state.target.baseOffset,
            log: log
        ) { [weak self] result in
            // completion arrives after the write is verified (pasteboard and
            // delete-key paths poll the element's text; BUG-11)
            TextReplacer.dbgLog("applyReplacement completion path=\(result.path) success=\(result.success)")
            completion?(result.success)
            self?.lastReplacement = (result.path.rawValue, result.success)
            self?.writeDebugState()
        }
        scheduleCheck(key, now: true)
    }

    // MARK: - AI rewrite

    /// Registration failure shown under the shortcut recorder (nil = ok).
    @Published private(set) var hotkeyError: String?

    private func applyHotkeySetting() {
        switch hotkey.set(settings.rewriteHotkey.spec) {
        case noErr:
            hotkeyError = nil
        case OSStatus(eventHotKeyExistsErr):
            hotkeyError = L10n.t(.hotkeyTaken, settings.uiLanguage)
        case let status:
            hotkeyError = L10n.f(.hotkeyFailed, settings.uiLanguage, Int(status))
        }
    }

    /// The shortcut recorder unregisters the global hotkey while capturing
    /// (so pressing the current combo can't fire a rewrite) and re-applies
    /// the setting when done.
    func setHotkeyPaused(_ paused: Bool) {
        if paused { hotkey.unregister() } else { applyHotkeySetting() }
    }

    /// Card button path: rewrite the paragraph containing the finding.
    private func startRewriteForFinding(
        key: UInt64, finding: Finding, anchor: CGRect
    ) {
        guard let state = states[key] else { return }
        card.dismiss()
        // collapsed selection at the finding start → enclosing paragraph
        let caret = CFRange(
            location: state.target.baseOffset + Int(finding.start),
            length: 0
        )
        guard let scope = RewriteScope.compute(
            text: state.text,
            selection: caret,
            baseOffset: state.target.baseOffset
        ) else {
            NSSound.beep()
            return
        }
        beginRewrite(
            element: state.target.element,
            baseOffset: state.target.baseOffset,
            text: state.text, scope: scope,
            findings: state.findings,
            anchor: anchor
        )
    }

    /// Global hotkey path ("选中检查"): run an explicit check on the
    /// selection — or the caret's paragraph when collapsed — and step
    /// through the findings with the suggestion card. Unlike the ambient
    /// underline pipeline, explicit invocation ignores the app/group
    /// *enabled* flag and autoUnderline; category toggles, group check
    /// chips, disabledRuleIds and sessionIgnored still apply (they live in
    /// FindingFilter). Sensitive apps are never served — not even on demand.
    private func selectionCheckPressed() {
        if let bundleId = tracker.currentApp?.bundleIdentifier,
           AppGroup.group(for: bundleId) == .sensitive {
            NSSound.beep()
            return
        }
        // Prefer an already-tracked element containing the selection.
        for (_, state) in states {
            guard let scope = selectionScope(
                target: state.target,
                fallbackText: state.text
            ) else { continue }
            startSelectionSession(target: state.target, scope: scope)
            return
        }
        // No served state (app/group disabled, or nothing tracked yet):
        // resolve the frontmost app's focused text target on demand.
        resolveSelectionTargets { [weak self] targets in
            guard let self else { return }
            for t in targets {
                if let scope = self.selectionScope(target: t, fallbackText: nil) {
                    self.startSelectionSession(target: t, scope: scope)
                    return
                }
            }
            NSSound.beep()
        }
    }

    /// Compute the hotkey scope for a target from its live selection;
    /// `fallbackText` is the tracked text, live-read when possible.
    /// Returns nil when the element has no readable selection inside its
    /// slice or the scope is empty/whitespace.
    private func selectionScope(
        target: TextTarget, fallbackText: String?
    ) -> (start: Int, end: Int)? {
        guard let sel = target.element.selectedTextRange else { return nil }
        let base = target.baseOffset
        let text = target.element.stringValue ?? fallbackText ?? ""
        let len = text.utf16.count
        // the selection must live inside this element's shared-text slice
        guard sel.location >= base, sel.location <= base + len else {
            return nil
        }
        return RewriteScope.compute(text: text, selection: sel, baseOffset: base)
    }

    /// On-demand resolution for apps the tracker is not serving (disabled
    /// app/group): same TextTargetResolver machinery, frontmost app only.
    /// `completion` arrives on the main queue (resolveAsync is @MainActor).
    private func resolveSelectionTargets(
        completion: @escaping ([TextTarget]) -> Void
    ) {
        guard let app = tracker.currentApp,
              let bundleId = app.bundleIdentifier else {
            completion([])
            return
        }
        let appEl = AXElement.application(pid: app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl.raw, 0.25)
        TextTargetResolver().resolveAsync(
            appElement: appEl, bundleId: bundleId, completion: completion
        )
    }

    // MARK: - selection check session

    private func startSelectionSession(
        target: TextTarget, scope: (start: Int, end: Int)
    ) {
        guard let text = target.element.stringValue else {
            NSSound.beep()
            return
        }
        selectionSession = SelectionSession(
            key: tag(for: target.element),
            target: target,
            text: text,
            scope: scope,
            bundleId: target.appBundleId
        )
        TextReplacer.dbgLog(
            "selectionCheck start scope=[\(scope.start),\(scope.end)) key=\(selectionSession?.key ?? 0)"
        )
        runSelectionCheck()
    }

    /// Run the one-shot check on the session element's live text. Bumps the
    /// session generation so out-of-order completions are dropped.
    private func runSelectionCheck() {
        guard var s = selectionSession else { return }
        s.generation += 1
        // fresh read on every (re)check — the text may have been replaced
        if let live = s.target.element.stringValue {
            s.text = live
        }
        selectionSession = s
        let gen = s.generation
        checkService.checkNow(
            text: s.text, settings: settings, bundleId: s.bundleId
        ) { [weak self] findings in
            self?.selectionCheckFinished(gen: gen, findings: findings)
        }
    }

    private func selectionCheckFinished(gen: Int, findings: [Finding]) {
        guard var s = selectionSession, s.generation == gen else { return }
        s.findings = SelectionSessionLogic.scoped(
            findings, scopeStart: s.scope.start, scopeEnd: s.scope.end
        )
        selectionSession = s
        repositionSession()
        render()
        if s.findings.isEmpty {
            if card.current != nil {
                // the last scoped finding was just resolved — brief success
                // state, then the view's auto-dismiss ends the session
                card.flashSuccess()
                return
            }
            let flash = s.shownEmpty
            s.shownEmpty = true
            selectionSession = s
            showEmptySessionCard(flash: flash)
            return
        }
        guard let next = SelectionSessionLogic.nextIndex(
            current: s.index, remaining: s.findings.count
        ) else { return }
        s.index = next
        s.shownEmpty = false
        selectionSession = s
        showSessionCard()
    }

    /// Rect of a session finding (positioned), else the scope's first
    /// glyph, else near the mouse — the card anchor.
    private func sessionAnchor(
        _ s: SelectionSession, for finding: Finding? = nil
    ) -> CGRect {
        if let finding,
           let rect = s.positioned.first(where: {
               $0.finding.start == finding.start
                   && $0.finding.end == finding.end
                   && $0.finding.ruleId == finding.ruleId
           })?.rects.first {
            return rect
        }
        let firstGlyph = CFRange(
            location: s.target.baseOffset + s.scope.start,
            length: min(1, s.scope.end - s.scope.start)
        )
        if let axRect = s.target.element.boundsForRange(firstGlyph) {
            return TextGeometry.axToCocoa(axRect, primaryMaxY: primaryMaxY)
        }
        return CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 1))
    }

    /// (Re)position the session's scoped findings — called by the render
    /// paths so forced underlines track geometry like normal ones.
    private func repositionSession() {
        guard var s = selectionSession else { return }
        let winFrame = focusedWindowFrameAX()
        s.positioned = TextGeometry.position(
            findings: s.findings,
            element: s.target.element,
            primaryMaxY: primaryMaxY,
            baseOffset: s.target.baseOffset,
            viewportAX: s.target.element.viewportFrame(windowFrame: winFrame)
        )
        selectionSession = s
    }

    /// Show the session card for `session.index`. The card stays open across
    /// 忽略/停用此规则 — the re-check advances it to the next finding.
    private func showSessionCard(anchor rect: CGRect? = nil) {
        guard var s = selectionSession,
              s.findings.indices.contains(s.index) else { return }
        let finding = s.findings[s.index]
        let utf16 = Array(s.text.utf16)
        let lo = Int(finding.start)
        let hi = min(Int(finding.end), utf16.count)
        let matched = hi > lo
            ? String(decoding: utf16[lo..<hi], as: UTF16.self) : ""
        let anchor = rect ?? sessionAnchor(s, for: finding)
        s.anchor = anchor
        selectionSession = s
        // captured snapshot for the wand — the panel's onRewrite wrapper
        // dismisses the card first, which ends the session and would leave
        // nothing to rewrite
        let scope = s.scope
        let target = s.target
        let text = s.text
        let sessionFindings = s.findings
        cardContext = (key: s.key, ruleId: finding.ruleId,
                       start: finding.start, end: finding.end)
        TextReplacer.dbgLog(
            "selectionCheck card \(s.index + 1)/\(s.findings.count) \(finding.ruleId)"
        )
        card.show(
            finding: finding,
            matchedText: matched,
            near: anchor,
            sessionStep: (index: s.index, count: s.findings.count),
            onStep: { [weak self] delta in self?.stepSession(delta) },
            keepOpenOnAction: true,
            onApply: { [weak self] replacement, completion in
                self?.applySessionReplacement(
                    finding: finding, matched: matched,
                    replacement: replacement, completion: completion
                )
            },
            onRewrite: { [weak self] in
                self?.endSelectionSession()
                self?.beginRewrite(
                    element: target.element,
                    baseOffset: target.baseOffset,
                    text: text, scope: scope,
                    findings: sessionFindings,
                    anchor: anchor
                )
            },
            onIgnore: { [weak self] in
                self?.ignoreSessionFinding(finding, matched: matched)
            },
            onDisableRule: { [weak self] in
                self?.disableSessionRule(finding)
            },
            onDismiss: { [weak self] in
                self?.cardContext = nil
                self?.endSelectionSession()
            },
            onAddKeep: { [weak self] in
                guard !matched.isEmpty else { return }
                self?.settings.lexicon.addEntry(
                    kind: .keep, term: matched,
                    replacement: nil, match: .exact
                )
                // keepOpenOnAction keeps the card up; the session re-check
                // refreshes its findings (keep suppresses overlaps)
                self?.runSelectionCheck()
            },
            onRememberFix: { [weak self] in
                guard let suggestion = finding.suggestions
                    .first(where: { !$0.isEmpty }), !matched.isEmpty
                else { return }
                self?.settings.lexicon.addEntry(
                    kind: .replace, term: matched,
                    replacement: suggestion, match: .exact
                )
                self?.runSelectionCheck()
            },
            onEditLexicon: { [weak self] in
                self?.endSelectionSession()
                self?.showSettingsWindow(tab: .personal)
            }
        )
        writeDebugState()
    }

    /// The empty variant: "检查完成 / 未发现问题" + sensitivity slider +
    /// 重新检测, anchored at the scope's first glyph (or the mouse).
    private func showEmptySessionCard(flash: Bool) {
        guard var s = selectionSession else { return }
        let anchor = s.anchor == .zero ? sessionAnchor(s) : s.anchor
        s.anchor = anchor
        selectionSession = s
        let scope = s.scope
        let target = s.target
        let text = s.text
        cardContext = nil
        card.showEmpty(
            near: anchor,
            sensitivity: settings.sensitivity,
            flash: flash,
            onSensitivityChange: { [weak self] value in
                self?.settings.sensitivity = value
            },
            onRecheck: { [weak self] in self?.runSelectionCheck() },
            onRewrite: { [weak self] in
                self?.endSelectionSession()
                self?.beginRewrite(
                    element: target.element,
                    baseOffset: target.baseOffset,
                    text: text, scope: scope,
                    findings: [],
                    anchor: anchor
                )
            },
            onDismiss: { [weak self] in self?.endSelectionSession() }
        )
        writeDebugState()
    }

    private func stepSession(_ delta: Int) {
        guard var s = selectionSession else { return }
        let next = s.index + delta
        guard s.findings.indices.contains(next) else { return }
        s.index = next
        selectionSession = s
        showSessionCard()
    }

    private func applySessionReplacement(
        finding: Finding, matched: String, replacement: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let s = selectionSession else { completion(false); return }
        TextReplacer.dbgLog(
            "selectionCheck apply \(finding.ruleId) repl=\(replacement)"
        )
        TextReplacer.apply(
            element: s.target.element,
            finding: finding,
            replacement: replacement,
            matched: matched,
            baseOffset: s.target.baseOffset,
            log: log
        ) { [weak self] result in
            completion(result.success)
            guard let self, var s = self.selectionSession else { return }
            if result.success {
                // the scope tracks the edit so the re-check sees the whole
                // (grown/shrunk) selection
                s.scope.end = SelectionSessionLogic.adjustedScopeEnd(
                    s.scope.end,
                    matchedLength: matched.utf16.count,
                    replacementLength: replacement.utf16.count
                )
                self.selectionSession = s
                // re-check → advance to the next remaining finding
                self.runSelectionCheck()
            }
            self.lastReplacement = (result.path.rawValue, result.success)
            // keep the ambient findings fresh when the element is tracked
            if self.states[s.key] != nil {
                self.scheduleCheck(s.key, now: true)
            }
            self.writeDebugState()
        }
    }

    /// Session 忽略 — same store, then re-check advances the card.
    private func ignoreSessionFinding(_ finding: Finding, matched: String) {
        settings.sessionIgnored.insert(
            AppSettings.IgnoreKey(ruleId: finding.ruleId, text: matched)
        )
        runSelectionCheck()
    }

    /// Session 停用此规则 — persists, then re-check advances the card.
    private func disableSessionRule(_ finding: Finding) {
        settings.disabledRuleIds.insert(finding.ruleId)
        runSelectionCheck()
    }

    /// Esc / outside click / focus loss / app switch / wand: tear down.
    private func endSelectionSession() {
        guard selectionSession != nil else { return }
        selectionSession = nil
        cardContext = nil
        render()
        writeDebugState()
    }

    /// Shared entry: validates config, captures the context, shows the
    /// panel in loading state, and kicks off the request.
    private func beginRewrite(
        element: AXElement,
        baseOffset: Int,
        text: String,
        scope: (start: Int, end: Int),
        findings: [Finding],
        anchor: CGRect
    ) {
        // Close any open panel first: show() dismisses the previous panel,
        // whose onDismissed would clear the context we set below (RW-01).
        rewritePanel.dismiss()
        guard scope.end - scope.start <= RewriteScope.maxLength else {
            showRewriteError(
                L10n.f(.errorTooLong, settings.uiLanguage, RewriteScope.maxLength),
                original: "", anchor: anchor
            )
            return
        }
        let units = Array(text.utf16)
        let original = String(
            decoding: units[scope.start..<scope.end], as: UTF16.self
        )
        guard let provider = settings.activeProvider,
              !provider.baseURL
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !provider.model.isEmpty,
              !provider.preset.requiresKey
                || !(settings.secrets.get(provider.id.uuidString) ?? "")
                    .isEmpty
        else {
            showRewriteError(
                L10n.t(.errorConfigureAI, settings.uiLanguage),
                original: original, anchor: anchor,
                showOpenSettings: true
            )
            return
        }
        let hints: [RewriteHint] = findings
            .filter {
                Int($0.start) >= scope.start && Int($0.end) <= scope.end
            }
            .prefix(20)
            .map {
                let s = Int($0.start)
                let e = min(Int($0.end), units.count)
                return RewriteHint(
                    ruleId: $0.ruleId,
                    matched: e > s
                        ? String(decoding: units[s..<e], as: UTF16.self) : "",
                    message: $0.message
                )
            }
        rewriteContext = RewriteContext(
            element: element,
            baseOffset: baseOffset,
            start: scope.start,
            end: scope.end,
            original: original,
            hints: hints,
            bundleId: tracker.currentApp?.bundleIdentifier ?? ""
        )
        rewritePanel.model.phase = .loading
        rewritePanel.model.original = original
        rewritePanel.model.result = ""
        rewritePanel.model.errorMessage = ""
        rewritePanel.model.showOpenSettings = false
        rewritePanel.model.canRetry = true
        rewritePanel.model.rememberPairs = []
        rewritePanel.model.rememberChecked = []
        rewritePanel.model.rememberExpanded = false
        rewritePanel.model.rememberSaved = false
        rewritePanel.show(near: anchor)
        rewriteDebug = (state: "loading", original: original,
                        result: "", error: "")
        writeDebugState()
        runRewriteRequest()
    }

    /// (Re)send the request for the captured context. Also wired to the
    /// panel's 重试 button.
    private func runRewriteRequest() {
        guard let ctx = rewriteContext,
              let provider = settings.activeProvider else { return }
        rewriteTask?.cancel()
        rewritePanel.model.phase = .loading
        rewritePanel.update()
        rewriteDebug = (state: "loading", original: ctx.original,
                        result: "", error: "")
        writeDebugState()
        let user = RewritePrompt.user(
            text: ctx.original, hints: ctx.hints,
            lexicon: settings.lexicon.entries
        )
        let apiKey = settings.secrets.get(provider.id.uuidString)
        // Skill selection follows the text's detected language: zh texts
        // pick from zh|any skills, en texts from en|any.
        let rewriteLang = RewriteLanguageDetect.language(of: ctx.original)
        let skillId = rewriteLang == .zh
            ? settings.rewriteSkillZh : settings.rewriteSkillEn
        let skill = settings.skills.resolved(id: skillId, for: rewriteLang)
        let systemPrompt = RewritePrompt.system(skill: skill)
        rewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.llmClient.complete(
                    config: provider,
                    apiKey: apiKey,
                    system: systemPrompt,
                    user: user
                )
                let cleaned = LLMClient.cleanOutput(raw)
                self.rewriteFinished(cleaned)
            } catch is CancellationError {
                // dismissed while in flight — panel already closed
            } catch {
                self.rewriteFailed(error.deaiMessage(self.settings.uiLanguage))
            }
        }
    }

    private func rewriteFinished(_ result: String) {
        guard let ctx = rewriteContext, rewritePanel.isShowing else { return }
        if result == ctx.original {
            rewritePanel.model.phase = .noChange
            rewriteDebug = (state: "noChange", original: ctx.original,
                            result: result, error: "")
        } else {
            rewritePanel.model.phase = .result
            rewritePanel.model.result = result
            // 记住改法: word-level changed pairs for the checkbox list
            let pairs = RewriteDiff.wordPairs(
                original: ctx.original, result: result
            )
            rewritePanel.model.rememberPairs = pairs
            rewritePanel.model.rememberChecked = Set(pairs.indices)
            rewritePanel.model.rememberExpanded = false
            rewritePanel.model.rememberSaved = false
            rewriteDebug = (state: "result", original: ctx.original,
                            result: result, error: "")
        }
        rewritePanel.update()
        writeDebugState()
    }

    private func rewriteFailed(_ message: String) {
        guard let ctx = rewriteContext, rewritePanel.isShowing else { return }
        rewritePanel.model.phase = .error
        rewritePanel.model.errorMessage = message
        rewriteDebug = (state: "error", original: ctx.original,
                        result: "", error: message)
        rewritePanel.update()
        writeDebugState()
    }

    /// Error-only panel (no request context exists yet — e.g. no provider).
    private func showRewriteError(
        _ message: String, original: String,
        anchor: CGRect, showOpenSettings: Bool = false
    ) {
        rewriteContext = nil
        rewritePanel.model.phase = .error
        rewritePanel.model.original = original
        rewritePanel.model.result = ""
        rewritePanel.model.errorMessage = message
        rewritePanel.model.showOpenSettings = showOpenSettings
        rewritePanel.model.canRetry = false
        rewritePanel.show(near: anchor)
        rewriteDebug = (state: "error", original: original,
                        result: "", error: message)
        writeDebugState()
    }

    /// 替换 button / debug hook: re-read the element, verify the scope text
    /// is untouched, then write via the normal replacer.
    private func rewriteAccept() {
        guard let ctx = rewriteContext,
              rewritePanel.model.phase == .result else { return }
        let result = rewritePanel.model.result
        guard let live = ctx.element.stringValue else {
            rewriteFailed(L10n.t(.errorReadText, settings.uiLanguage))
            return
        }
        let units = Array(live.utf16)
        guard ctx.end <= units.count,
              String(decoding: units[ctx.start..<ctx.end], as: UTF16.self)
                  == ctx.original
        else {
            rewriteFailed(L10n.t(.errorOriginalChanged, settings.uiLanguage))
            return
        }
        let normalized = RewriteScope.normalizeNewlines(
            result, likeOriginal: ctx.original
        )
        rewritePanel.dismiss()
        TextReplacer.apply(
            element: ctx.element,
            start: ctx.start, end: ctx.end,
            matched: ctx.original,
            replacement: normalized,
            baseOffset: ctx.baseOffset,
            label: "ai-rewrite",
            log: log
        ) { [weak self] r in
            self?.lastReplacement = (r.path.rawValue, r.success)
            self?.writeDebugState()
        }
        // re-check the owning target (element may be a Word page whose key
        // changed on scroll — match by identity, not key)
        if let key = states.first(where: {
            CFEqual($0.value.target.element.raw, ctx.element.raw)
        })?.key {
            scheduleCheck(key, now: true)
        }
    }

    /// Panel closed (Esc / outside click / 取消 / accept path): cancel the
    /// in-flight request and clear the debug field.
    private func rewriteClosed() {
        rewriteTask?.cancel()
        rewriteTask = nil
        rewriteContext = nil
        rewriteDebug = nil
        writeDebugState()
    }

    // MARK: - settings window

    /// A real NSWindow (the menu-bar app has no key window otherwise) —
    /// replaces the SwiftUI `Window` scene, which misbehaved behind
    /// `LSUIElement`.
    func showSettingsWindow(tab: SettingsTabID = .check) {
        if let w = settingsWindow {
            // a deep-link (e.g. card … → 编辑词条…) retargets the open window
            if tab != .check {
                w.contentView = NSHostingView(
                    rootView: SettingsView(
                        settings: settings,
                        currentBundleId: tracker.currentApp?.bundleIdentifier,
                        initialTab: tab.rawValue,
                        controller: self
                    )
                )
            }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t(.windowSettings, settings.uiLanguage)
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                currentBundleId: tracker.currentApp?.bundleIdentifier,
                initialTab: tab.rawValue,
                controller: self
            )
        )
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    // MARK: - debug commands (automated QA)

    /// All positioned findings matching `ruleId`, deterministically ordered
    /// (baseOffset, then start) so `index` is stable for QA.
    private func positionedFindings(ruleId: String)
        -> [(key: UInt64, item: PositionedFinding, matched: String)]
    {
        var out: [(UInt64, PositionedFinding, String)] = []
        for (key, state) in states {
            let utf16 = Array(state.text.utf16)
            for pf in state.positioned where pf.finding.ruleId == ruleId {
                let s = Int(pf.finding.start)
                let e = min(Int(pf.finding.end), utf16.count)
                let matched = e > s
                    ? String(decoding: utf16[s..<e], as: UTF16.self) : ""
                out.append((key, pf, matched))
            }
        }
        out.sort {
            let a = states[$0.0]?.target.baseOffset ?? 0
            let b = states[$1.0]?.target.baseOffset ?? 0
            if a != b { return a < b }
            return ($0.1.finding.start, $0.1.finding.end)
                < ($1.1.finding.start, $1.1.finding.end)
        }
        return out
    }

    /// Drive the exact code paths of the card UI buttons remotely.
    private func handleDebugCommand(_ cmd: DebugCommand) {
        switch cmd.action {
        case .dismissCard:
            card.dismiss()
            writeDebugState()
            return
        case .rewriteHotkey:
            // the hotkey is the selection check now
            selectionCheckPressed()
            writeDebugState()
            return
        case .rewriteAccept:
            rewriteAccept()
            writeDebugState()
            return
        case .rewriteCancel:
            rewritePanel.dismiss()
            writeDebugState()
            return
        case .rewriteFinding:
            break // resolved below, with the finding
        default:
            break
        }
        if cmd.action == .dumpPanels {
            // snapshot overlay panels to <debugStatePath>.panels/
            let base = UserDefaults.standard.string(forKey: "deai.debugStatePath")
                ?? NSTemporaryDirectory()
            overlay.dumpPanelImages(
                to: URL(fileURLWithPath: base + ".panels")
            )
            writeDebugState()
            return
        }
        let matches = positionedFindings(ruleId: cmd.ruleId)
        guard matches.indices.contains(cmd.index) else {
            log.notice("debug command \(cmd.action.rawValue): no finding \(cmd.index) for \(cmd.ruleId)")
            return
        }
        let (key, pf, matched) = matches[cmd.index]
        switch cmd.action {
        case .showCard:
            if let rect = pf.rects.first {
                showCard(for: pf, at: rect)
            }
        case .apply:
            let suggestions = pf.finding.suggestions
            guard suggestions.indices.contains(cmd.suggestion) else {
                log.notice("debug apply: no suggestion \(cmd.suggestion) for \(cmd.ruleId)")
                return
            }
            applyReplacement(
                key: key, finding: pf.finding,
                matched: matched, replacement: suggestions[cmd.suggestion]
            )
        case .ignore:
            ignoreFinding(key: key, finding: pf.finding, matched: matched)
        case .disableRule:
            disableRule(key: key, finding: pf.finding)
        case .rewriteFinding:
            // same path as the card's AI 改写 button
            let anchor = pf.rects.first
                ?? CGRect(
                    origin: NSEvent.mouseLocation,
                    size: CGSize(width: 1, height: 1)
                )
            startRewriteForFinding(key: key, finding: pf.finding, anchor: anchor)
        case .dismissCard, .dumpPanels,
             .rewriteHotkey, .rewriteAccept, .rewriteCancel:
            break // handled above
        }
        writeDebugState()
    }

    // MARK: - menu actions

    var currentAppBundleId: String? {
        tracker.currentApp?.bundleIdentifier
    }

    func toggleAutoUnderline() {
        settings.autoUnderline.toggle()
    }

    func toggleCurrentApp() {
        guard let bundleId = tracker.currentApp?.bundleIdentifier else { return }
        settings.setAppEnabled(bundleId, !settings.isAppEnabled(bundleId))
        tracker.refresh()
    }

    /// Snapshot of the settings that influence check output. Appearance-only
    /// edits (underline style) and AI-provider/hotkey edits don't change it,
    /// so those repaint or re-register the hotkey instead of re-running
    /// checks on every tick.
    private struct CheckFingerprint: Equatable {
        var autoUnderline: Bool
        var grammar: Bool
        var aiToneZh: Bool
        var aiToneEn: Bool
        var markdown: Bool
        var sensitivity: Int
        var disabledRuleIds: Set<String>
        var appRules: [String: AppRule]
        var groupRules: [AppGroup: GroupRule]

        init(_ s: AppSettings) {
            autoUnderline = s.autoUnderline
            grammar = s.grammar
            aiToneZh = s.aiToneZh
            aiToneEn = s.aiToneEn
            markdown = s.markdown
            sensitivity = s.sensitivity
            disabledRuleIds = s.disabledRuleIds
            appRules = s.appRules
            groupRules = s.groupRules
        }
    }

    private var lastCheckFingerprint: CheckFingerprint?

    private func settingsChanged() {
        // Provider/hotkey edits land here too — re-registering the hotkey is
        // cheap and covers the case where the fingerprint did not change.
        applyHotkeySetting()
        let fingerprint = CheckFingerprint(settings)
        if fingerprint != lastCheckFingerprint {
            lastCheckFingerprint = fingerprint
            // re-check all active targets under the new settings
            for key in states.keys { scheduleCheck(key, now: true) }
        }
        // Repaint immediately: applies underline-appearance changes to the
        // already-positioned findings, and clears overlays when
        // autoUnderline was switched off.
        render()
        // The AppKit window title isn't a SwiftUI view — retitle it on a
        // language switch so it doesn't lag one reopen behind.
        settingsWindow?.title = L10n.t(.windowSettings, settings.uiLanguage)
        permissionWindow?.title = L10n.t(.windowPermission, settings.uiLanguage)
        // …same for the open card / rewrite panel models (their hosting
        // roots were created once, so the language is pushed into the model).
        card.lang = settings.uiLanguage
        rewritePanel.model.lang = settings.uiLanguage
    }

    // MARK: - debug state dump

    private struct DebugState: Codable {
        struct Target: Codable {
            let role: String
            let description: String
            let textLength: Int
        }
        struct F: Codable {
            let ruleId: String
            let category: String
            let tier: UInt8
            let start: UInt32
            let end: UInt32
            let text: String
            let rects: [[CGFloat]]
        }
        struct Timings: Codable {
            let readMs: Double
            let checkMs: Double
            let nonGrammarMs: Double
            let grammarMs: Double
            let filterMs: Double
            let grammarCacheHits: Int
            let grammarCacheMisses: Int
            let geometryMs: Double
            let renderMs: Double
        }
        struct Replacement: Codable {
            let path: String
            let success: Bool
        }
        struct Card: Codable {
            let visible: Bool
            let ruleId: String
            let start: UInt32
            let end: UInt32
            let suggestions: [String]
        }
        struct Rewrite: Codable {
            let state: String
            let original: String
            let result: String
            let error: String
        }
        /// Selection-check session snapshot for QA: always present;
        /// `active` false when no session is running.
        struct SelectionCheck: Codable {
            let active: Bool
            let scopeStart: Int
            let scopeEnd: Int
            let count: Int
            let index: Int
            /// true while the "未发现问题" empty card is up
            let empty: Bool
        }
        let timestamp: String
        let frontmostBundleId: String
        let targetCount: Int
        let targets: [Target]
        let findings: [F]
        let timings: Timings
        let lastReplacement: Replacement?
        let card: Card?
        let rewrite: Rewrite?
        let selectionCheck: SelectionCheck
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Written after every render when `deai.debugStatePath` is set
    /// (UserDefaults; `-deai.debugStatePath /path` launch arg works too).
    func writeDebugState() {
        guard let path = UserDefaults.standard.string(forKey: "deai.debugStatePath"),
              !path.isEmpty else { return }
        var findings: [DebugState.F] = []
        for state in states.values {
            let utf16 = Array(state.text.utf16)
            for pf in state.positioned {
                let s = Int(pf.finding.start)
                let e = min(Int(pf.finding.end), utf16.count)
                let slice = e > s ? String(decoding: utf16[s..<e], as: UTF16.self) : ""
                findings.append(
                    .init(
                        ruleId: pf.finding.ruleId,
                        category: "\(pf.finding.category)",
                        tier: pf.finding.tier,
                        start: pf.finding.start,
                        end: pf.finding.end,
                        text: slice,
                        rects: pf.rects.map { [$0.origin.x, $0.origin.y, $0.width, $0.height] }
                    )
                )
            }
        }
        let dbg = DebugState(
            timestamp: Self.isoFormatter.string(from: Date()),
            frontmostBundleId: tracker.currentApp?.bundleIdentifier ?? "",
            targetCount: states.count,
            targets: states.values.map {
                .init(
                    role: $0.target.element.role ?? "",
                    description: $0.target.element.descriptionText ?? "",
                    textLength: $0.text.utf16.count
                )
            },
            findings: findings,
            timings: .init(
                readMs: states.values.map(\.readMs).max() ?? 0,
                checkMs: states.values.map(\.checkMs).max() ?? 0,
                nonGrammarMs: states.values.map(\.nonGrammarMs).max() ?? 0,
                grammarMs: states.values.map(\.grammarMs).max() ?? 0,
                filterMs: states.values.map(\.filterMs).max() ?? 0,
                grammarCacheHits: states.values.map(\.grammarHits).reduce(0, +),
                grammarCacheMisses: states.values.map(\.grammarMisses).reduce(0, +),
                geometryMs: lastGeometryMs,
                renderMs: lastRenderMs
            ),
            lastReplacement: lastReplacement.map {
                .init(path: $0.path, success: $0.success)
            },
            card: card.current.map {
                .init(
                    visible: true,
                    ruleId: $0.finding.ruleId,
                    start: $0.finding.start,
                    end: $0.finding.end,
                    suggestions: $0.finding.suggestions
                )
            },
            rewrite: rewriteDebug.map {
                .init(
                    state: $0.state,
                    original: $0.original,
                    result: $0.result,
                    error: $0.error
                )
            },
            selectionCheck: .init(
                active: selectionSession != nil,
                scopeStart: selectionSession?.scope.start ?? 0,
                scopeEnd: selectionSession?.scope.end ?? 0,
                count: selectionSession?.findings.count ?? 0,
                index: selectionSession?.index ?? 0,
                empty: selectionSession.map {
                    $0.findings.isEmpty && $0.shownEmpty
                } ?? false
            )
        )
        guard let data = try? JSONEncoder().encode(dbg) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// A remote command posted to `com.local.deai.debug.command` via
/// DistributedNotificationCenter (only honored when `deai.debugStatePath`
/// is set). Lets automated QA drive the exact paths behind the card UI.
struct DebugCommand {
    static let notificationName = NSNotification.Name("com.local.deai.debug.command")

    enum Action: String {
        case showCard
        case apply
        case ignore
        case disableRule
        case dismissCard
        /// dump overlay panel contents to PNG (live-render QA)
        case dumpPanels
        case rewriteFinding
        case rewriteHotkey
        case rewriteAccept
        case rewriteCancel
    }

    let action: Action
    let ruleId: String
    /// nth finding of `ruleId` (default 0)
    let index: Int
    /// index into `finding.suggestions` for `.apply` (default 0)
    let suggestion: Int

    init?(userInfo: [AnyHashable: Any]?) {
        guard let actionName = userInfo?["action"] as? String,
              let action = Action(rawValue: actionName) else { return nil }
        self.action = action
        ruleId = userInfo?["ruleId"] as? String ?? ""
        index = userInfo?["index"] as? Int ?? 0
        suggestion = userInfo?["suggestion"] as? Int ?? 0
    }
}

/// Pure helpers for the selection-check session (unit-tested).
enum SelectionSessionLogic {
    /// Findings fully contained in `[start, end)` — a finding that only
    /// partially overlaps the scope does not belong to the session.
    static func scoped(
        _ findings: [Finding], scopeStart: Int, scopeEnd: Int
    ) -> [Finding] {
        findings.filter {
            Int($0.start) >= scopeStart && Int($0.end) <= scopeEnd
        }
    }

    /// New scope end after a replacement inside the scope:
    /// `end += replacementLen - matchedLen` (UTF-16 units), never < start.
    static func adjustedScopeEnd(
        _ end: Int, matchedLength: Int, replacementLength: Int
    ) -> Int {
        end + replacementLength - matchedLength
    }

    /// Index into the remaining list after the current finding was removed:
    /// the same slot now holds the next finding; clamps past the end, and
    /// returns nil when nothing remains (session over).
    static func nextIndex(current: Int, remaining: Int) -> Int? {
        guard remaining > 0 else { return nil }
        return min(current, remaining - 1)
    }
}

/// Decides whether a collapsed caret event should open a suggestion card.
/// A jump of more than 1 UTF-16 unit from the previous caret means a click
/// (real or synthetic) rather than arrow-key stepping; the caret must land
/// inside a positioned finding's range (element-local coords).
enum CaretCardTrigger {
    static func finding(
        caret: Int,
        previousCaret: Int?,
        positioned: [PositionedFinding]
    ) -> PositionedFinding? {
        if let prev = previousCaret, abs(caret - prev) <= 1 { return nil }
        return positioned.first {
            caret >= Int($0.finding.start) && caret <= Int($0.finding.end)
        }
    }

    /// The whole selection-event gate, mirroring `focusSelectionMayHaveChanged`
    /// so the ordering is unit-testable (BUG-06 regression): the text must
    /// be unchanged AND the selection collapsed AND the caret must have
    /// jumped. `selectedRange` is in shared-document offsets; `baseOffset`
    /// converts to element-local.
    static func cardFinding(
        textUnchanged: Bool,
        selectedRange: CFRange?,
        baseOffset: Int,
        previousCaret: Int?,
        positioned: [PositionedFinding]
    ) -> PositionedFinding? {
        guard textUnchanged,
              let sel = selectedRange,
              sel.length == 0 else { return nil }
        return finding(
            caret: sel.location - baseOffset,
            previousCaret: previousCaret,
            positioned: positioned
        )
    }
}
