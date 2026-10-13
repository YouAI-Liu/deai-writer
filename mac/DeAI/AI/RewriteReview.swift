import Foundation

/// Lossless review of a rewrite. Every unchanged byte of text comes from a
/// matched token, and each change switches between its complete original and
/// revised span. Unlike lexicon pairs, whitespace and large edits are retained.
struct RewriteReview {
    struct Edit: Equatable, Identifiable {
        let id: Int
        let original: String
        let revised: String
    }

    enum Segment {
        case unchanged(String)
        case edit(Edit)
    }

    let id = UUID()
    let original: String
    let result: String
    let segments: [Segment]
    let edits: [Edit]
    let isWholePassage: Bool

    init(original: String, result: String) {
        self.original = original
        self.result = result
        if Self.identical(original, result) {
            segments = [.unchanged(original)]
            edits = []
            isWholePassage = false
            return
        }
        let a = Self.tokens(original), b = Self.tokens(result)
        // Bound worst-case alignment work for unexpectedly long model output.
        if a.count + b.count > 12_000 || a.count * b.count > 16_000_000 {
            let edit = Edit(id: 0, original: original, revised: result)
            segments = [.edit(edit)]
            edits = [edit]
            isWholePassage = true
            return
        }
        // String equality normalizes Unicode; byte tokens also preserve changes
        // between precomposed and decomposed spellings without splitting them.
        let difference = b.map { Data($0.utf8) }.difference(from: a.map { Data($0.utf8) })
        var removed: Set<Int> = [], inserted: Set<Int> = []
        for change in difference {
            switch change {
            case let .remove(index, _, _): removed.insert(index)
            case let .insert(index, _, _): inserted.insert(index)
            }
        }
        var segments: [Segment] = [], edits: [Edit] = []
        var i = 0, j = 0, unchanged = ""
        while i < a.count || j < b.count {
            if removed.contains(i) || inserted.contains(j) {
                if !unchanged.isEmpty {
                    segments.append(.unchanged(unchanged)); unchanged = ""
                }
                var from = "", to = ""
                while i < a.count, removed.contains(i) { from += a[i]; i += 1 }
                while j < b.count, inserted.contains(j) { to += b[j]; j += 1 }
                let edit = Edit(id: edits.count, original: from, revised: to)
                edits.append(edit); segments.append(.edit(edit))
            } else {
                // CollectionDifference preserves the order of all matches.
                unchanged += a[i]; i += 1; j += 1
            }
        }
        if !unchanged.isEmpty { segments.append(.unchanged(unchanged)) }
        self.segments = segments
        self.edits = edits
        isWholePassage = false
    }

    func text(accepting selected: Set<Int>) -> String {
        segments.map { segment in
            switch segment {
            case let .unchanged(text): return text
            case let .edit(edit): return selected.contains(edit.id) ? edit.revised : edit.original
            }
        }.joined()
    }

    static func identical(_ a: String, _ b: String) -> Bool {
        a.utf8.elementsEqual(b.utf8)
    }

    /// Character tokens keep emoji, combining marks and CRLF intact; ASCII
    /// words stay together so users do not review individual English letters.
    private static func tokens(_ text: String) -> [String] {
        var out: [String] = [], word = ""
        for character in text {
            if character.isASCII && (character.isLetter || character.isNumber || character == "'") {
                word.append(character)
            } else {
                if !word.isEmpty { out.append(word); word = "" }
                out.append(String(character))
            }
        }
        if !word.isEmpty { out.append(word) }
        return out
    }
}
