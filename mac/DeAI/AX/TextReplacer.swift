import AppKit
import CoreGraphics
import OSLog

/// Apply a suggestion's replacement into the target app: AXSelectedText first,
/// pasteboard+Cmd+V fallback. Pure helpers are separated for unit tests.
enum TextReplacer {
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

    /// Try the AX path on `element`. `start`/`end` are element-local; the
    /// selection range is written in shared-document offsets (`baseOffset`).
    /// Returns nil if freshness failed (abort); otherwise the decision for
    /// the caller to act on.
    static func applyViaAX(
        element: AXElement, start: Int, end: Int,
        matched: String, replacement: String, baseOffset: Int = 0
    ) -> AXDecision? {
        // freshness: re-read current value
        guard let current = element.stringValue else { return .failNoPaste }
        guard isFresh(text: current, start: start, end: end, matched: matched) else {
            return nil
        }
        guard element.setSelectedTextRange(
            CFRange(location: baseOffset + start, length: end - start)
        ) else {
            return .failNoPaste
        }
        let setOK = element.setSelectedText(replacement)
        let after = element.stringValue ?? current
        return decide(
            setOK: setOK, current: current, after: after,
            start: start, end: end, replacement: replacement
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
            // host normalization (e.g. Word may append a paragraph mark) —
            // the write counts if the replacement sits at [start, start+len)
            return isFresh(
                text: after,
                start: start,
                end: start + replacement.utf16.count,
                matched: replacement
            )
        }
        // deletion: length shrank by exactly (end - start) and everything
        // before `start` is untouched
        let u16After = Array(after.utf16)
        let u16Before = Array(current.utf16)
        guard u16After.count == u16Before.count - (end - start),
              start <= u16After.count else { return false }
        return u16After[..<start].elementsEqual(u16Before[..<start])
    }

    /// Pasteboard/delete fallback. The selection must be verifiably on the
    /// requested (shared-document) range first — pasting without it would
    /// insert at the caret. An empty `replacement` posts Forward Delete
    /// (BUG-11: pasting an empty string does not delete in Word) and never
    /// touches the clipboard. Success is reported asynchronously after
    /// re-reading the element's text (poll every 50 ms, up to 600 ms);
    /// the clipboard is restored after verification, but not before 300 ms
    /// have elapsed since the paste.
    static func applyViaPasteboard(
        element: AXElement, start: Int, end: Int,
        replacement: String, baseOffset: Int = 0,
        completion: @escaping (Bool) -> Void
    ) {
        let wanted = CFRange(location: baseOffset + start, length: end - start)
        guard element.setSelectedTextRange(wanted),
              let got = element.selectedTextRange,
              got.location == wanted.location, got.length == wanted.length
        else {
            completion(false)
            return
        }
        let before = element.stringValue
        let t0 = CFAbsoluteTimeGetCurrent()

        let pb = NSPasteboard.general
        // save every item with all its types (one item each, preserving
        // order); skipped entirely for the deletion path
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

        let src = CGEventSource(stateID: .combinedSessionState)
        if let saved {
            pb.clearContents()
            pb.setString(replacement, forType: .string)
            let vCode: CGKeyCode = 9 // kVK_ANSI_V
            let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cgSessionEventTap)
            up?.post(tap: .cgSessionEventTap)
        } else {
            let del: CGKeyCode = 51 // kVK_Delete — forward delete selection
            let down = CGEvent(keyboardEventSource: src, virtualKey: del, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: del, keyDown: false)
            down?.post(tap: .cgSessionEventTap)
            up?.post(tap: .cgSessionEventTap)
        }

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

        func poll(_ deadline: CFAbsoluteTime) {
            if let before, let after = element.stringValue,
               pasteVerified(
                   current: before, after: after,
                   start: start, end: end, replacement: replacement
               ) {
                restoreClipboard()
                completion(true)
                return
            }
            if CFAbsoluteTimeGetCurrent() >= deadline {
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

    /// AX path first, pasteboard/delete fallback; the completion runs on the
    /// main queue once the write is verified (or has definitively failed).
    static func apply(
        element: AXElement, finding: Finding, replacement: String,
        matched: String, baseOffset: Int = 0, log: Logger,
        completion: @escaping (Result) -> Void
    ) {
        let start = Int(finding.start)
        let end = Int(finding.end)
        switch applyViaAX(
            element: element, start: start, end: end,
            matched: matched, replacement: replacement, baseOffset: baseOffset
        ) {
        case .some(.success):
            log.info("replaced via AXSelectedText: \(finding.ruleId)")
            completion(Result(path: .axSelectedText, success: true))
        case .none:
            log.notice("replacement aborted (text changed): \(finding.ruleId)")
            completion(Result(path: .aborted, success: false))
        case .some(.failNoPaste):
            log.warning("AX write inconclusive, not pasting: \(finding.ruleId)")
            completion(Result(path: .axSelectedText, success: false))
        case .some(.fallbackToPasteboard):
            applyViaPasteboard(
                element: element, start: start, end: end,
                replacement: replacement, baseOffset: baseOffset
            ) { ok in
                log.info("replaced via \(replacement.isEmpty ? "delete-key" : "pasteboard") (\(ok ? "verified" : "unverified")): \(finding.ruleId)")
                completion(Result(path: .pasteboard, success: ok))
            }
        }
    }
}
