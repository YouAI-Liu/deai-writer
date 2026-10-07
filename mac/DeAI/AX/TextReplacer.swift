import AppKit
import CoreGraphics
import OSLog

/// Apply a suggestion's replacement into the target app: AXSelectedText first,
/// pasteboard+Cmd+V fallback. Pure helpers are separated for unit tests.
enum TextReplacer {
    /// At-most-one in-flight write per target app (BUG-01). A second `apply`
    /// while the first is still unverified can paste twice into the same
    /// document — Word keeps reporting a stale `AXSelectedTextRange` and
    /// stale `AXValue` for tens of ms after a write, so the freshness checks
    /// in the second call can all pass while its paste lands at the caret
    /// the first write just left behind ("goesgoes"). Keyed by pid: Word's
    /// page elements are distinct AX elements over one shared document.
    struct ApplyGate {
        private(set) var inFlight: Set<pid_t> = []
        /// Returns false when a write is already in flight for `pid`.
        mutating func begin(_ pid: pid_t) -> Bool {
            inFlight.insert(pid).inserted
        }
        mutating func end(_ pid: pid_t) {
            inFlight.remove(pid)
        }
    }

    private static var applyGate = ApplyGate()

    /// Temporary BUG-01 diagnostics: appended when `deai.debugStatePath` is set.
    static func dbgLog(_ s: String) {
        guard let base = UserDefaults.standard.string(forKey: "deai.debugStatePath")
        else { return }
        let url = URL(fileURLWithPath: base + ".apply.log")
        let line = "\(String(format: "%.3f", Date().timeIntervalSince1970)) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: false, encoding: .utf8)
        }
    }

    enum Path: String {
        case axSelectedText
        case pasteboard
        case aborted
    }

    struct Result {
        let path: Path
        let success: Bool
    }

    /// The UTF-16 substring of `text` covered by the finding must still equal
    /// `matched` — otherwise the text moved and we must not write.
    static func isFresh(text: String, start: Int, end: Int, matched: String) -> Bool {
        let utf16 = Array(text.utf16)
        guard start >= 0, end <= utf16.count, start < end else { return false }
        return String(decoding: utf16[start..<end], as: UTF16.self) == matched
    }

    /// Expected document text after applying `replacement` to `[start,end)`.
    static func expectedText(
        _ text: String, start: Int, end: Int, replacement: String
    ) -> String {
        let utf16 = Array(text.utf16)
        guard start >= 0, end <= utf16.count else { return text }
        let out = Array(utf16[0..<start]) + Array(replacement.utf16) + Array(utf16[end...])
        return String(decoding: out, as: UTF16.self)
    }

    enum AXDecision {
        /// AX write verified (exact match, or replacement found at the slot
        /// after host-side normalization).
        case success
        /// The document is provably unchanged — safe to paste.
        case fallbackToPasteboard
        /// Write outcome inconclusive — do NOT paste (would double-apply).
        case failNoPaste
    }

    /// Decide the outcome of an AX write attempt. `current`/`after` are the
    /// element's AXValue before and after the `setSelectedText` call.
    ///
    /// Rules (see review + BUG-07): expected text is computed from `current`,
    /// never the stale snapshot; `setSelectedText` on Word page elements
    /// returns success but writes nothing (`AXSelectedText` is not settable
    /// there) — an unchanged re-read is always safe to fall back to
    /// pasteboard because nothing was written. Only a *changed* but
    /// unexpected result is inconclusive.
    static func decide(
        setOK: Bool,
        current: String,
        after: String,
        start: Int,
        end: Int,
        replacement: String
    ) -> AXDecision {
        if after == current {
            // Nothing was written — regardless of what the set call
            // reported, pasting cannot double-apply.
            return .fallbackToPasteboard
        }
        guard setOK else { return .failNoPaste }
        let expected = expectedText(current, start: start, end: end, replacement: replacement)
        if after == expected { return .success }
        // Host may normalize (e.g. Word CR/LF, trailing paragraph mark) — the
        // write counts if the replacement now sits at [start, start+len).
        if !replacement.isEmpty,
           isFresh(
               text: after,
               start: start,
               end: start + replacement.utf16.count,
               matched: replacement
           ) {
            return .success
        }
        return .failNoPaste
    }

    /// Outcome of the AX write attempt. `baseline` is the element's text as
    /// read before `setSelectedText` — needed before any paste to tell
    /// "AX write landed late" from "document untouched" (BUG-01).
    struct AXAttempt {
        var decision: AXDecision
        var baseline: String
    }

    /// Try the AX path on `element`. `start`/`end` are element-local; the
    /// selection range is written in shared-document offsets (`baseOffset`).
    /// Returns nil if freshness failed (abort); otherwise the decision for
    /// the caller to act on.
    static func applyViaAX(
        element: AXElement, start: Int, end: Int,
        matched: String, replacement: String, baseOffset: Int = 0
    ) -> AXAttempt? {
        dbgLog("applyViaAX enter start=\(start) end=\(end) base=\(baseOffset) repl=\(replacement)")
        // freshness: re-read current value
        guard let current = element.stringValue else {
            return AXAttempt(decision: .failNoPaste, baseline: "")
        }
        guard isFresh(text: current, start: start, end: end, matched: matched) else {
            dbgLog("applyViaAX abort: not fresh")
            return nil
        }
        guard element.setSelectedTextRange(
            CFRange(location: baseOffset + start, length: end - start)
        ) else {
            dbgLog("applyViaAX selRange set failed")
            return AXAttempt(decision: .failNoPaste, baseline: current)
        }
        let setOK = element.setSelectedText(replacement)
        let after = element.stringValue ?? current
        dbgLog("applyViaAX setOK=\(setOK) after==current:\(after == current)")
        return AXAttempt(
            decision: decide(
                setOK: setOK, current: current, after: after,
                start: start, end: end, replacement: replacement
            ),
            baseline: current
        )
    }

    /// Whether the pasteboard/delete write actually landed: `after` is the
    /// element's text re-read after posting the key event, `current` the text
    /// before. `start`/`end`/`replacement` describe the requested change in
    /// element-local offsets.
    static func pasteVerified(
        current: String, after: String,
        start: Int, end: Int, replacement: String
    ) -> Bool {
        if after == expectedText(
            current, start: start, end: end, replacement: replacement
        ) {
            return true
        }
        if !replacement.isEmpty {
            // Host normalization is only tolerated at the slot itself plus
            // a trailing paragraph mark: the prefix and the tail after the
            // replacement must match the original exactly. A doubled write
            // ("He goes goes to…") fails the tail check instead of
            // verifying on the first "goes".
            let a = Array(after.utf16)
            let c = Array(current.utf16)
            let len = replacement.utf16.count
            guard a.count >= start + len, c.count >= end,
                  a[..<start].elementsEqual(c[..<start]),
                  isFresh(
                      text: after, start: start,
                      end: start + len, matched: replacement
                  )
            else { return false }
            var tailA = a.suffix(from: start + len)
            var tailB = c.suffix(from: end)
            while let last = tailA.last, last == 13 || last == 10 {
                tailA = tailA.dropLast()
            }
            while let last = tailB.last, last == 13 || last == 10 {
                tailB = tailB.dropLast()
            }
            return tailA.elementsEqual(tailB)
        }
        // deletion: length shrank by exactly (end - start) and everything
        // before `start` is untouched
        let u16After = Array(after.utf16)
        let u16Before = Array(current.utf16)
        guard u16After.count == u16Before.count - (end - start),
              start <= u16After.count else { return false }
        return u16After[..<start].elementsEqual(u16Before[..<start])
    }

    /// What the pre-paste settle check concluded about `text` (the element's
    /// value re-read after the AX write attempt) relative to `baseline` (the
    /// text read immediately before `setSelectedText`). Pasting is only safe
    /// while the text is still exactly the baseline — a shorter/longer
    /// `replacement` may share a prefix with `matched`, so substring checks
    /// alone cannot distinguish "untouched" from "AX write landed late".
    enum PrePasteDecision {
        case paste
        case alreadyApplied
        case abort
    }

    /// Word's page-element `setSelectedText` returns success and can even
    /// write, but the element's AXValue read-back stays stale — the settle
    /// loop then sees "baseline" forever and pastes on top of the AX write
    /// (BUG-01 r2: "goes goes" on page 3). Skip the AX write entirely and
    /// go straight to the pasteboard path, whose settle/verify works on the
    /// same stale-tolerant reads.
    static func skipsAXWrite(bundleId: String?) -> Bool {
        bundleId == "com.microsoft.Word"
    }

    static func prePasteDecision(
        baseline: String, text: String, start: Int, end: Int,
        matched: String, replacement: String
    ) -> PrePasteDecision {
        if text == baseline { return .paste }
        if text == expectedText(
            baseline, start: start, end: end, replacement: replacement
        ) || (!replacement.isEmpty && isFresh(
            text: text, start: start,
            end: start + replacement.utf16.count, matched: replacement
        )) {
            return .alreadyApplied
        }
        return .abort
    }

    /// Word-specific write path: invoke the app's own menu command
    /// (Edit ▸ Paste / Edit ▸ Cut) instead of synthesized key events —
    /// language-independent via AXMenuItemCmdChar (BUG-01 r4: a probe
    /// showed AXPress on Word's menu item writes correctly while DeAI's
    /// posted keys still doubled).
    private static func menuCommandItem(pid: pid_t, cmdChar: String) -> AXElement? {
        let app = AXElement.application(pid: pid)
        guard let barRaw: AXUIElement = app.attribute(kAXMenuBarAttribute)
        else { return nil }
        var stack = [AXElement(barRaw)]
        while let el = stack.popLast() {
            if el.role == "AXMenuItem",
               let ch: String = el.attribute("AXMenuItemCmdChar"),
               ch.uppercased() == cmdChar {
                // AXMenuItemCmdModifiers: 0 = ⌘ only
                let mods: Int = el.attribute("AXMenuItemCmdModifiers") ?? -1
                if mods == 0 { return el }
            }
            stack.append(contentsOf: el.children)
        }
        return nil
    }

    /// Focus/window context at paste time (BUG-01 diagnostics): who is
    /// frontmost, which window is key, and where Word's selection sits.
    private static func dbgContext(_ element: AXElement) {
        let front = NSWorkspace.shared.frontmostApplication
        let key = NSApp.keyWindow
        let sel = element.selectedTextRange.map {
            "{\($0.location),\($0.length)}"
        } ?? "nil"
        dbgLog(
            "ctx front=\(front?.localizedName ?? "nil")/\(front?.processIdentifier ?? -1)"
            + " active=\(NSApp.isActive)"
            + " key=\(key.map { "\(type(of: $0)) '\($0.title)'" } ?? "nil")"
            + " sel=\(sel)"
        )
    }

    /// Word's Cut menu command (and a bare delete key) do nothing on a
    /// page element selection — turn a deletion into a replacement over an
    /// extended range instead: swallow one neighbouring whole character
    /// (never a paragraph separator, never half a surrogate pair) and paste
    /// it back. Prefers the following char, then the preceding one.
    /// Returns nil when neither side offers a usable character.
    static func wordDeletionAsReplacement(
        text: String, start: Int, end: Int
    ) -> (start: Int, end: Int, replacement: String)? {
        let u = Array(text.utf16)
        guard start >= 0, end <= u.count, start < end else { return nil }
        func isSeparator(_ c: UInt16) -> Bool {
            c == 10 || c == 13 || c == 0x2029
        }
        func isHighSurrogate(_ c: UInt16) -> Bool { (0xD800...0xDBFF).contains(c) }
        func isLowSurrogate(_ c: UInt16) -> Bool { (0xDC00...0xDFFF).contains(c) }
        if end < u.count {
            let c = u[end]
            // a low surrogate here would split a pair — unusable
            if !isSeparator(c), !isLowSurrogate(c) {
                let len = isHighSurrogate(c) ? 2 : 1
                if end + len <= u.count {
                    return (start, end + len,
                            String(decoding: u[end..<end + len], as: UTF16.self))
                }
            }
        }
        if start > 0 {
            let c = u[start - 1]
            // a high surrogate here would split the pair (start-1, start)
            if !isSeparator(c), !isHighSurrogate(c) {
                let len = isLowSurrogate(c) ? 2 : 1
                if start - len >= 0 {
                    return (start - len, end,
                            String(decoding: u[(start - len)..<start], as: UTF16.self))
                }
            }
        }
        return nil
    }

    /// Pasteboard/delete fallback. The selection must be verifiably on the
    /// requested (shared-document) range first — pasting without it would
    /// insert at the caret. An empty `replacement` posts Forward Delete
    /// (BUG-11: pasting an empty string does not delete in Word) — under
    /// `useMenuCommands` (Word) it is instead rewritten as a replacement
    /// over an extended range, since Word's Cut is a no-op here. Success is
    /// reported asynchronously after
    /// re-reading the element's text (poll every 50 ms, up to 600 ms);
    /// the clipboard is restored after verification, but not before 300 ms
    /// have elapsed since the paste.
    static func applyViaPasteboard(
        element: AXElement, start: Int, end: Int,
        matched: String, replacement: String,
        baseline: String, baseOffset: Int = 0,
        useMenuCommands: Bool = false,
        completion: @escaping (Bool) -> Void
    ) {
        var start = start, end = end
        var matched = matched, replacement = replacement
        var useMenuCommands = useMenuCommands
        if useMenuCommands && replacement.isEmpty {
            // Word Cut is a no-op on page-element selections — express the
            // deletion as a replacement over an extended range instead.
            if let ext = wordDeletionAsReplacement(
                text: baseline, start: start, end: end
            ) {
                let u = Array(baseline.utf16)
                matched = String(decoding: u[ext.start..<ext.end], as: UTF16.self)
                dbgLog(
                    "Word deletion as replacement: {\(start),\(end)} → "
                    + "{\(ext.start),\(ext.end)} repl=\(ext.replacement)"
                )
                start = ext.start; end = ext.end; replacement = ext.replacement
            } else {
                dbgLog("Word deletion: no usable neighbour — key-event delete")
                useMenuCommands = false
            }
        }
        dbgLog("applyViaPasteboard enter start=\(start) end=\(end) base=\(baseOffset)")
        let wanted = CFRange(location: baseOffset + start, length: end - start)
        guard element.setSelectedTextRange(wanted),
              let got = element.selectedTextRange,
              got.location == wanted.location, got.length == wanted.length
        else {
            dbgLog("pasteboard: selection not on wanted range")
            completion(false)
            return
        }
        // BUG-01: never paste while a previous write could still be in
        // flight. Word page elements return success for setSelectedText yet
        // apply it asynchronously (or not at all), and AXValue/selection
        // read-backs stay stale meanwhile — settle first: if the write
        // landed, done; if the range changed, abort; only paste once the
        // text is still exactly the baseline seen before the AX write.
        var settleAttempts = 0
        func settle() {
            guard let before = element.stringValue else {
                completion(false)
                return
            }
            switch prePasteDecision(
                baseline: baseline, text: before, start: start, end: end,
                matched: matched, replacement: replacement
            ) {
            case .alreadyApplied:
                dbgLog("pasteboard: earlier write landed — already applied")
                completion(true)
            case .abort:
                dbgLog("pasteboard: matched range changed — abort paste")
                completion(false)
            case .paste:
                settleAttempts += 1
                if settleAttempts < 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        settle()
                    }
                } else {
                    paste(before: before)
                }
            }
        }
        func paste(before: String) {
            let t0 = CFAbsoluteTimeGetCurrent()
            dbgContext(element)

            let pb = NSPasteboard.general
            // save every item with all its types (one item each, preserving
            // order); skipped only by the key-delete path — the menu path
            // always has a non-empty replacement by now (Word deletions
            // were rewritten as replacements)
            var saved: [[(NSPasteboard.PasteboardType, Data)]]?
            if !replacement.isEmpty {
                var entries: [[(NSPasteboard.PasteboardType, Data)]] = []
                for item in pb.pasteboardItems ?? [] {
                    var entry: [(NSPasteboard.PasteboardType, Data)] = []
                    for type in item.types {
                        if let data = item.data(forType: type) {
                            entry.append((type, data))
                        }
                    }
                    entries.append(entry)
                }
                saved = entries
            }

            var mechanism = "keyEvent"
            var pasteboardSet = false
            if useMenuCommands, let pid = element.pid {
                pb.clearContents()
                pb.setString(replacement, forType: .string)
                pasteboardSet = true
                let item = menuCommandItem(pid: pid, cmdChar: "V")
                if item?.press() == true {
                    mechanism = "menuPaste"
                } else {
                    dbgLog(
                        "pasteboard: menu command "
                        + (item == nil ? "not found" : "AXPress failed")
                        + " — key-event fallback"
                    )
                }
            }
            if mechanism == "keyEvent" {
                let src = CGEventSource(stateID: .combinedSessionState)
                if !replacement.isEmpty {
                    if !pasteboardSet {
                        pb.clearContents()
                        pb.setString(replacement, forType: .string)
                    }
                    let vCode: CGKeyCode = 9 // kVK_ANSI_V
                    let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
                    let up = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
                    down?.flags = .maskCommand
                    up?.flags = .maskCommand
                    down?.post(tap: .cgSessionEventTap)
                    up?.post(tap: .cgSessionEventTap)
                    dbgLog("pasteboard: Cmd+V posted")
                } else {
                    let del: CGKeyCode = 51 // kVK_Delete — forward delete selection
                    let down = CGEvent(keyboardEventSource: src, virtualKey: del, keyDown: true)
                    let up = CGEvent(keyboardEventSource: src, virtualKey: del, keyDown: false)
                    down?.post(tap: .cgSessionEventTap)
                    up?.post(tap: .cgSessionEventTap)
                }
            }
            dbgLog("pasteboard: mechanism=\(mechanism)")

            func restoreClipboard() {
                guard let saved else { return }
                // restore no earlier than 300 ms after posting the paste
                let wait = max(0, 0.3 - (CFAbsoluteTimeGetCurrent() - t0))
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    pb.clearContents()
                    let items = saved.map { entry -> NSPasteboardItem in
                        let item = NSPasteboardItem()
                        for (type, data) in entry {
                            item.setData(data, forType: type)
                        }
                        return item
                    }
                    if !items.isEmpty {
                        pb.writeObjects(items)
                    }
                }
            }

            var lastSnippet = ""
            func snippet(_ text: String) -> String {
                let u = Array(text.utf16)
                let lo = max(0, start - 20)
                let hi = min(u.count, end + 20)
                return String(decoding: u[lo..<hi], as: UTF16.self)
                    .replacingOccurrences(of: "\r", with: "␍")
                    .replacingOccurrences(of: "\n", with: "⏎")
            }
            func poll(_ deadline: CFAbsoluteTime) {
                if let after = element.stringValue {
                    let s = snippet(after)
                    if s != lastSnippet {
                        lastSnippet = s
                        dbgLog(
                            "verify +\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s"
                            + " …\(s)…"
                        )
                    }
                    if pasteVerified(
                        current: before, after: after,
                        start: start, end: end, replacement: replacement
                    ) {
                        dbgLog("pasteboard: verified ok")
                        restoreClipboard()
                        completion(true)
                        return
                    }
                }
                if CFAbsoluteTimeGetCurrent() >= deadline {
                    dbgLog("pasteboard: deadline reached unverified")
                    restoreClipboard()
                    completion(false)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    poll(deadline)
                }
            }
            // give the keystroke a beat to land before the first read
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                poll(CFAbsoluteTimeGetCurrent() + 0.6)
            }
        }
        settle()
    }

    /// AX path first, pasteboard/delete fallback; the completion runs on the
    /// main queue once the write is verified (or has definitively failed).
    /// `start`/`end` are element-local UTF-16 offsets; `label` is only for
    /// logs (rule id, or "ai-rewrite").
    static func apply(
        element: AXElement, start: Int, end: Int,
        matched: String, replacement: String,
        baseOffset: Int = 0, label: String, log: Logger,
        completion: @escaping (Result) -> Void
    ) {
        // BUG-01: never let two writes into the same app overlap — a second
        // paste racing the first lands at the post-write caret. Keyed by pid
        // (not element identity): Word exposes one AXTextArea per page, all
        // sharing one document.
        let gateKey = element.pid ?? pid_t(truncatingIfNeeded: CFHash(element.raw))
        guard applyGate.begin(gateKey) else {
            dbgLog("apply REJECTED: write already in flight (\(label))")
            log.notice("skipped — write already in flight: \(label)")
            completion(Result(path: .aborted, success: false))
            return
        }
        func finish(_ result: Result) {
            applyGate.end(gateKey)
            completion(result)
        }
        let bundleId = element.pid.flatMap {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
        if skipsAXWrite(bundleId: bundleId) {
            // freshness on the live value, then straight to pasteboard
            guard let current = element.stringValue,
                  isFresh(text: current, start: start, end: end, matched: matched)
            else {
                log.notice("replacement aborted (text changed/unreadable): \(label)")
                finish(Result(path: .aborted, success: false))
                return
            }
            dbgLog("applyViaAX skipped (Word)")
            applyViaPasteboard(
                element: element, start: start, end: end,
                matched: matched, replacement: replacement,
                baseline: current, baseOffset: baseOffset,
                useMenuCommands: true
            ) { ok in
                log.info("replaced via \(replacement.isEmpty ? "delete-key" : "pasteboard") (\(ok ? "verified" : "unverified")): \(label)")
                finish(Result(path: .pasteboard, success: ok))
            }
            return
        }
        guard let attempt = applyViaAX(
            element: element, start: start, end: end,
            matched: matched, replacement: replacement, baseOffset: baseOffset
        ) else {
            log.notice("replacement aborted (text changed): \(label)")
            finish(Result(path: .aborted, success: false))
            return
        }
        switch attempt.decision {
        case .success:
            log.info("replaced via AXSelectedText: \(label)")
            finish(Result(path: .axSelectedText, success: true))
        case .failNoPaste:
            log.warning("AX write inconclusive, not pasting: \(label)")
            finish(Result(path: .axSelectedText, success: false))
        case .fallbackToPasteboard:
            applyViaPasteboard(
                element: element, start: start, end: end,
                matched: matched, replacement: replacement,
                baseline: attempt.baseline, baseOffset: baseOffset
            ) { ok in
                log.info("replaced via \(replacement.isEmpty ? "delete-key" : "pasteboard") (\(ok ? "verified" : "unverified")): \(label)")
                finish(Result(path: .pasteboard, success: ok))
            }
        }
    }

    /// Finding-based convenience wrapper.
    static func apply(
        element: AXElement, finding: Finding, replacement: String,
        matched: String, baseOffset: Int = 0, log: Logger,
        completion: @escaping (Result) -> Void
    ) {
        apply(
            element: element,
            start: Int(finding.start), end: Int(finding.end),
            matched: matched, replacement: replacement,
            baseOffset: baseOffset, label: finding.ruleId, log: log,
            completion: completion
        )
    }
}
