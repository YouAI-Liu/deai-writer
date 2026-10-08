import AppKit
import SwiftUI
import XCTest
@testable import DeAI

final class DeAITests: XCTestCase {
    private func slice(_ text: String, _ finding: Finding) -> String {
        (text as NSString).substring(
            with: NSRange(location: Int(finding.start), length: Int(finding.end - finding.start))
        )
    }

    private func options(
        grammar: Bool = true,
        aiToneEn: Bool = true,
        aiToneZh: Bool = true,
        markdown: Bool = true,
        personal: Bool = true,
        sensitivity: UInt8 = 2
    ) -> CheckOptions {
        CheckOptions(
            grammar: grammar,
            aiToneEn: aiToneEn,
            aiToneZh: aiToneZh,
            markdown: markdown,
            personal: personal,
            sensitivity: sensitivity
        )
    }

    func testMixedText() {
        let checker = Checker()
        let text = "我们不是工具，而是伙伴。This is an test."
        let findings = checker.check(text: text, opts: options())

        let zh = findings.first { $0.category == .aiToneZh }
        XCTAssertNotNil(zh)
        XCTAssertEqual(zh?.ruleId, "zh.fanan")
        XCTAssertEqual(zh?.tier, 2)
        XCTAssertEqual(zh.map { slice(text, $0) }, "不是工具，而是")

        let grammar = findings.first { $0.category == .grammar }
        XCTAssertNotNil(grammar)
        XCTAssertEqual(grammar?.tier, 1)
        XCTAssertEqual(grammar.map { slice(text, $0) }, "an")
        XCTAssertTrue(grammar?.suggestions.contains("a") ?? false)

        // harper must not flag anything inside the Chinese half
        for f in findings where f.category == .grammar {
            XCTAssertGreaterThan(Int(f.start), 12)
        }
    }

    func testOptionsToggle() {
        let checker = Checker()
        let text = "这是**粗体**文字"
        let findings = checker.check(
            text: text,
            opts: options(grammar: false, aiToneEn: false, aiToneZh: false, markdown: true)
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].ruleId, "md.bold")
        XCTAssertEqual(findings[0].tier, 1)
        XCTAssertEqual(slice(text, findings[0]), "**粗体**")
        XCTAssertEqual(findings[0].suggestions, ["粗体"])
    }

    func testSensitivity() {
        let checker = Checker()
        // banned_opener is tier 1, zh.dash is tier 2, zh.fanan_loose is tier 3
        let text = "说穿了，没别的办法。他——走了。这不是终点，是起点。"
        let ids = { (s: UInt8) -> Set<String> in
            Set(
                checker.check(
                    text: text,
                    opts: self.options(grammar: false, aiToneEn: false, markdown: false, sensitivity: s)
                ).map(\.ruleId)
            )
        }
        XCTAssertEqual(ids(1), ["zh.banned_opener"])
        XCTAssertEqual(ids(2), ["zh.banned_opener", "zh.dash"])
        XCTAssertEqual(ids(3), ["zh.banned_opener", "zh.dash", "zh.fanan_loose"])
    }

    /// The exact text used for the live overlay QA screenshots — sanity
    /// check that it really triggers markdown + zh + grammar findings.
    func testLiveQATextFindings() {
        let checker = Checker()
        let text = "说白了，这是一个**粗体**示例。值得注意的是，我们需要赋能。 This is an test."
        let findings = checker.check(text: text, opts: options())
        print("LIVE-QA findings:", findings.map { "\($0.category)/\($0.ruleId)" })
        XCTAssertTrue(findings.contains { $0.category == .markdown })
        XCTAssertTrue(findings.contains { $0.category == .aiToneZh })
        XCTAssertTrue(findings.contains { $0.category == .grammar })
    }

    func testStripMarkdown() {
        let text = "# 标题\n这是**粗体**和 `代码`，还有[链接](https://a.com)。"
        XCTAssertEqual(
            stripMarkdown(text: text, opts: options()),
            "标题\n这是粗体和 代码，还有链接。"
        )
    }
}

// MARK: - TextGeometry pure parts

final class TextGeometryTests: XCTestCase {
    private func mkFinding(_ s: UInt32, _ e: UInt32) -> Finding {
        Finding(
            category: .grammar, ruleId: "x", message: "", start: s, end: e,
            suggestions: [], tier: 1
        )
    }

    func testAxToCocoaConversion() {
        // primary screen maxY = 1440; AX rect at top-left origin
        let ax = CGRect(x: 100, y: 50, width: 80, height: 20)
        let cocoa = TextGeometry.axToCocoa(ax, primaryMaxY: 1440)
        XCTAssertEqual(cocoa, CGRect(x: 100, y: 1440 - 50 - 20, width: 80, height: 20))
    }

    func testLineSegmentsWithinOneLine() {
        // line lookup: everything on line 0 covering 0..<100
        let segs = TextGeometry.lineSegments(
            start: 5, end: 12,
            lineForIndex: { _ in 0 },
            rangeForLine: { _ in CFRange(location: 0, length: 100) }
        )
        XCTAssertEqual(segs.map { [$0.location, $0.length] }, [[5, 7]])
    }

    func testLineSegmentsAcrossThreeLines() {
        // lines: L0 0..<10, L1 10..<20, L2 20..<30
        let segs = TextGeometry.lineSegments(
            start: 5, end: 25,
            lineForIndex: { $0 / 10 },
            rangeForLine: { CFRange(location: $0 * 10, length: 10) }
        )
        XCTAssertEqual(
            segs.map { [$0.location, $0.length] },
            [[5, 5], [10, 10], [20, 5]]
        )
    }

    func testLineSegmentsUnsupportedFallsBackToSingle() {
        let segs = TextGeometry.lineSegments(
            start: 3, end: 40,
            lineForIndex: { _ in nil },
            rangeForLine: { _ in nil }
        )
        XCTAssertEqual(segs.map { [$0.location, $0.length] }, [[3, 37]])
    }

    func testFilterRects() {
        let elementFrame = CGRect(x: 0, y: 0, width: 500, height: 300)
        let good = CGRect(x: 10, y: 10, width: 40, height: 14)
        let zeroW = CGRect(x: 10, y: 10, width: 0, height: 14)
        let outside = CGRect(x: 1000, y: 10, width: 40, height: 14)
        XCTAssertEqual(
            TextGeometry.filterRects([good, zeroW, outside], elementFrame: elementFrame),
            [good]
        )
        // no element frame → keep rects with area
        XCTAssertEqual(
            TextGeometry.filterRects([good, zeroW], elementFrame: nil),
            [good]
        )
    }
}

// MARK: - Paragraph splitting + grammar cache

final class ParagraphGrammarCacheTests: XCTestCase {
    final class CountingChecker: GrammarChecker {
        var calls = 0
        var lastText = ""
        var result: [Finding] = []

        func check(text: String) -> [Finding] {
            calls += 1
            lastText = text
            return result
        }
    }

    private func mkFinding(_ s: UInt32, _ e: UInt32) -> Finding {
        Finding(
            category: .grammar, ruleId: "g", message: "", start: s, end: e,
            suggestions: ["x"], tier: 1
        )
    }

    func testSplitLF() {
        let paras = splitParagraphs("ab\ncd")
        XCTAssertEqual(paras.map(\.text), ["ab", "cd"])
        XCTAssertEqual(paras.map { [Int($0.start), Int($0.end)] }, [[0, 2], [3, 5]])
    }

    func testSplitCR() {
        let paras = splitParagraphs("ab\rcd")
        XCTAssertEqual(paras.map(\.text), ["ab", "cd"])
        XCTAssertEqual(paras.map { [Int($0.start), Int($0.end)] }, [[0, 2], [3, 5]])
    }

    func testSplitCRLF() {
        let paras = splitParagraphs("ab\r\ncd")
        // CRLF is one break — no empty middle paragraph
        XCTAssertEqual(paras.map(\.text), ["ab", "cd"])
        XCTAssertEqual(paras.map { [Int($0.start), Int($0.end)] }, [[0, 2], [4, 6]])
    }

    func testSplitU2029() {
        let paras = splitParagraphs("ab\u{2029}cd")
        XCTAssertEqual(paras.map(\.text), ["ab", "cd"])
        XCTAssertEqual(paras.map { [Int($0.start), Int($0.end)] }, [[0, 2], [3, 5]])
    }

