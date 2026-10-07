import CoreFoundation
import Foundation

/// What an "AI 改写" operates on: the selected range, or when the selection
/// is collapsed, the paragraph containing the caret. All offsets are
/// element-local UTF-16 code units; `selection` arrives in shared-document
/// offsets (Word pages) and is translated by `baseOffset`.
enum RewriteScope {
    /// Above this the caller shows "选中内容过长（上限 4000 字）".
    static let maxLength = 4000

    /// Paragraph separators: LF, CR, U+2029, U+2028 (excluded from scope).
    private static let separators: Set<UTF16.CodeUnit> = [
        0x0A, 0x0D, 0x2028, 0x2029,
    ]

    /// Returns the element-local `[start, end)` scope, or nil when the text
    /// is empty or the scope contains only whitespace.
    static func compute(
        text: String,
        selection: CFRange?,
        baseOffset: Int
    ) -> (start: Int, end: Int)? {
        let units = Array(text.utf16)
        let len = units.count
        guard len > 0 else { return nil }

        var s: Int
        var e: Int
        if let sel = selection, sel.length > 0 {
            // real selection: shared → local, clamped to the element's slice
            let ls = sel.location - baseOffset
            s = max(0, min(ls, len))
            e = max(0, min(ls + sel.length, len))
            guard s < e else { return nil }
        } else {
            // collapsed caret: expand to the enclosing paragraph
            let caret = max(
                0, min((selection?.location ?? baseOffset) - baseOffset, len)
            )
            s = units[0..<caret].lastIndex(where: {
                separators.contains($0)
            }).map { $0 + 1 } ?? 0
            e = units[caret...].firstIndex(where: {
                separators.contains($0)
            }) ?? len
            guard s < e else { return nil }
        }
        let scope = String(decoding: units[s..<e], as: UTF16.self)
        if scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return (s, e)
    }

    /// Match the host's newline convention so a replace doesn't flip the
    /// document's line endings (Word uses LF, TextEdit CR, some apps U+2029).
    static func normalizeNewlines(
        _ output: String, likeOriginal original: String
    ) -> String {
        if original.contains("\r"), !original.contains("\r\n") {
            return output
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r")
        }
        if original.contains("\u{2029}") {
            return output
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "\u{2029}")
        }
        return output
    }
}
