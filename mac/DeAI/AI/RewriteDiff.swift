import Foundation

/// Word-level changed pairs between an original text and its rewrite — the
/// data behind the rewrite panel's 记住改法 list. Pure & testable.
///
/// Tokenization: each CJK char is its own token, `[A-Za-z0-9']+` runs are
/// latin-word tokens, every other char (punctuation) is a token; whitespace
/// is skipped for matching but kept in the reconstructed pair text.
/// LCS-diff, then consecutive delete+insert token runs are coalesced into a
/// pair (the pair text is the original/result *substring* spanning the
/// changed tokens, so internal spacing/punctuation survives).
enum RewriteDiff {
    struct Pair: Equatable {
        /// Text in the original; empty = pure insertion.
        let from: String
        /// Text in the rewrite; empty = pure deletion.
        let to: String

        /// The lexicon entry this pair becomes. A changed span is a
        /// `replace`; a pure deletion is an `avoid` whose term drops
        /// trailing punctuation (「说白了，」 should avoid 说白了, not the
        /// comma); a pure insertion has no term to learn from.
        var lexiconCandidate: (
            kind: LexiconEntry.Kind, term: String, replacement: String?
        )? {
            guard !from.isEmpty else { return nil }
            if to.isEmpty {
                let term = RewriteDiff.trimmingEndPunctuation(from)
                return term.isEmpty ? nil : (.avoid, term, nil)
            }
            return (.replace, from, to)
        }
    }

    /// Sentence punctuation dropped from the end of avoid-terms.
    private static let endPunctuation = CharacterSet(
        charactersIn: "，,。．.、；;：:！!？?…—-·"
    )

    static func trimmingEndPunctuation(_ s: String) -> String {
        var t = s
        while let last = t.last,
              last.isWhitespace
                || String(last).rangeOfCharacter(from: endPunctuation) != nil {
            t.removeLast()
        }
        return t
    }

    private struct Token {
        let text: String
        /// char-index range in the source string. (Not Equatable: positions
        /// differ between the two strings — comparisons must use `text`.)
        let start: Int
        let end: Int
    }

    private static func tokenize(_ s: String) -> [Token] {
        let chars = Array(s)
        var tokens: [Token] = []
        var i = 0
        func isLatinWord(_ c: Character) -> Bool {
            c.isASCII && (c.isLetter || c.isNumber || c == "'")
        }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c.isNewline {
                i += 1
                continue
            }
            if isLatinWord(c) {
                var j = i
                while j < chars.count, isLatinWord(chars[j]) { j += 1 }
                tokens.append(
                    Token(text: String(chars[i..<j]), start: i, end: j)
                )
                i = j
            } else {
                tokens.append(Token(text: String(c), start: i, end: i + 1))
                i += 1
            }
        }
        return tokens
    }

    /// `(delete-count, insert-count)` blocks after the LCS alignment.
    /// Kept runs between adjacent change blocks merge them (coalesce).
    private static func changeBlocks(
        _ a: [Token], _ b: [Token]
    ) -> [(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int)] {
        let n = a.count
        let m = b.count
        guard n > 0, m > 0 else {
            return n + m > 0 ? [(0, n, 0, m)] : []
        }
        // LCS table
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i].text == b[j].text
                    ? lcs[i + 1][j + 1] + 1
                    : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        // walk: each contiguous run of non-matching tokens is one block
        // (adjacent deletes+inserts coalesce automatically)
        var blocks: [(Int, Int, Int, Int)] = []
        var i = 0
        var j = 0
        var open: (a: Int, b: Int)?
        while i < n && j < m {
            if a[i].text == b[j].text {
                if let c = open {
                    blocks.append((c.a, i, c.b, j))
                    open = nil
                }
                i += 1
                j += 1
            } else {
                if open == nil { open = (i, j) }
                if lcs[i + 1][j] >= lcs[i][j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
        }
        if let c = open {
            blocks.append((c.a, n, c.b, m))
        } else if i < n || j < m {
            // trailing inserts/deletes with no preceding change
            blocks.append((i, n, j, m))
        }
        return blocks
    }

    /// Word-level `(from, to)` pairs, capped at `maxPairs`; pairs whose
    /// either side exceeds `maxLen` chars are skipped.
    static func wordPairs(
        original: String,
        result: String,
        maxPairs: Int = 10,
        maxLen: Int = 20
    ) -> [Pair] {
        let a = tokenize(original)
        let b = tokenize(result)
        let aChars = Array(original)
        let bChars = Array(result)
        var pairs: [Pair] = []
        for block in changeBlocks(a, b) {
            // skip unchanged whitespace-only spans? The substring spans the
            // changed tokens' char range, so interior unchanged content is
            // intentionally included (it moved with the tokens).
            let from = block.aEnd > block.aStart
                ? String(aChars[a[block.aStart].start..<a[block.aEnd - 1].end])
                : ""
            let to = block.bEnd > block.bStart
                ? String(bChars[b[block.bStart].start..<b[block.bEnd - 1].end])
                : ""
            if from == to { continue }
            if from.count > maxLen || to.count > maxLen { continue }
            pairs.append(Pair(from: from, to: to))
            if pairs.count >= maxPairs { break }
        }
        return pairs
    }

    /// What the rewrite panel's 记住改法 section shows.
    enum RememberSectionState: Equatable {
        /// No checkbox list and no note — the rewrite was identical.
        case hidden
        /// Text changed but every diff block was unsplittable — a muted
        /// one-line note instead of the (empty) checkbox list.
        case note
        /// Usable pairs → the expandable checkbox list + 加入词库.
        case list
    }

    /// Section selection: any usable pair → list; a changed text with no
    /// usable pairs → note; nothing changed → hidden.
    static func rememberSection(
        changed: Bool, pairs: [Pair]
    ) -> RememberSectionState {
        if !pairs.isEmpty { return .list }
        return changed ? .note : .hidden
    }
}