    func testSplitUTF16OffsetsWithEmoji() {
        // 😀 = 2 UTF-16 units
        let paras = splitParagraphs("😀x\nzz")
        XCTAssertEqual(paras.map(\.text), ["😀x", "zz"])
        XCTAssertEqual(paras.map { [Int($0.start), Int($0.end)] }, [[0, 3], [4, 6]])
    }

    func testOffsetShifting() {
        let counter = CountingChecker()
        counter.result = [mkFinding(0, 1)]
        let runner = ParagraphGrammarRunner(checker: counter)
        let findings = runner.checkAll(text: "ok\nzz").findings
        XCTAssertEqual(findings.map { [Int($0.start), Int($0.end)] }, [[0, 1], [3, 4]])
        XCTAssertEqual(counter.calls, 2)
    }

    func testCacheHitAvoidsRecheck() {
        let counter = CountingChecker()
        counter.result = [mkFinding(0, 1)]
        let runner = ParagraphGrammarRunner(checker: counter)
        let first = runner.checkAll(text: "same\npara")
        let callsAfterFirst = counter.calls
        let second = runner.checkAll(text: "same\npara")
        XCTAssertEqual(counter.calls, callsAfterFirst) // no new checks
        XCTAssertEqual(first.misses, 2)
        XCTAssertEqual(second.hits, 2)
        XCTAssertEqual(second.misses, 0)
    }
}

// MARK: - FindingFilter

final class FindingFilterTests: XCTestCase {
    private func freshSettings() -> AppSettings {
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return AppSettings(userDefaults: ud)
    }

    private func mk(_ ruleId: String, _ cat: DeAI.Category, _ s: UInt32, _ e: UInt32) -> Finding {
        Finding(category: cat, ruleId: ruleId, message: "", start: s, end: e,
                suggestions: [], tier: 1)
    }

    func testPerAppMarkdownOff() {
        let settings = freshSettings()
        let text = "**bold**"
        let f = [mk("md.bold", .markdown, 0, 8)]
        // VSCode: markdown off by default
        XCTAssertTrue(
            FindingFilter.apply(f, text: text, settings: settings,
                                bundleId: "com.microsoft.VSCode").isEmpty
        )
        // TextEdit: markdown on
        XCTAssertEqual(
            FindingFilter.apply(f, text: text, settings: settings,
                                bundleId: "com.apple.TextEdit").count,
            1
        )
    }

    func testDisabledRuleIds() {
        let settings = freshSettings()
        settings.disabledRuleIds = ["zh.fanan"]
        let text = "不是A，而是B"
        let f = [mk("zh.fanan", .aiToneZh, 0, 6)]
        XCTAssertTrue(
            FindingFilter.apply(f, text: text, settings: settings,
                                bundleId: "x").isEmpty
        )
    }

    func testSessionIgnore() {
        let settings = freshSettings()
        let text = "**粗体**"
        settings.sessionIgnored.insert(
            AppSettings.IgnoreKey(ruleId: "md.bold", text: "**粗体**")
        )
        let f = [mk("md.bold", .markdown, 0, 6)]
        XCTAssertTrue(
            FindingFilter.apply(f, text: text, settings: settings,
                                bundleId: "x").isEmpty
        )
        // different matched text → still reported
        let text2 = "**加粗**"
        XCTAssertEqual(
            FindingFilter.apply(f, text: text2, settings: settings,
                                bundleId: "x").count,
            1
        )
    }

    func testCategoryToggles() {
        let settings = freshSettings()
        settings.aiToneEn = false
        let text = "delve into"
        let f = [
            mk("en.ai_vocab", .aiToneEn, 0, 5),
            mk("md.bold", .markdown, 0, 5),
        ]
        let out = FindingFilter.apply(f, text: text, settings: settings, bundleId: "x")
        XCTAssertEqual(out.map(\.ruleId), ["md.bold"])
    }
}

// MARK: - TextReplacer pure helpers

final class TextReplacerTests: XCTestCase {
    func testIsFresh() {
        XCTAssertTrue(TextReplacer.isFresh(text: "hello world", start: 0, end: 5, matched: "hello"))
        XCTAssertFalse(TextReplacer.isFresh(text: "hello world", start: 0, end: 5, matched: "HELLO"))
        XCTAssertFalse(TextReplacer.isFresh(text: "hi", start: 0, end: 5, matched: "hello"))
    }

    func testIsFreshWithEmoji() {
        // 😀 = UTF-16 units 0-1; "x" at unit 2
        XCTAssertTrue(TextReplacer.isFresh(text: "😀x", start: 2, end: 3, matched: "x"))
        XCTAssertFalse(TextReplacer.isFresh(text: "😀x", start: 0, end: 1, matched: "x"))
    }

    func testExpectedText() {
        XCTAssertEqual(
            TextReplacer.expectedText("hello world", start: 0, end: 5, replacement: "goodbye"),
            "goodbye world"
        )
        XCTAssertEqual(
            TextReplacer.expectedText("**粗体**文字", start: 0, end: 6, replacement: "粗体"),
            "粗体文字"
        )
        // deletion
        XCTAssertEqual(
            TextReplacer.expectedText("ab X", start: 3, end: 4, replacement: ""),
            "ab "
        )
        // out of range → unchanged
        XCTAssertEqual(
            TextReplacer.expectedText("ab", start: 0, end: 9, replacement: "z"),
            "ab"
        )
    }

    func testExpectedTextMatchesCoreApplySuggestion() {
        let text = "这是**粗体**文字"
        XCTAssertEqual(
            TextReplacer.expectedText(text, start: 2, end: 7, replacement: "粗体"),
            applySuggestion(text: text, start: 2, end: 7, replacement: "粗体")
        )
    }

    // MARK: decide() — the AX-write outcome table (review fix 3)

