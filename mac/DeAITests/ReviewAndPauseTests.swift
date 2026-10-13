import AppKit
import XCTest
@testable import DeAI

final class RewriteReviewTests: XCTestCase {
    private func assertRoundTrip(_ original: String, _ result: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let review = RewriteReview(original: original, result: result)
        XCTAssertEqual(Array(review.text(accepting: []).utf16), Array(original.utf16), file: file, line: line)
        XCTAssertEqual(Array(review.text(accepting: Set(review.edits.map(\.id))).utf16),
                       Array(result.utf16), file: file, line: line)
    }

    func testAllKeptAndAllAcceptedRoundTripExactly() {
        for (original, result) in [
            ("He go home. We was late!", "He goes home. We were late!"),
            ("说白了，这是一个例子。", "这是例子！"),
            ("a  b\r\nc\t", "a b\nc\t\t"),
            ("", "new 😀"), ("delete all", ""), ("unchanged", "unchanged"),
            ("same same word", "same word same"),
            ("👨‍👩‍👧‍👦 cafe\u{301}。🇨🇳", "👨‍👩‍👧‍👦 café！🇨🇳"),
            ("a😀b", "a👩🏽‍💻b"),
        ] { assertRoundTrip(original, result) }
    }

    func testMixedChoiceKeepsOnlySelectedChanges() throws {
        let review = RewriteReview(original: "He go home. We was late!",
                                   result: "He goes home. We were late!")
        let go = try XCTUnwrap(review.edits.first(where: { $0.original == "go" }))
        let was = try XCTUnwrap(review.edits.first(where: { $0.original == "was" }))
        XCTAssertEqual(review.text(accepting: [go.id]), "He goes home. We was late!")
        XCTAssertEqual(review.text(accepting: [was.id]), "He go home. We were late!")
    }

    func testPunctuationAndWhitespaceRemainSelectable() throws {
        let review = RewriteReview(original: "Hello, world.\r\n", result: "Hello! world?\n")
        let punctuation = try XCTUnwrap(review.edits.first(where: { $0.original == "," }))
        XCTAssertEqual(review.text(accepting: [punctuation.id]), "Hello! world.\r\n")
        assertRoundTrip("  A\tB  ", " A B ")
    }

    func testNormalizationChangesKeepTheirActualUTF16Encoding() {
        let original = "e\u{301}", result = "é"
        let review = RewriteReview(original: original, result: result)
        XCTAssertEqual(review.edits.count, 1)
        assertRoundTrip(original, result)
    }

    func testKeepOriginalActionUsesExactEncodingInsteadOfCanonicalEquality() {
        let model = RewritePanelModel()
        model.original = "e\u{301}"
        model.setResult("é")
        XCTAssertFalse(model.keepsOriginal)
        model.selectAllEdits(accepted: false)
        XCTAssertTrue(model.keepsOriginal)
    }

    func testLargeResultIsOneLosslessChoice() {
        let original = "短文", result = String(repeating: "😀。", count: 7000)
        let review = RewriteReview(original: original, result: result)
        XCTAssertTrue(review.isWholePassage)
        XCTAssertEqual(review.edits.count, 1)
        XCTAssertEqual(review.text(accepting: []), original)
        XCTAssertEqual(review.text(accepting: [0]), result)
    }

    func testManyRepeatedMixedUnicodeSequencesRoundTrip() {
        var seed: UInt64 = 29
        let tokens = ["a", "b", " ", "\t", "\n", "，", "中", "😀", "é", "e\u{301}"]
        func text() -> String {
            (0..<24).map { _ in
                seed = seed &* 6364136223846793005 &+ 1
                return tokens[Int(seed % UInt64(tokens.count))]
            }.joined()
        }
        for _ in 0..<150 { assertRoundTrip(text(), text()) }
    }

    func testModelPreviewAndSelectionResetWhenResultChanges() throws {
        let model = RewritePanelModel()
        model.original = "He go home. We was late!"
        model.setResult("He goes home. We were late!")
        let review = try XCTUnwrap(model.review)
        let first = try XCTUnwrap(review.edits.first(where: { $0.original == "go" }))
        model.selectEdit(first.id, accepted: false, reviewID: review.id)
        XCTAssertEqual(model.reviewedText, "He go home. We were late!")
        XCTAssertFalse(model.rememberPairs.contains(where: { $0.from == "go" }))
        model.selectAllEdits(accepted: false)
        XCTAssertEqual(model.reviewedText, model.original)
        XCTAssertTrue(model.rememberPairs.isEmpty)
        model.selectAllEdits(accepted: true)
        XCTAssertEqual(model.reviewedText, model.result)
        model.setResult("He went home. We were early!")
        let newSelection = model.acceptedEdits
        model.selectEdit(0, accepted: false, reviewID: review.id)
        XCTAssertEqual(model.acceptedEdits, newSelection) // Old UI binding is ignored.
        XCTAssertEqual(model.reviewedText, model.result)
    }

