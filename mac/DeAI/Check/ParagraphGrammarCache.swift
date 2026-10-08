import Foundation

/// A paragraph of text with its UTF-16 start offset in the source text.
struct ParagraphSlice: Equatable {
    let start: UInt32 // UTF-16 code units
    let end: UInt32 // UTF-16 code units, exclusive of the separator
    let text: String
}

/// Split `text` on `\n`, `\r`, `\u2028`, `\u2029` into paragraph slices with
/// UTF-16 offsets. Matches RULES.md 段落切分 (Word emits LF, TextEdit CR).
/// CRLF is treated as one break (the `\n` after `\r` yields an empty
/// paragraph that is skipped by callers).
///
/// Paragraph strings are decoded straight from the UTF-16 buffer —
/// `String.Index(utf16Offset:in:)` costs O(offset) per separator, which made
/// this O(chars × paragraphs).
func splitParagraphs(_ text: String) -> [ParagraphSlice] {
    let separators: Set<UInt16> = [0x000A, 0x000D, 0x2028, 0x2029]
    var out: [ParagraphSlice] = []
    let utf16 = Array(text.utf16)
    var start = 0
    var i = 0
    while i < utf16.count {
        if separators.contains(utf16[i]) {
            out.append(
                ParagraphSlice(
                    start: UInt32(start),
                    end: UInt32(i),
                    text: String(decoding: utf16[start..<i], as: UTF16.self)
                )
            )
            start = i + 1
            // swallow the LF of a CRLF pair so it doesn't make an empty para
            if utf16[i] == 0x000D, i + 1 < utf16.count, utf16[i + 1] == 0x000A {
                start = i + 2
                i += 1
            }
        }
        i += 1
    }
    out.append(
        ParagraphSlice(
            start: UInt32(start),
            end: UInt32(utf16.count),
            text: String(decoding: utf16[start...], as: UTF16.self)
        )
    )
    return out
}

/// Minimal interface so tests can inject a counting fake.
protocol GrammarChecker {
    func check(text: String) -> [Finding]
}

/// Harper grammar check through DeAICore (grammar category only).
/// `sensitivity` is pinned to 3 because all grammar findings are tier 1
/// anyway; the cache key is the paragraph text (dialect is fixed American).
struct CoreGrammarChecker: GrammarChecker {
    let checker: Checker

    init(checker: Checker) {
        self.checker = checker
    }

    func check(text: String) -> [Finding] {
        checker.check(
            text: text,
            opts: CheckOptions(
                grammar: true,
                aiToneEn: false,
                aiToneZh: false,
                markdown: false,
                personal: false,
                sensitivity: 3
            )
        )
        .filter { $0.category == .grammar }
    }
}

/// Grammar findings for a full text plus cache stats for diagnostics.
struct GrammarPass {
    let findings: [Finding]
    let hits: Int
    let misses: Int
}

/// LRU cache of per-paragraph grammar results so that typing only re-runs
/// harper on the edited paragraph. Key = paragraph text (dialect is fixed
/// American inside the core). `tick` gives O(1) recency updates — a
/// `recency.removeAll` array scan per hit was measurably hot.
final class ParagraphGrammarRunner {
    static let capacity = 2000

    private let checker: GrammarChecker
    private struct Entry {
        var findings: [Finding]
        var tick: UInt64
    }
    private var cache: [String: Entry] = [:]
    private var tick: UInt64 = 0

    init(checker: GrammarChecker) {
        self.checker = checker
    }

    /// Grammar findings for the whole text, UTF-16 offsets already shifted
    /// into source coordinates.
    func checkAll(text: String) -> GrammarPass {
        var out: [Finding] = []
        var hits = 0
        var misses = 0
        for para in splitParagraphs(text) where !para.text.isEmpty {
            let (findings, hit) = cachedFindings(for: para.text)
            hit ? (hits += 1) : (misses += 1)
            for f in findings {
                var shifted = f
                shifted.start += para.start
                shifted.end += para.start
                out.append(shifted)
            }
        }
        return GrammarPass(findings: out, hits: hits, misses: misses)
    }

    private func cachedFindings(for paragraph: String) -> ([Finding], Bool) {
        tick &+= 1
        if var hit = cache[paragraph] {
            hit.tick = tick
            cache[paragraph] = hit
            return (hit.findings, true)
        }
        let findings = checker.check(text: paragraph)
        cache[paragraph] = Entry(findings: findings, tick: tick)
        if cache.count > Self.capacity {
            // evict the coldest quarter — O(capacity) but amortized over
            // `capacity/4` inserts
            let doomed = cache.sorted { $0.value.tick < $1.value.tick }
                .prefix(Self.capacity / 4 + 1)
            for (k, _) in doomed {
                cache.removeValue(forKey: k)
            }
        }
        return (findings, false)
    }
}