    /// set failed + doc unchanged → paste is safe
    func testDecideSetFailedUnchangedFallsBack() {
        let current = "hello world"
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: false, current: current, after: current,
                start: 0, end: 5, replacement: "goodbye"
            ),
            .fallbackToPasteboard
        )
    }

    /// set failed + doc changed meanwhile → do NOT paste (would double-apply)
    func testDecideSetFailedChangedIsNoPaste() {
        let current = "hello world"
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: false, current: current, after: "hello worlds",
                start: 0, end: 5, replacement: "goodbye"
            ),
            .failNoPaste
        )
    }

    /// set ok + doc equals expected (computed from `current`) → success
    func testDecideSetOkExactMatch() {
        let current = "hello world"
        let after = TextReplacer.expectedText(current, start: 0, end: 5, replacement: "goodbye")
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: true, current: current, after: after,
                start: 0, end: 5, replacement: "goodbye"
            ),
            .success
        )
    }

    /// set ok + host normalized the text but the replacement sits in place
    /// (e.g. Word appends a paragraph mark) → still success, never paste
    func testDecideSetOkNormalized() {
        let current = "hello"
        let after = "goodbye\n" // replacement applied + normalized
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: true, current: current, after: after,
                start: 0, end: 5, replacement: "goodbye"
            ),
            .success
        )
    }

    /// set ok + neither expected nor replacement-in-place → inconclusive,
    /// report failure on the AX path WITHOUT pasting
    func testDecideSetOkInconclusiveNoPaste() {
        let current = "hello world"
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: true, current: current, after: "totally different",
                start: 0, end: 5, replacement: "goodbye"
            ),
            .failNoPaste
        )
    }

    /// set "ok" + doc provably unchanged → nothing was written (Word page
    /// elements report success on a non-settable AXSelectedText — BUG-07),
    /// so the pasteboard fallback is safe and required.
    func testDecideSetOkUnchangedFallsBack() {
        let current = "hello world"
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: true, current: current, after: current,
                start: 0, end: 5, replacement: "goodbye"
            ),
            .fallbackToPasteboard
        )
        // deletion variant: unchanged is still a safe fallback
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: true, current: "ab X", after: "ab X",
                start: 3, end: 4, replacement: ""
            ),
            .fallbackToPasteboard
        )
    }

    /// deletion that lands exactly → success; inconclusive delete → no paste
    func testDecideDeletion() {
        let current = "ab X"
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: true, current: current, after: "ab ",
                start: 3, end: 4, replacement: ""
            ),
            .success
        )
        XCTAssertEqual(
            TextReplacer.decide(
                setOK: true, current: current, after: "ab XY",
                start: 3, end: 4, replacement: ""
            ),
            .failNoPaste
        )
    }

    // MARK: pasteVerified() — async write verification (BUG-11)

    func testPasteVerifiedExact() {
        let current = "第一段。说白了，下一段。"
        let after = "第一段。下一段。"
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: current, after: after,
                start: 4, end: 8, replacement: ""
            )
        )
    }

    /// the BUG-11 failure mode: the delete key never landed (or the paste of
    /// an empty string no-oped) — text identical → not verified
    func testPasteVerifiedUnchangedIsFalse() {
        let current = "第一段。说白了，下一段。"
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: current, after: current,
                start: 4, end: 8, replacement: ""
            )
        )
    }

    /// deletion where the host normalized something after the span (e.g.
    /// trailing paragraph mark) — length/prefix rule still accepts
    func testPasteVerifiedDeletionTolerantSuffix() {
        let current = "第一段。说白了，下一段。"
        // prefix unchanged, exactly (end-start) fewer units; suffix differs
        // only AFTER the deleted span — tolerated per spec predicate
        let after = "第一段。下段段。"
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: current, after: after,
                start: 4, end: 8, replacement: ""
            )
        )
        // wrong delta → not a verified delete
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: current, after: "第一段。白了下一段。",
                start: 4, end: 8, replacement: ""
            )
        )
        // prefix changed → not verified
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: current, after: "第X段。下一段。",
                start: 4, end: 8, replacement: ""
            )
        )
    }

    func testPasteVerifiedNonEmpty() {
        let current = "这是**粗体**文字"
        let after = "这是粗体文字"
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: current, after: after,
                start: 2, end: 8, replacement: "粗体"
            )
        )
        // normalized: host appended a trailing paragraph mark
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: current, after: "这是粗体文字\r",
                start: 2, end: 8, replacement: "粗体"
            )
        )
        // unchanged → false
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: current, after: current,
                start: 2, end: 8, replacement: "粗体"
            )
        )
    }

    /// BUG-01 r4: a doubled write ("goes goes") must never verify — the
    /// replacement sitting at the slot is not enough when the tail after
    /// it still contains the original matched text.
    func testPasteVerifiedDoubleApplyIsFalse() {
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: "He go to school", after: "He goes goes to school",
                start: 3, end: 5, replacement: "goes"
            )
        )
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: "He go to school", after: "He goes to school",
                start: 3, end: 5, replacement: "goes"
            )
        )
        // Word may append a trailing paragraph mark to the page value
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: "He go to school", after: "He goes to school\r",
                start: 3, end: 5, replacement: "goes"
            )
        )
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: "He go to school", after: "He goes to school\n",
                start: 3, end: 5, replacement: "goes"
            )
        )
        // tail genuinely different → not verified
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: "He go to school", after: "He goes to college",
                start: 3, end: 5, replacement: "goes"
            )
        )
        // prefix changed → not verified
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: "He go to school", after: "We goes to school",
                start: 3, end: 5, replacement: "goes"
            )
        )
    }

    /// A deletion that also eats a preceding character (BUG-11 r4: the
    /// delete key dropped the newline before the matched range) fails the
    /// exact length/prefix check.
    func testPasteVerifiedDeletionEatsNeighborIsFalse() {
        XCTAssertFalse(
            TextReplacer.pasteVerified(
                current: "第一段。\n说白了，下一段。", after: "第一段。下一段。",
                start: 5, end: 9, replacement: ""
            )
        )
        // correct deletion (newline preserved) still verifies
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: "第一段。\n说白了，下一段。", after: "第一段。\n下一段。",
                start: 5, end: 9, replacement: ""
            )
        )
    }

    // MARK: ApplyGate — at most one in-flight write per element (BUG-01)

    func testApplyGateSerializesPerElement() {
        var gate = TextReplacer.ApplyGate()
        XCTAssertTrue(gate.begin(42))
        // a second write on the same element while the first is in flight
        // is rejected — that race is what produced "goesgoes" in Word
        XCTAssertFalse(gate.begin(42))
        XCTAssertFalse(gate.begin(42))
        // a different element is unaffected
        XCTAssertTrue(gate.begin(7))
        // once the first write completes, the element is writable again
        gate.end(42)
        XCTAssertTrue(gate.begin(42))
        XCTAssertTrue(gate.inFlight.contains(42))
        XCTAssertTrue(gate.inFlight.contains(7))
        gate.end(42)
        gate.end(7)
        XCTAssertTrue(gate.inFlight.isEmpty)
    }

    // MARK: prePasteDecision() — settle before pasting (BUG-01)

    func testPrePasteDecision() {
        // text untouched since the AX write attempt → safe to paste
        XCTAssertEqual(
            TextReplacer.prePasteDecision(
                baseline: "He go to school", text: "He go to school",
                start: 3, end: 5, matched: "go", replacement: "goes"
            ),
            .paste
        )
        // the AX write landed late: "go"→"goes" — the matched range still
        // reads "go" (prefix), but the text differs from baseline, and the
        // slot now holds the replacement → already applied, never paste
        XCTAssertEqual(
            TextReplacer.prePasteDecision(
                baseline: "He go to school", text: "He goes to school",
                start: 3, end: 5, matched: "go", replacement: "goes"
            ),
            .alreadyApplied
        )
        // shrinking replacement "goes"→"go": "go" is a prefix of the
        // untouched text, so substring checks alone would false-positive;
        // baseline comparison keeps it .paste while unchanged
        XCTAssertEqual(
            TextReplacer.prePasteDecision(
                baseline: "He goes to school", text: "He goes to school",
                start: 3, end: 7, matched: "goes", replacement: "go"
            ),
            .paste
        )
        XCTAssertEqual(
            TextReplacer.prePasteDecision(
                baseline: "He goes to school", text: "He go to school",
                start: 3, end: 7, matched: "goes", replacement: "go"
            ),
            .alreadyApplied
        )
        // text changed to something unrelated → abort, never paste
        XCTAssertEqual(
            TextReplacer.prePasteDecision(
                baseline: "He go to school", text: "He went to school",
                start: 3, end: 5, matched: "go", replacement: "goes"
            ),
            .abort
        )
        // deletion: matched range gone via the earlier write → alreadyApplied
        XCTAssertEqual(
            TextReplacer.prePasteDecision(
                baseline: "说白了，确实如此", text: "确实如此",
                start: 0, end: 4, matched: "说白了，", replacement: ""
            ),
            .alreadyApplied
        )
        XCTAssertEqual(
            TextReplacer.prePasteDecision(
                baseline: "说白了，确实如此", text: "说白了，确实如此",
                start: 0, end: 4, matched: "说白了，", replacement: ""
            ),
            .paste
        )
    }

    /// Word skips the AX write entirely: its page-element setSelectedText
    /// can write while AXValue stays stale, so the settle loop would paste
    /// on top of it (BUG-01 r2).
    // MARK: wordDeletionAsReplacement() — Word Cut is a no-op (BUG-01 r5)

    private func assertExt(
        _ actual: (start: Int, end: Int, replacement: String)?,
        _ want: (Int, Int, String), file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("expected extension", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.start, want.0, file: file, line: line)
        XCTAssertEqual(actual.end, want.1, file: file, line: line)
        XCTAssertEqual(actual.replacement, want.2, file: file, line: line)
    }

    func testWordDeletionAsReplacement() {
        // following char is usable → extend end, paste it back
        assertExt(
            TextReplacer.wordDeletionAsReplacement(text: "ab", start: 0, end: 1),
            (0, 2, "b")
        )
        // following char is a paragraph separator → take the preceding one
        assertExt(
            TextReplacer.wordDeletionAsReplacement(text: "ab\ncd", start: 1, end: 2),
            (0, 2, "a")
        )
        // phrase at end of text → preceding char
        assertExt(
            TextReplacer.wordDeletionAsReplacement(text: "ab", start: 1, end: 2),
            (0, 2, "a")
        )
        // following neighbour is an emoji → whole surrogate pair
        assertExt(
            TextReplacer.wordDeletionAsReplacement(text: "a😀b", start: 0, end: 1),
            (0, 3, "😀")
        )
        // preceding neighbour is an emoji → whole surrogate pair, start -2
        assertExt(
            TextReplacer.wordDeletionAsReplacement(text: "a😀b", start: 3, end: 4),
            (1, 4, "😀")
        )
        // \r counts as a separator too → preceding char used
        assertExt(
            TextReplacer.wordDeletionAsReplacement(text: "ab\rc", start: 1, end: 2),
            (0, 2, "a")
        )
        // the paragraph sits alone between two separators → no usable char
        XCTAssertNil(
            TextReplacer.wordDeletionAsReplacement(text: "\nx\n", start: 1, end: 2)
        )
        // single-char text, deleting it → nil (both sides empty)
        XCTAssertNil(
            TextReplacer.wordDeletionAsReplacement(text: "x", start: 0, end: 1)
        )
        // empty range → nil
        XCTAssertNil(
            TextReplacer.wordDeletionAsReplacement(text: "abc", start: 1, end: 1)
        )
    }

    /// Scroll-suppression predicate: while the window is active nothing may
    /// draw; the trailing re-measure runs after it expires.
    func testScrollSuppressed() {
        XCTAssertTrue(AppController.scrollSuppressed(now: 10, until: 20))
        XCTAssertFalse(AppController.scrollSuppressed(now: 20, until: 20))
        XCTAssertFalse(AppController.scrollSuppressed(now: 21, until: 20))
        XCTAssertFalse(AppController.scrollSuppressed(now: 10, until: 0))
    }

    /// Word skips the AX write entirely: its page-element `setSelectedText`
    /// can write while AXValue stays stale, so the settle loop would paste
    /// on top of it (BUG-01 r2).
    func testSkipsAXWrite() {
        XCTAssertTrue(TextReplacer.skipsAXWrite(bundleId: "com.microsoft.Word"))
        XCTAssertFalse(
            TextReplacer.skipsAXWrite(bundleId: "com.apple.TextEdit")
        )
        XCTAssertFalse(TextReplacer.skipsAXWrite(bundleId: "com.apple.Notes"))
        XCTAssertFalse(TextReplacer.skipsAXWrite(bundleId: nil))
    }
}

