import AppKit
import ApplicationServices

/// A content snapshot uses document offsets; page elements only supply geometry.
enum TextDocument {
    struct Slice {
        let range: CFRange
        let text: String
    }

    /// Never join missing, overlapping or stale pages into a plausible document.
    static func assemble(_ slices: [Slice], length: Int) -> String? {
        guard length >= 0 else { return nil }
        var units: [UInt16] = []
        for slice in slices.sorted(by: { $0.range.location < $1.range.location }) {
            guard slice.range.location == units.count,
                  slice.range.length >= 0,
                  slice.text.utf16.count == slice.range.length,
                  slice.range.length <= length - units.count else { return nil }
            units.append(contentsOf: slice.text.utf16)
        }
        guard units.count == length else { return nil }
        return String(decoding: units, as: UTF16.self)
    }

    static func isWord(_ element: AXElement) -> Bool {
        element.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            == "com.microsoft.Word" && element.sharedCharacterRange != nil
    }

    static func read(_ element: AXElement) -> String? {
        guard isWord(element) else { return element.stringValue }
        guard let length = element.numberOfCharacters, length >= 0 else { return nil }
        let window = element.containingWindow
        let document: String? = window?.attribute("AXDocument")
        // Some Word versions support the full shared range directly.
        if let text = element.stringForRange(CFRange(location: 0, length: length)),
           text.utf16.count == length,
           element.numberOfCharacters == length,
           (window?.attribute("AXDocument") as String?) == document {
            return text
        }
        let pages = element.sharedTextElements
        guard !pages.isEmpty else { return nil }
        var slices: [Slice] = []
        for page in pages {
            guard let range = page.sharedCharacterRange, let text = page.stringValue,
                  let pageWindow = page.containingWindow,
                  let window, CFEqual(pageWindow.raw, window.raw) else { return nil }
            slices.append(Slice(range: range, text: text))
        }
        guard element.numberOfCharacters == length,
              (window?.attribute("AXDocument") as String?) == document else { return nil }
        // Pagination can change during AX calls without changing document length.
        for (page, slice) in zip(pages, slices) {
            guard let range = page.sharedCharacterRange,
                  range.location == slice.range.location,
                  range.length == slice.range.length,
                  page.stringValue == slice.text else { return nil }
        }
        return assemble(slices, length: length)
    }
}

/// Captured before displaying a result, retained across delayed write operations.
struct TextDocumentIdentity {
    let element: AXElement
    let pid: pid_t?
    let window: AXElement?
    let document: String?
    let windowTitle: String?

    init(element: AXElement) {
        self.element = element
        pid = element.pid
        window = element.containingWindow
        document = window?.attribute("AXDocument")
        windowTitle = window?.title
    }

    func isCurrent(requireFocus: Bool = true) -> Bool {
        guard let pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let window,
              let focusedWindow: AXUIElement = AXElement.application(pid: pid)
                .attribute(kAXFocusedWindowAttribute),
              CFEqual(window.raw, focusedWindow),
              let liveWindow = element.containingWindow,
              CFEqual(window.raw, liveWindow.raw),
              (window.attribute("AXDocument") as String?) == document,
              window.title == windowTitle else { return false }
        if !requireFocus { return true }
        guard let focused: AXUIElement = AXElement.application(pid: pid)
            .attribute(kAXFocusedUIElementAttribute) else { return false }
        if CFEqual(focused, element.raw) { return true }
        guard TextDocument.isWord(element) else { return false }
        // Word focuses either a page or a container above its document body.
        // A ribbon/search field must never qualify just because the window matches.
        if element.sharedTextElements.contains(where: { CFEqual($0.raw, focused) }) {
            return true
        }
        var ancestor = element.parent
        for _ in 0..<16 {
            guard let current = ancestor,
                  current.role != kAXWindowRole, current.role != kAXApplicationRole
            else { break }
            if CFEqual(current.raw, focused) { return true }
            ancestor = current.parent
        }
        return false
    }
}