    func testOriginalOrRawResultMutationInvalidatesOldReview() {
        let model = RewritePanelModel()
        model.original = "old"
        model.setResult("new")
        model.original = "edited while reviewing"
        XCTAssertNil(model.reviewedText)
        XCTAssertNil(model.review)
        model.setResult("fresh")
        model.result = "a different response"
        XCTAssertNil(model.reviewedText)
        XCTAssertTrue(model.acceptedEdits.isEmpty)
    }

    func testChosenTextUsesFirstStageWriteVerification() throws {
        let model = RewritePanelModel()
        model.original = "He go home. We was late!"
        model.setResult("He goes home. We were late!")
        let review = try XCTUnwrap(model.review)
        let was = try XCTUnwrap(review.edits.first(where: { $0.original == "was" }))
        model.selectEdit(was.id, accepted: false, reviewID: review.id)
        let selected = try XCTUnwrap(model.reviewedText)
        let document = "前😀\n" + model.original + "\n后"
        let start = "前😀\n".utf16.count, end = start + model.original.utf16.count
        let after = TextReplacer.expectedText(document, start: start, end: end, replacement: selected)
        XCTAssertTrue(TextReplacer.pasteVerified(current: document, after: after,
                                                start: start, end: end, replacement: selected))
        XCTAssertTrue(after.contains("We was late!"))
        XCTAssertFalse(TextReplacer.pasteVerified(current: document, after: after + "external edit",
                                                 start: start, end: end, replacement: selected))
    }
}

final class AppPauseTests: XCTestCase {
    func testApplicationIsolationAndAutomaticExpiry() {
        var now = Date(timeIntervalSince1970: 1000)
        let pauses = AppPauseStore(now: { now }, automaticallyExpires: false)
        var changes: [Set<String>] = []
        pauses.onChange = { changes.append($0) }
        pauses.pause("word", for: 60)
        pauses.pause("notes", for: 120)
        XCTAssertFalse(pauses.permitsAutomaticCheck("word", enabled: true))
        XCTAssertTrue(pauses.permitsAutomaticCheck("textedit", enabled: true))
        now = now.addingTimeInterval(60)
        pauses.refreshExpirations()
        XCTAssertTrue(pauses.permitsAutomaticCheck("word", enabled: true))
        XCTAssertFalse(pauses.permitsAutomaticCheck("notes", enabled: true))
        XCTAssertEqual(changes.last, ["word"])
    }

    func testResumeDoesNotEnablePermanentlyDisabledApp() {
        let pauses = AppPauseStore(automaticallyExpires: false)
        pauses.pause("word")
        pauses.pause("notes")
        pauses.resume("word")
        XCTAssertNil(pauses.deadline(for: "word"))
        XCTAssertFalse(pauses.permitsAutomaticCheck("word", enabled: false))
        XCTAssertFalse(pauses.permitsAutomaticCheck("notes", enabled: true))
    }

    func testRepeatingPauseReplacesDeadlineAndRejectsInvalidDurations() {
        var now = Date(timeIntervalSince1970: 1000)
        let pauses = AppPauseStore(now: { now }, automaticallyExpires: false)
        pauses.pause("word", for: 60)
        now = now.addingTimeInterval(30)
        pauses.pause("word", for: 60)
        now = now.addingTimeInterval(30)
        pauses.refreshExpirations()
        XCTAssertEqual(pauses.deadline(for: "word"), Date(timeIntervalSince1970: 1090))
        pauses.pause("bad", for: .infinity)
        pauses.pause("bad", for: -1)
        XCTAssertNil(pauses.deadline(for: "bad"))
        XCTAssertTrue(AppPauseStore(automaticallyExpires: false).deadlines.isEmpty)
    }

    func testRealTimerRestoresAutomaticChecksOnce() {
        let pauses = AppPauseStore()
        let expired = expectation(description: "pause timer expired")
        var expiredCount = 0
        pauses.onChange = { changed in
            if changed == ["word"], pauses.deadline(for: "word") == nil {
                expiredCount += 1
                expired.fulfill()
            }
        }
        pauses.pause("word", for: 0.05)
        wait(for: [expired], timeout: 2)
        XCTAssertTrue(pauses.permitsAutomaticCheck("word", enabled: true))
        XCTAssertEqual(expiredCount, 1)
        pauses.onChange = { _ in } // Break the test's observer capture cycle.
    }
}