// MARK: - AppSettings

final class AppSettingsTests: XCTestCase {
    private func fresh() -> (AppSettings, UserDefaults) {
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return (AppSettings(userDefaults: ud), ud)
    }

    func testDefaultsDisabledApps() {
        let (s, _) = fresh()
        XCTAssertFalse(s.isAppEnabled("com.google.Chrome"))
        XCTAssertFalse(s.isAppEnabled("com.apple.Terminal"))
        XCTAssertFalse(s.isAppEnabled("com.1password.1password"))
        XCTAssertFalse(s.isAppEnabled("com.local.deai"))
        // the whole com.local.deai[.*] family is excluded — Debug and
        // Release builds must ignore each other even via an explicit AppRule
        XCTAssertFalse(s.isAppEnabled("com.local.deai.debug"))
        s.appRules["com.local.deai"] = AppRule(enabled: true, markdown: true)
        XCTAssertFalse(s.isAppEnabled("com.local.deai"))
        // but the prefix must not overmatch unrelated ids
        XCTAssertTrue(s.isAppEnabled("com.local.deaix"))
        // own-app exclusion follows the live bundle id (debug id in tests)
        if let own = Bundle.main.bundleIdentifier {
            XCTAssertFalse(s.isAppEnabled(own))
        }
        XCTAssertTrue(s.isAppEnabled("com.apple.TextEdit"))
        XCTAssertTrue(s.isAppEnabled("com.microsoft.Word"))
    }

