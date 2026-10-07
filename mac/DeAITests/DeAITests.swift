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
