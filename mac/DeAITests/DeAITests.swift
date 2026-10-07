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
        sensitivity: UInt8 = 2
    ) -> CheckOptions {
        CheckOptions(
            grammar: grammar,
            aiToneEn: aiToneEn,
            aiToneZh: aiToneZh,
            markdown: markdown,
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
        // normalized: replacement in place but tail differs
        XCTAssertTrue(
            TextReplacer.pasteVerified(
                current: current, after: "这是粗体\n尾",
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
        XCTAssertFalse(s.markdownEnabled(for: "md.obsidian"))
        XCTAssertTrue(s.markdownEnabled(for: "com.apple.TextEdit"))
    }

    func testAppRuleOverrides() {
        let (s, _) = fresh()
        s.setAppEnabled("com.google.Chrome", true)
        XCTAssertTrue(s.isAppEnabled("com.google.Chrome"))
        s.setAppEnabled("com.apple.TextEdit", false)
        XCTAssertFalse(s.isAppEnabled("com.apple.TextEdit"))
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
                onApply: { _, completion in completion(true) }, onIgnore: {}, onDisableRule: {}, onDismiss: {}
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