    func testDefaultsMarkdownOffApps() {
        let (s, _) = fresh()
        XCTAssertFalse(s.markdownEnabled(for: "com.microsoft.VSCode"))
        // Cursor is a code editor → markdown off by default too
        XCTAssertFalse(s.markdownEnabled(for: "com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(s.markdownEnabled(for: "com.apple.TextEdit"))
        // Obsidian sits in 笔记 (notes), which keeps markdown on by default
        XCTAssertTrue(s.markdownEnabled(for: "md.obsidian"))
    }

    func testAppRuleOverrides() {
        let (s, _) = fresh()
        s.setAppEnabled("com.google.Chrome", true)
        XCTAssertTrue(s.isAppEnabled("com.google.Chrome"))
        s.setAppEnabled("com.apple.TextEdit", false)
        XCTAssertFalse(s.isAppEnabled("com.apple.TextEdit"))
    }

    /// BUG-02: disabling then re-enabling the current app must flip the
    /// per-app rule back — the menu toggle relies on `isAppEnabled`.
    func testAppToggleRoundTrip() {
        let (s, _) = fresh()
        let id = "com.apple.TextEdit"
        XCTAssertTrue(s.isAppEnabled(id))
        s.setAppEnabled(id, false)
        XCTAssertFalse(s.isAppEnabled(id))
        s.setAppEnabled(id, true)
        XCTAssertTrue(s.isAppEnabled(id))
    }

    func testCodableRoundTrip() {
        let (s1, ud) = fresh()
        s1.autoUnderline = false
        s1.grammar = false
        s1.sensitivity = 3
        s1.disabledRuleIds = ["zh.dash", "en.em_dash"]
        s1.appRules["com.example.App"] = AppRule(enabled: false, markdown: false)

        let s2 = AppSettings(userDefaults: ud)
        XCTAssertFalse(s2.autoUnderline)
        XCTAssertFalse(s2.grammar)
        XCTAssertEqual(s2.sensitivity, 3)
        XCTAssertEqual(s2.disabledRuleIds, ["zh.dash", "en.em_dash"])
        XCTAssertEqual(s2.appRules["com.example.App"], AppRule(enabled: false, markdown: false))
    }

    func testSensitivityClamp() {
        let (s, _) = fresh()
        s.sensitivity = 9
        XCTAssertEqual(s.sensitivity, 2) // invalid → reset to default
    }

    func testSessionIgnoredIsNotPersisted() {
        let (s1, ud) = fresh()
        s1.sessionIgnored.insert(AppSettings.IgnoreKey(ruleId: "zh.dash", text: "——"))
        // force a persist by touching a stored property
        s1.autoUnderline = true
        let s2 = AppSettings(userDefaults: ud)
        XCTAssertTrue(s2.sessionIgnored.isEmpty)
    }

    /// Settings written by an older build (only the 8 original keys) must
    /// decode — preserved values plus defaults for the new fields, not a
    /// wholesale reset.
    func testOldFormatJSONDecodes() {
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let oldJSON = """
            {
              "autoUnderline": false,
              "grammar": false,
              "aiToneZh": true,
              "aiToneEn": false,
              "markdown": true,
              "sensitivity": 3,
              "disabledRuleIds": ["zh.dash"],
              "appRules": {"com.example.App": {"enabled": false, "markdown": true}}
            }
            """
        ud.set(oldJSON.data(using: .utf8)!, forKey: AppSettings.defaultsKey)
        let s = AppSettings(userDefaults: ud)
        XCTAssertFalse(s.autoUnderline)
        XCTAssertFalse(s.grammar)
        XCTAssertTrue(s.aiToneZh)
        XCTAssertFalse(s.aiToneEn)
        XCTAssertTrue(s.markdown)
        XCTAssertEqual(s.sensitivity, 3)
        XCTAssertEqual(s.disabledRuleIds, ["zh.dash"])
        XCTAssertEqual(s.appRules["com.example.App"], AppRule(enabled: false, markdown: true))
        // new fields fall back to defaults
        XCTAssertEqual(s.underline, .default)
        XCTAssertEqual(s.groupRules, AppGroup.defaultRules)
    }

    func testUnderlineAndGroupRulesRoundTrip() {
        let (s1, ud) = fresh()
        var appearance = s1.underline
        appearance.styles["grammar"] = UnderlineStyle(colorHex: "#00FF00", shape: .dotted)
        appearance.thickness = 2.5
        appearance.opacity = 0.7
        appearance.offset = 3
        appearance.dimLowConfidence = false
        appearance.highlightFill = true
        s1.underline = appearance

        var officeRule = s1.groupRules[.office]!
        officeRule.checks.remove(.aiToneZh)
        s1.groupRules[.office] = officeRule
        var browserRule = s1.groupRules[.browser]!
        browserRule.enabled = true
        s1.groupRules[.browser] = browserRule

        let s2 = AppSettings(userDefaults: ud)
        XCTAssertEqual(s2.underline, appearance)
        XCTAssertEqual(s2.groupRules[.office]?.checks.contains(.aiToneZh), false)
        XCTAssertEqual(s2.groupRules[.browser]?.enabled, true)
    }

    func testGroupForBundleId() {
        XCTAssertEqual(AppGroup.group(for: "com.microsoft.Word"), .office)
        XCTAssertEqual(AppGroup.group(for: "com.apple.Safari"), .browser)
        // JetBrains prefix rule
        XCTAssertEqual(AppGroup.group(for: "com.jetbrains.intellij"), .code)
        XCTAssertEqual(AppGroup.group(for: "com.jetbrains.CLion"), .code)
        XCTAssertEqual(AppGroup.group(for: "com.example.foo"), .other)
    }

    func testGroupDefaults() {
        let (s, _) = fresh()
        // browsers + sensitive off; notes on
        XCTAssertFalse(s.isAppEnabled("com.google.Chrome"))
        XCTAssertFalse(s.isAppEnabled("com.apple.Safari"))
        XCTAssertFalse(s.isAppEnabled("com.apple.Terminal"))
        XCTAssertTrue(s.isAppEnabled("com.apple.TextEdit"))
        // code group: all checks except markdown
        let vscode = s.checkOptions(for: "com.microsoft.VSCode")
        XCTAssertTrue(vscode.grammar)
        XCTAssertTrue(vscode.aiToneZh)
        XCTAssertTrue(vscode.aiToneEn)
        XCTAssertFalse(vscode.markdown)
    }

    /// A per-app AppRule.enabled overrides a disabled group; group-level
    /// check removal applies to every app in the group but not others.
    func testPerAppOverridesGroupAndCheckNarrowing() {
        let (s, _) = fresh()
        // browser group is disabled by default; a per-app rule re-enables it
        s.appRules["com.google.Chrome"] = AppRule(enabled: true, markdown: true)
        XCTAssertTrue(s.isAppEnabled("com.google.Chrome"))

        // turn off aiToneZh for the office group
        var office = s.groupRules[.office]!
        office.checks.remove(.aiToneZh)
        s.groupRules[.office] = office

        XCTAssertFalse(s.checkOptions(for: "com.microsoft.Word").aiToneZh)
        XCTAssertTrue(s.checkOptions(for: "com.apple.TextEdit").aiToneZh)
    }

    /// Per-app markdown override can only narrow: enabling it on an app
    /// whose group lacks markdown does NOT re-enable the check.
    func testPerAppMarkdownCannotWiden() {
        let (s, _) = fresh()
        s.appRules["com.microsoft.VSCode"] = AppRule(enabled: true, markdown: true)
        XCTAssertFalse(s.markdownEnabled(for: "com.microsoft.VSCode"))
        // and narrowing works the other way
        s.appRules["com.apple.TextEdit"] = AppRule(enabled: true, markdown: false)
        XCTAssertFalse(s.markdownEnabled(for: "com.apple.TextEdit"))
    }

    func testNewAppRuleMarkdownFollowsGroup() {
        let (s, _) = fresh()
        // code group lacks markdown → new exception defaults markdown off
        s.setAppEnabled("com.microsoft.VSCode", true)
        XCTAssertEqual(s.appRules["com.microsoft.VSCode"]?.markdown, false)
        // notes group has markdown → defaults on
        s.setAppEnabled("com.apple.TextEdit", true)
        XCTAssertEqual(s.appRules["com.apple.TextEdit"]?.markdown, true)
    }

    /// .sensitive is a hard exclusion list: enabling its group rule AND a
    /// per-app override still cannot turn a terminal/password app on.
    func testSensitiveAppsStayDisabled() {
        let (s, _) = fresh()
        s.groupRules[.sensitive] = GroupRule(
            enabled: true, checks: Set(CheckKind.allCases)
        )
        for id in [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.apple.keychainaccess",
            "com.1password.1password",
        ] {
            s.setAppEnabled(id, true)
            XCTAssertFalse(s.isAppEnabled(id), "\(id) must stay disabled")
        }
    }

    /// `.sensitive` is hidden from every group list in the UI.
    func testConfigurableExcludesSensitive() {
        XCTAssertFalse(AppGroup.configurable.contains(.sensitive))
        XCTAssertEqual(
            AppGroup.configurable,
            AppGroup.allCases.filter { $0 != .sensitive }
        )
        XCTAssertEqual(AppGroup.configurable.count, AppGroup.allCases.count - 1)
    }
}

// MARK: - UnderlineAppearance

final class UnderlineAppearanceTests: XCTestCase {
    /// The default appearance follows the theme-aware palette
    /// (colorHex "") while keeping the historical shapes.
    func testDefaultMatchesOldLook() {
        let d = UnderlineAppearance.default
        XCTAssertEqual(d.style(for: .grammar).colorHex, "")
        XCTAssertEqual(d.style(for: .grammar).shape, .wavy)
        XCTAssertEqual(d.style(for: .aiToneZh).colorHex, "")
        XCTAssertEqual(d.style(for: .aiToneZh).shape, .straight)
        XCTAssertEqual(d.style(for: .aiToneEn).colorHex, "")
        XCTAssertEqual(d.style(for: .markdown).colorHex, "")
        XCTAssertEqual(d.style(for: .markdown).shape, .straight)
        XCTAssertEqual(d.thickness, 1.2)
        XCTAssertEqual(d.opacity, 1)
        XCTAssertEqual(d.offset, 1)
        XCTAssertTrue(d.dimLowConfidence)
        XCTAssertFalse(d.highlightFill)
    }

    /// Default offset (1) must put the line exactly where the old code did:
    /// rect.minY + 1.
    func testDefaultOffsetReproducesOldY() {
        let rect = CGRect(x: 0, y: 100, width: 50, height: 14)
        XCTAssertEqual(
            UnderlineDrawing.underlineY(rect: rect, offset: 1),
            rect.minY + 1
        )
        XCTAssertEqual(
            UnderlineDrawing.underlineY(rect: rect, offset: -2),
            rect.minY + 4
        )
    }

    /// style(for:) falls back to the default for missing/foreign keys.
    func testStyleFallback() {
        var a = UnderlineAppearance.default
        a.styles = ["grammar": UnderlineStyle(colorHex: "#000000", shape: .dotted)]
        XCTAssertEqual(a.style(for: .grammar).colorHex, "#000000")
        XCTAssertEqual(a.style(for: .markdown).colorHex, "")
    }

    func testHexRoundTrip() {
        for hex in ["#E5484D", "#0090FF", "8B8D98", "#000000", "#FFFFFF"] {
            let color = NSColor(hex: hex)
            XCTAssertNotNil(color, hex)
            let normalized = hex.hasPrefix("#") ? hex : "#\(hex)"
            XCTAssertEqual(color?.hexString, normalized.uppercased())
        }
        XCTAssertNil(NSColor(hex: "#XYZXYZ"))
        XCTAssertNil(NSColor(hex: "#FFF"))
    }
}

// MARK: - settings window screenshots (renders each tab to /tmp)

final class SettingsScreenshotTests: XCTestCase {
    /// Retained for the whole test run — letting the hosting windows
    /// deallocate inside the test scope crashes XCTest's memory checker.
    private static var liveWindows: [NSWindow] = []

    func testRenderSettingsTabs() throws {
        // Opt-in: the normal suite must not write /tmp files or pin windows.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEAI_SCREENSHOTS"] == "1",
            "set DEAI_SCREENSHOTS=1 to render settings-tab PNGs to /tmp"
        )
        let work = {
            let settings = AppSettings(
                userDefaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!
            )
            for (tab, name) in [(0, "checks"), (1, "appearance"), (2, "ai")] {
                let hosting = NSHostingView(
                    rootView: SettingsView(settings: settings, initialTab: tab)
                )
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                    styleMask: [.titled],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                window.orderFront(nil)
                window.display()
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                hosting.layoutSubtreeIfNeeded()

                let bounds = hosting.bounds
                let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds)
                XCTAssertNotNil(rep)
                if let rep {
                    hosting.cacheDisplay(in: bounds, to: rep)
                    let png = rep.representation(using: .png, properties: [:])
                    XCTAssertNotNil(png)
                    let url = URL(fileURLWithPath: "/tmp/deai-settings-\(name).png")
                    try? png?.write(to: url)
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                }
                window.orderOut(nil)
                Self.liveWindows.append(window)
            }
        }
        if Thread.isMainThread {
            try work()
        } else {
            try DispatchQueue.main.sync(execute: work)
        }
    }
}

// MARK: - BUG-02: filtering must happen in AX space, not Cocoa space

