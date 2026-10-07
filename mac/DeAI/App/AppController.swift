import AppKit
import ApplicationServices
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

    private var lastReplacement: (path: String, success: Bool)?
    /// Rewrite panel state for the debug JSON (nil when no panel is up).
    private var rewriteDebug:
        (state: String, original: String, result: String, error: String)?
    private var debugObserver: NSObjectProtocol?

    /// The finding an open suggestion card is bound to — a check only
    /// dismisses the card when this finding is actually gone.
    private var cardContext: (key: UInt64, ruleId: String, start: UInt32, end: UInt32)?

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
            self?.showCard(for: item, at: rect)
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
        rewritePanel.onDismissed = { [weak self] in
            self?.rewriteClosed()
        }
        hotkey.onPress = { [weak self] in self?.rewriteHotkeyPressed() }
        applyHotkeySetting()
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the write lands — apply next tick
            DispatchQueue.main.async { [weak self] in self?.settingsChanged() }
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
        window.title = "DeAI — 辅助功能权限"
        window.contentView = NSHostingView(rootView: PermissionView())
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
        handleTextRead(key: key, current: current)
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

    func focusLost() {
        for key in states.keys { checkService.invalidate(tag: key) }
        states = [:]
        lastCarets = [:]
        frontmostBundleId = nil
        cardContext = nil
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
        // gone — a caret move or unrelated result must not close it.
        if let ctx = cardContext, ctx.key == result.tag {
            let stillThere = state.findings.contains {
                $0.ruleId == ctx.ruleId && $0.start == ctx.start && $0.end == ctx.end
            }
            if !stillThere {
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
        lastGeometryMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        render()
    }

    private func render() {
        let t0 = CFAbsoluteTimeGetCurrent()
        overlay.appearance = settings.underline
        guard settings.autoUnderline else {
            overlay.hideAll()
            clickMonitor.setHitRects([])
            writeDebugState()
            return
        }
        let all = states.values.flatMap(\.positioned)
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
            onApply: { [weak self] replacement in
                self?.applyReplacement(
                    key: key, finding: finding,
                    matched: matched, replacement: replacement
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
            }
        )
        // BUG-10: the debug JSON must reflect the open card immediately,
        // whichever path opened it (mouse, caret, hook).
        writeDebugState()
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
        key: UInt64, finding: Finding, matched: String, replacement: String
    ) {
        guard let state = states[key] else { return }
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
            self?.lastReplacement = (result.path.rawValue, result.success)
            self?.writeDebugState()
        }
        scheduleCheck(key, now: true)
    }

    // MARK: - AI rewrite

    private func applyHotkeySetting() {
        hotkey.set(settings.rewriteHotkey.spec)
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

    /// Global hotkey path: rewrite the selection, or the caret's paragraph
    /// when the selection is collapsed.
    private func rewriteHotkeyPressed() {
        for (_, state) in states {
            guard let sel = state.target.element.selectedTextRange
            else { continue }
            let base = state.target.baseOffset
            let len = state.text.utf16.count
            // the selection must live inside this element's shared-text slice
            guard sel.location >= base, sel.location <= base + len
            else { continue }
            guard let scope = RewriteScope.compute(
                text: state.text,
                selection: sel,
                baseOffset: base
            ) else {
                NSSound.beep()
                return
            }
            // anchor on the scope's first glyph rect (AX space → Cocoa);
            // fallback: near the mouse
            let anchor: CGRect
            let firstGlyph = CFRange(
                location: base + scope.start,
                length: min(1, scope.end - scope.start)
            )
            if let axRect = state.target.element.boundsForRange(firstGlyph) {
                anchor = TextGeometry.axToCocoa(
                    axRect, primaryMaxY: primaryMaxY
                )
            } else {
                anchor = CGRect(
                    origin: NSEvent.mouseLocation,
                    size: CGSize(width: 1, height: 1)
                )
            }
            beginRewrite(
                element: state.target.element,
                baseOffset: base,
                text: state.text, scope: scope,
                findings: state.findings,
                anchor: anchor
            )
            return
        }
        NSSound.beep()
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
                "选中内容过长（上限 4000 字）",
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
                "请先在设置中配置 AI 服务",
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
        let user = RewritePrompt.user(text: ctx.original, hints: ctx.hints)
        let apiKey = settings.secrets.get(provider.id.uuidString)
        rewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.llmClient.complete(
                    config: provider,
                    apiKey: apiKey,
                    system: RewritePrompt.system,
                    user: user
                )
                let cleaned = LLMClient.cleanOutput(raw)
                self.rewriteFinished(cleaned)
            } catch is CancellationError {
                // dismissed while in flight — panel already closed
            } catch {
                self.rewriteFailed(error.localizedDescription)
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
            rewriteFailed("无法读取文本")
            return
        }
        let units = Array(live.utf16)
        guard ctx.end <= units.count,
              String(decoding: units[ctx.start..<ctx.end], as: UTF16.self)
                  == ctx.original
        else {
            rewriteFailed("原文已改动，请重新改写")
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
    func showSettingsWindow() {
        if let w = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeAI 设置"
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                currentBundleId: tracker.currentApp?.bundleIdentifier
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
            rewriteHotkeyPressed()
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
        let timestamp: String
        let frontmostBundleId: String
        let targetCount: Int
        let targets: [Target]
        let findings: [F]
        let timings: Timings
        let lastReplacement: Replacement?
        let card: Card?
        let rewrite: Rewrite?
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
            }
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