extension TextGeometryTests {
    /// Element frame is in AX top-left coords. With the screen's maxY at
    /// 1117 pt, a window near the top has small AX y but large Cocoa y —
    /// filtering the converted rects against the AX frame dropped every
    /// underline (BUG-02).
    func testFilterInAXSpaceWhenWindowNearTop() {
        let elementFrameAX = CGRect(x: 300, y: 112, width: 600, height: 400)
        let glyphAX = CGRect(x: 310, y: 140, width: 50, height: 14)
        let rects = TextGeometry.positionRects(
            start: 0,
            end: 5,
            elementFrameAX: elementFrameAX,
            primaryMaxY: 1117,
            boundsForRange: { _ in glyphAX },
            lineForIndex: { _ in nil },
            rangeForLine: { _ in nil }
        )
        XCTAssertEqual(
            rects,
            [TextGeometry.axToCocoa(glyphAX, primaryMaxY: 1117)],
            "glyph inside the element frame must survive — only dropped if filtered in the wrong coordinate space"
        )
    }

    func testPositionRectsDropsOutOfFrame() {
        let elementFrameAX = CGRect(x: 300, y: 112, width: 600, height: 400)
        let farAway = CGRect(x: 10, y: 900, width: 50, height: 14)
        let rects = TextGeometry.positionRects(
            start: 0,
            end: 5,
            elementFrameAX: elementFrameAX,
            primaryMaxY: 1117,
            boundsForRange: { _ in farAway },
            lineForIndex: { _ in nil },
            rangeForLine: { _ in nil }
        )
        XCTAssertTrue(rects.isEmpty)
    }
}

// MARK: - BUG-08: viewport clipping

extension TextGeometryTests {
    /// Word reports glyph bounds for the whole page — lines scrolled out of
    /// the document viewport must be clipped, not drawn over chrome.
    func testClipRectsClipsToViewport() {
        let viewport = CGRect(x: 0, y: 100, width: 500, height: 300)
        let element = CGRect(x: 0, y: -500, width: 500, height: 1000)
        let inside = CGRect(x: 10, y: 150, width: 100, height: 14)
        let above = CGRect(x: 10, y: 50, width: 100, height: 14)   // over ribbon
        let below = CGRect(x: 10, y: 450, width: 100, height: 14)  // over status bar
        let partial = CGRect(x: 10, y: 90, width: 100, height: 20) // straddles top
        let out = TextGeometry.clipRects(
            [inside, above, below, partial],
            elementFrame: element,
            clip: viewport
        )
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0], inside)
        // partial rect clipped to the viewport's top edge
        XCTAssertEqual(out[1], CGRect(x: 10, y: 100, width: 100, height: 10))
    }

    func testClipRectsNoClipMeansElementFrameOnly() {
        let element = CGRect(x: 0, y: 0, width: 500, height: 400)
        let inside = CGRect(x: 10, y: 100, width: 100, height: 14)
        let outside = CGRect(x: 10, y: 900, width: 100, height: 14)
        let out = TextGeometry.clipRects(
            [inside, outside], elementFrame: element, clip: nil
        )
        XCTAssertEqual(out, [inside])
    }

    /// positionRects must clip in AX space before the Cocoa flip.
    func testPositionRectsClipsViewportInAXSpace() {
        // primaryMaxY 1117; element near top; viewport cuts off the top half
        let elementFrameAX = CGRect(x: 100, y: 40, width: 600, height: 400)
        let viewportAX = CGRect(x: 100, y: 140, width: 600, height: 300)
        let glyph = CGRect(x: 120, y: 60, width: 100, height: 14) // above viewport
        let rects = TextGeometry.positionRects(
            start: 0, end: 5,
            elementFrameAX: elementFrameAX,
            viewportAX: viewportAX,
            primaryMaxY: 1117,
            boundsForRange: { _ in glyph },
            lineForIndex: { _ in nil },
            rangeForLine: { _ in nil }
        )
        XCTAssertTrue(rects.isEmpty)
    }
}

// MARK: - BUG-04: shared-text base offset translation

extension TextGeometryTests {
    private func loc(_ r: CFRange?) -> [Int]? {
        r.map { [$0.location, $0.length] }
    }

    func testGlobalSpanTranslation() {
        // Word page 2: baseOffset 1144, visible range = the page's slice
        let visible = CFRange(location: 1144, length: 1144)
        // finding [10, 20) local → [1154, 1164) shared
        XCTAssertEqual(
            loc(TextGeometry.globalSpan(start: 10, end: 20, baseOffset: 1144, visible: visible)),
            [1154, 10]
        )
        // partially outside the page's visible slice → clipped
        XCTAssertEqual(
            loc(TextGeometry.globalSpan(start: 1140, end: 1160, baseOffset: 1144, visible: visible)),
            [2284, 4]
        )
        // fully outside → nil (finding on another page)
        XCTAssertNil(
            TextGeometry.globalSpan(start: 0, end: 5, baseOffset: 0, visible: visible)
        )
        // baseOffset 0 element: identity mapping
        XCTAssertEqual(
            loc(TextGeometry.globalSpan(
                start: 3, end: 8, baseOffset: 0,
                visible: CFRange(location: 0, length: 100)
            )),
            [3, 5]
        )
    }
}

// MARK: - caret-based card trigger

final class CaretCardTriggerTests: XCTestCase {
    private func pf(_ s: UInt32, _ e: UInt32) -> PositionedFinding {
        PositionedFinding(
            finding: Finding(
                category: .markdown, ruleId: "md.bold", message: "", start: s,
                end: e, suggestions: [], tier: 1
            ),
            rects: [CGRect(x: 0, y: 0, width: 50, height: 14)]
        )
    }

    func testClickInsideFindingOpens() {
        // caret jumped from 50 to inside [10, 20) → click → open
        let hit = CaretCardTrigger.finding(
            caret: 15, previousCaret: 50, positioned: [pf(10, 20)]
        )
        XCTAssertEqual(hit?.finding.start, 10)
    }

    func testArrowKeyStepDoesNotOpen() {
        // |Δ| = 1 → arrow key, not a click
        XCTAssertNil(
            CaretCardTrigger.finding(caret: 15, previousCaret: 14, positioned: [pf(10, 20)])
        )
        XCTAssertNil(
            CaretCardTrigger.finding(caret: 15, previousCaret: 16, positioned: [pf(10, 20)])
        )
    }

    func testFirstEventWithNoPreviousOpens() {
        XCTAssertEqual(
            CaretCardTrigger.finding(caret: 15, previousCaret: nil, positioned: [pf(10, 20)])?.finding.end,
            20
        )
    }

    func testCaretOutsideFindingDoesNotOpen() {
        XCTAssertNil(
            CaretCardTrigger.finding(caret: 30, previousCaret: 0, positioned: [pf(10, 20)])
        )
    }

    func testCaretAtBoundaryOpens() {
        // spec: start ≤ caret ≤ end
        XCTAssertNotNil(
            CaretCardTrigger.finding(caret: 20, previousCaret: 0, positioned: [pf(10, 20)])
        )
        XCTAssertNotNil(
            CaretCardTrigger.finding(caret: 10, previousCaret: 0, positioned: [pf(10, 20)])
        )
    }

    // MARK: BUG-06 — the controller-level gate (unchanged text must still
    // reach the caret trigger; the old inverted guard returned early)

    /// Regression: unchanged text + collapsed caret inside a finding after a
    /// >1-unit jump must open the card.
    func testCardFindingUnchangedTextOpens() {
        let hit = CaretCardTrigger.cardFinding(
            textUnchanged: true,
            selectedRange: CFRange(location: 15, length: 0),
            baseOffset: 0,
            previousCaret: 50,
            positioned: [pf(10, 20)]
        )
        XCTAssertEqual(hit?.finding.ruleId, "md.bold")
    }

    func testCardFindingChangedTextNeverOpens() {
        XCTAssertNil(
            CaretCardTrigger.cardFinding(
                textUnchanged: false,
                selectedRange: CFRange(location: 15, length: 0),
                baseOffset: 0,
                previousCaret: 50,
                positioned: [pf(10, 20)]
            )
        )
    }

    func testCardFindingNonCollapsedSelectionNeverOpens() {
        XCTAssertNil(
            CaretCardTrigger.cardFinding(
                textUnchanged: true,
                selectedRange: CFRange(location: 15, length: 4),
                baseOffset: 0,
                previousCaret: 50,
                positioned: [pf(10, 20)]
            )
        )
    }

    /// Word page element: AXSelectedTextRange is in shared-document offsets;
    /// findings are element-local — baseOffset must be subtracted.
    func testCardFindingSharedRangeConversion() {
        let hit = CaretCardTrigger.cardFinding(
            textUnchanged: true,
            selectedRange: CFRange(location: 1159, length: 0),
            baseOffset: 1144,
            previousCaret: nil,
            positioned: [pf(10, 20)]
        )
        XCTAssertEqual(hit?.finding.start, 10)
        // a global offset that lands outside the local finding → nil
        XCTAssertNil(
            CaretCardTrigger.cardFinding(
                textUnchanged: true,
                selectedRange: CFRange(location: 1170, length: 0),
                baseOffset: 1144,
                previousCaret: nil,
                positioned: [pf(10, 20)]
            )
        )
    }
}

// MARK: - debug command parsing

final class DebugCommandTests: XCTestCase {
    func testParse() {
        let cmd = DebugCommand(userInfo: [
            "action": "apply", "ruleId": "md.bold", "index": 1, "suggestion": 2,
        ])
        XCTAssertEqual(cmd?.action, .apply)
        XCTAssertEqual(cmd?.ruleId, "md.bold")
        XCTAssertEqual(cmd?.index, 1)
        XCTAssertEqual(cmd?.suggestion, 2)
    }

    func testDefaults() {
        let cmd = DebugCommand(userInfo: ["action": "showCard", "ruleId": "zh.dash"])
        XCTAssertEqual(cmd?.index, 0)
        XCTAssertEqual(cmd?.suggestion, 0)
    }

    func testRejectsUnknownAction() {
        XCTAssertNil(DebugCommand(userInfo: ["action": "bogus"]))
        XCTAssertNil(DebugCommand(userInfo: nil))
        XCTAssertNil(DebugCommand(userInfo: ["ruleId": "x"]))
    }
}

// MARK: - memory: check pipeline must not grow unboundedly

final class MemoryHarnessTests: XCTestCase {
    /// phys_footprint of the current process.
    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count
                )
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// 2,000 check cycles on gradually changing text through the same
    /// components CheckService drives — RSS growth must stay bounded.
    func testCheckCyclesDoNotLeak() {
        let checker = Checker()
        let runner = ParagraphGrammarRunner(checker: CoreGrammarChecker(checker: checker))
        let settings = AppSettings(
            userDefaults: UserDefaults(suiteName: "mem.\(UUID().uuidString)")!
        )
        let bundleId = "com.apple.TextEdit"
        let body = "这是一个用于测试的混合段落，包含顿号、举例。**加粗**、`代码` 都出现。"

        func cycle(_ i: Int) {
            // edited last paragraph each cycle → cache churn + 1 grammar miss
            let text = body + "\n" + body + "\nlast para \(i)"
            var opts = settings.checkOptions(for: bundleId)
            opts.grammar = false
            var findings = checker.check(text: text, opts: opts)
            findings += runner.checkAll(text: text).findings
            _ = FindingFilter.apply(findings, text: text, settings: settings, bundleId: bundleId)
        }

        // phase isolation: which component retains memory?
        var opts = settings.checkOptions(for: bundleId)
        opts.grammar = false
        let textA = body + "\n" + body
        for _ in 0..<100 { _ = checker.check(text: textA, opts: opts) }
        let b0 = footprint()
        for _ in 0..<2000 {
            _ = checker.check(text: textA + "\nx", opts: opts)
        }
        print("MEM-BISECT non-grammar only: \(Double(Int64(footprint()) - Int64(b0)) / 1_048_576) MiB")

        for i in 0..<100 { _ = runner.checkAll(text: "\(i)") }
        let b1 = footprint()
        for i in 0..<2000 { _ = runner.checkAll(text: "para \(i)") }
        print("MEM-BISECT grammar runner only: \(Double(Int64(footprint()) - Int64(b1)) / 1_048_576) MiB")

        for i in 0..<100 { cycle(i) } // warm-up: caches, lazy inits
        let before = footprint()
        for i in 100..<2100 { cycle(i) }
        let growth = Int64(footprint()) - Int64(before)
        let mib = Double(growth) / 1_048_576
        XCTAssertLessThan(
            mib, 64,
            "2,000 check cycles grew footprint by \(String(format: "%.1f", mib)) MiB"
        )
        print("MEM: 2,000 cycles, footprint growth \(String(format: "%.1f", mib)) MiB")
    }
}

final class SuggestionCardModelTests: XCTestCase {
    private func model() -> SuggestionCardModel {
        SuggestionCardModel(
            finding: Finding(category: .markdown, ruleId: "md.bold", message: "移除粗体标记",
                             start: 0, end: 8, suggestions: ["粗体"], tier: 1),
            matchedText: "**粗体**"
        )
    }

    func testRepeatedApplyCallsReplacementOnlyOnce() {
        let model = model()
        var calls = 0
        model.onApply = { _, _ in calls += 1 }
        model.apply("粗体")
        model.apply("粗体")
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.phase, .loading)
    }

    func testFailedReplacementDoesNotShowSuccess() {
        let model = model()
        model.onApply = { _, completion in completion(false) }
        model.apply("粗体")
        let checked = expectation(description: "verified failure")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            XCTAssertEqual(model.phase, .failure)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
    }

    func testPreviousCompletionCannotChangeNewFinding() {
        let model = model()
        var finish: ((Bool) -> Void)?
        model.onApply = { _, completion in finish = completion }
        model.apply("粗体")
        model.update(finding: model.finding, matchedText: "新的文字")
        finish?(true)
        let checked = expectation(description: "old result ignored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            XCTAssertEqual(model.phase, .idle)
            XCTAssertEqual(model.matchedText, "新的文字")
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
    }
}

final class SuggestionCardPanelTests: XCTestCase {
    func testSwitchingFindingReusesPanelAndFitsLongContent() {
        let card = SuggestionCardPanel()
        defer { card.dismiss() }
        func show(_ text: String) {
            card.show(
                finding: Finding(category: .markdown, ruleId: "md.bold", message: "Markdown 残留：加粗",
                                 start: 0, end: UInt32(text.utf16.count), suggestions: [text], tier: 1),
                matchedText: text, near: CGRect(x: 300, y: 600, width: 40, height: 20),
                onApply: { _, completion in completion(true) }, onRewrite: {},
                onIgnore: {}, onDisableRule: {}, onDismiss: {}
            )
        }
        show("粗体")
        let first = NSApp.windows.first { $0.contentView is NSHostingView<SuggestionCardView> }
        XCTAssertNotNil(first)
        let shortHeight = first?.frame.height ?? 0
        show(String(repeating: "长文本，", count: 400))
        let second = NSApp.windows.first { $0.contentView is NSHostingView<SuggestionCardView> }
        XCTAssertTrue(first === second)
        XCTAssertGreaterThan(second?.frame.height ?? 0, shortHeight)
        XCTAssertLessThan(second?.frame.height ?? 1000, 600)
        XCTAssertEqual(card.current?.matchedText.count, 1600)
    }
}

final class UnderlineAppearanceAwareTests: XCTestCase {
    private func luminance(_ color: NSColor) -> Double {
        let color = color.usingColorSpace(.sRGB)!
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }

    func testEveryCategoryMeetsContrastInBothAppearances() {
        let backgrounds: [(NSAppearance.Name, [NSColor])] = [
            (.aqua, [.white, NSColor(srgbRed: 236 / 255, green: 235 / 255, blue: 232 / 255, alpha: 1)]),
            (.darkAqua, [NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1),
                         NSColor(srgbRed: 43 / 255, green: 43 / 255, blue: 43 / 255, alpha: 1)])
        ]
        for (name, backgrounds) in backgrounds {
            for category in [Category.grammar, .aiToneZh, .aiToneEn, .markdown] {
                let foreground = luminance(DeAIDesign.underlineColor(for: category, appearance: NSAppearance(named: name)!))
                for background in backgrounds {
                    let background = luminance(background)
                    let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 3, "\(name): \(category)")
                }
            }
        }
    }

    func testAppearanceChangeRecolorsVisibleLayerWithoutChangingGeometry() {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        NSApp.appearance = NSAppearance(named: .aqua)
        let view = UnderlineView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.render([PositionedFinding(
            finding: Finding(category: .aiToneEn, ruleId: "test", message: "", start: 0, end: 1,
                             suggestions: [], tier: 1),
            rects: [CGRect(x: 10, y: 20, width: 100, height: 12)]
        )])
        let layer = view.layer!.sublayers!.first as! CAShapeLayer
        let path = layer.path
        let hits = view.hitRects().map(\.0)
        XCTAssertEqual(layer.strokeColor, DeAIDesign.underlineColor(for: .aiToneEn, appearance: NSAppearance(named: .aqua)).cgColor)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // appearance change rebuilds the layers — geometry is untouched,
        // the theme-aware stroke color is re-resolved
        let newLayer = view.layer!.sublayers!.first as! CAShapeLayer
        XCTAssertEqual(newLayer.strokeColor, DeAIDesign.underlineColor(for: .aiToneEn, appearance: NSAppearance(named: .darkAqua)).cgColor)
        XCTAssertEqual(newLayer.path, path)
        XCTAssertEqual(view.hitRects().map(\.0), hits)
        XCTAssertEqual(newLayer.lineWidth, 1.2)
    }
}

// MARK: - safety-tick drift predicate (scroll stale-rect catch)

final class RectsMovedTests: XCTestCase {
    private let r = CGRect(x: 10, y: 20, width: 30, height: 4)

    func testIdenticalRectsNotMoved() {
        XCTAssertFalse(AppController.rectsMoved([r], [r]))
    }

    func testSubPointDriftIgnored() {
        let shifted = r.offsetBy(dx: 0.7, dy: -0.7)
        XCTAssertFalse(AppController.rectsMoved([r], [shifted]))
    }

    func testMovedBeyondTolerance() {
        XCTAssertTrue(
            AppController.rectsMoved([r], [r.offsetBy(dx: 0, dy: 1.5)])
        )
        XCTAssertTrue(
            AppController.rectsMoved([r], [r.offsetBy(dx: -40, dy: 0)])
        )
    }

    func testCountMismatchIsMoved() {
        XCTAssertTrue(AppController.rectsMoved([r], []))
        XCTAssertTrue(AppController.rectsMoved([], [r]))
        XCTAssertTrue(AppController.rectsMoved([r, r], [r]))
    }

    func testSizeChangeIsMoved() {
        var grown = r
        grown.size.width += 2
        XCTAssertTrue(AppController.rectsMoved([r], [grown]))
    }

    func testBothEmptyNotMoved() {
        XCTAssertFalse(AppController.rectsMoved([], []))
    }
}

final class KeyActionTests: XCTestCase {
    /// SecureField onCommit fires on focus loss too — an empty draft must
    /// never reach the store (it used to delete the saved key).
    func testEmptyAndWhitespaceDraftsAreIgnored() {
        XCTAssertEqual(KeyAction(draft: ""), .ignore)
        XCTAssertEqual(KeyAction(draft: "   "), .ignore)
        XCTAssertEqual(KeyAction(draft: "\n\t "), .ignore)
    }

    func testNonEmptyDraftSavesTrimmed() {
        XCTAssertEqual(KeyAction(draft: "sk-abc"), .save("sk-abc"))
        XCTAssertEqual(KeyAction(draft: "  sk-abc \n"), .save("sk-abc"))
    }
}

final class SelectionSessionLogicTests: XCTestCase {
    private func f(_ s: UInt32, _ e: UInt32) -> Finding {
        Finding(
            category: .grammar, ruleId: "test", message: "",
            start: s, end: e, suggestions: [], tier: 1
        )
    }

    // MARK: scope filtering

    func testScopedKeepsOnlyFullyContainedFindings() {
        let all = [f(0, 3), f(5, 8), f(8, 12), f(20, 22), f(4, 10)]
        // scope [5, 12)
        let out = SelectionSessionLogic.scoped(all, scopeStart: 5, scopeEnd: 12)
        XCTAssertEqual(out.map(\.start), [5, 8])
        // partial overlap (4,10) starts before the scope — excluded
        XCTAssertFalse(out.contains { $0.start == 4 })
        // touching boundaries count as inside
        XCTAssertEqual(
            SelectionSessionLogic.scoped(
                all, scopeStart: 0, scopeEnd: 3
            ).map(\.start),
            [0]
        )
        // nothing inside
        XCTAssertTrue(
            SelectionSessionLogic.scoped(
                all, scopeStart: 13, scopeEnd: 19
            ).isEmpty
        )
    }

    // MARK: scope tracking across replacements

    func testAdjustedScopeEnd() {
        // grow: "go" → "goes" (+2)
        XCTAssertEqual(
            SelectionSessionLogic.adjustedScopeEnd(
                20, matchedLength: 2, replacementLength: 4
            ),
            22
        )
        // shrink: "utilize" → "use"
        XCTAssertEqual(
            SelectionSessionLogic.adjustedScopeEnd(
                20, matchedLength: 7, replacementLength: 3
            ),
            16
        )
        // deletion: matched 4, replacement 0
        XCTAssertEqual(
            SelectionSessionLogic.adjustedScopeEnd(
                20, matchedLength: 4, replacementLength: 0
            ),
            16
        )
        // same length → unchanged
        XCTAssertEqual(
            SelectionSessionLogic.adjustedScopeEnd(
                20, matchedLength: 3, replacementLength: 3
            ),
            20
        )
    }

    // MARK: next-index after removal

    func testNextIndexAfterRemoval() {
        // removed item 0 of 3 → next is the new item 0
        XCTAssertEqual(SelectionSessionLogic.nextIndex(current: 0, remaining: 2), 0)
        // removed middle of 3 → same index = the old next
        XCTAssertEqual(SelectionSessionLogic.nextIndex(current: 1, remaining: 2), 1)
        // removed last → clamp to the new last
        XCTAssertEqual(SelectionSessionLogic.nextIndex(current: 2, remaining: 2), 1)
        // nothing remains → session over
        XCTAssertNil(SelectionSessionLogic.nextIndex(current: 0, remaining: 0))
    }
}

final class ExplicitCheckFilterTests: XCTestCase {
    private func settings() -> AppSettings {
        AppSettings(userDefaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    private func f(_ s: UInt32, _ e: UInt32, rule: String = "r") -> Finding {
        Finding(
            category: .markdown, ruleId: rule, message: "",
            start: s, end: e, suggestions: [], tier: 1
        )
    }

    /// The app/group *enabled* flag is not part of FindingFilter — an
    /// explicit selection check on a group-disabled app still yields
    /// findings, while chips/disabled rules/session ignores still apply.
    func testDisabledGroupStillFiltersChipsNotEnabled() {
        let s = settings()
        let text = "**a** and **b**"
        // .notes group is enabled by default — findings pass
        XCTAssertFalse(
            FindingFilter.apply(
                [f(0, 4), f(9, 13)], text: text,
                settings: s, bundleId: "com.apple.TextEdit"
            ).isEmpty
        )
        // remove the markdown chip from the notes group → filtered out even
        // though nothing checks group.enabled here
        var notes = s.groupRules[.notes]!
        notes.checks.remove(.markdown)
        s.groupRules[.notes] = notes
        XCTAssertTrue(
            FindingFilter.apply(
                [f(0, 4)], text: text,
                settings: s, bundleId: "com.apple.TextEdit"
            ).isEmpty
        )
        // a group that is entirely disabled (browser) still yields findings
        // through the explicit path — enabled is gated by tracking, not here
        XCTAssertFalse(
            FindingFilter.apply(
                [f(0, 4)], text: text,
                settings: s, bundleId: "com.google.Chrome"
            ).isEmpty
        )
    }

    func testDisabledRuleAndSessionIgnoreApply() {
        let s = settings()
        s.disabledRuleIds.insert("r")
        XCTAssertTrue(
            FindingFilter.apply(
                [f(0, 4)], text: "**a**",
                settings: s, bundleId: "com.apple.TextEdit"
            ).isEmpty
        )
        // "**a**" is 5 UTF-16 units — cover all of it so matched == "**a**"
        let s2 = settings()
        s2.sessionIgnored.insert(
            AppSettings.IgnoreKey(ruleId: "r", text: "**a**")
        )
        XCTAssertTrue(
            FindingFilter.apply(
                [f(0, 5)], text: "**a**",
                settings: s2, bundleId: "com.apple.TextEdit"
            ).isEmpty
        )
    }
}
