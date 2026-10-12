import AppKit
import XCTest
@testable import DeAI

final class WriteSafetyTests: XCTestCase {
    func testPartialPageSelectionMustNotBeSilentlyClamped() {
        XCTAssertNil(RewriteScope.compute(
            text: "page one", selection: CFRange(location: 4, length: 20),
            baseOffset: 0
        ))
    }

    func testChangedDocumentContainingReplacementIsNotAlreadyApplied() {
        XCTAssertEqual(TextReplacer.prePasteDecision(
            baseline: "He go home", text: "He goes elsewhere",
            start: 3, end: 5, matched: "go", replacement: "goes"
        ), .abort)
    }

    func testSameRuleAndOffsetsOnDifferentPagesKeepTheirTarget() {
        let finding = Finding(category: .grammar, ruleId: "same", message: "",
                              start: 3, end: 5, suggestions: ["goes"], tier: 1)
        let page1 = PositionedFinding(finding: finding, rects: [], targetKey: 101)
        let page2 = PositionedFinding(finding: finding, rects: [], targetKey: 102)
        XCTAssertFalse(page1.sameTargetAndFinding(as: page2))
        XCTAssertFalse(page2.belongs(to: 101))
        XCTAssertTrue(page2.belongs(to: 102))
    }

    func testPageGeometryClipsGlobalContentToThatPage() {
        let visible = TextGeometry.clippedRange(
            CFRange(location: 0, length: 100), to: CFRange(location: 50, length: 20)
        )
        XCTAssertEqual(visible.location, 50)
        XCTAssertEqual(visible.length, 20)
        XCTAssertNil(TextGeometry.globalSpan(start: 3, end: 5, baseOffset: 0, visible: visible))
        XCTAssertEqual(TextGeometry.globalSpan(start: 48, end: 55, baseOffset: 0,
                                               visible: visible)?.length, 5)
    }

    func testDocumentSnapshotAndSelectionAcrossPagesUseUTF16() throws {
        let text = try XCTUnwrap(TextDocument.assemble([
            .init(range: CFRange(location: 4, length: 4), text: "乙丙\n丁"),
            .init(range: CFRange(location: 0, length: 4), text: "甲😀a"),
        ], length: 8))
        XCTAssertEqual(text, "甲😀a乙丙\n丁")
        let scope = try XCTUnwrap(RewriteScope.compute(
            text: text, selection: CFRange(location: 1, length: 5), baseOffset: 0
        ))
        XCTAssertEqual(scope.start, 1)
        XCTAssertEqual(scope.end, 6)
        XCTAssertEqual(TextReplacer.expectedText(text, start: scope.start, end: scope.end,
                                                replacement: "改"), "甲改\n丁")
        // A paragraph broken by pagination is still one paragraph.
        XCTAssertEqual(RewriteScope.compute(text: text, selection: CFRange(location: 5, length: 0),
                                             baseOffset: 0)?.end, 6)
    }

    func testIncompleteOverlappingOrChangedPagesAreRejected() {
        let first = TextDocument.Slice(range: CFRange(location: 0, length: 3), text: "abc")
        XCTAssertNil(TextDocument.assemble([first], length: 6))
        XCTAssertNil(TextDocument.assemble([first, first], length: 6))
        XCTAssertNil(TextDocument.assemble([first,
            .init(range: CFRange(location: 4, length: 2), text: "ef")], length: 6))
        XCTAssertNil(TextDocument.assemble([first,
            .init(range: CFRange(location: 3, length: 3), text: "de")], length: 6))
    }

    /// Exercise the actual delayed paste/verification/restore transaction with
    /// an isolated pasteboard and controllable editor; never touch user text.
    private final class Editor {
        var text: String? = "He go home"
        var selected = CFRange(location: 0, length: 0)
        var current = true
        var commands = 0
        var commandSucceeds = true
        var onPrepare: (() -> Void)?
        var onCommand: (() -> Void)?
        let pb = NSPasteboard.withUniqueName()

        init() { pb.setString("original clipboard", forType: .string) }
        deinit { pb.releaseGlobally() }

        var access: TextReplacer.PasteboardAccess {
            .init(readText: { self.text }, selectedRange: { self.selected },
                  select: { self.selected = $0; return true },
                  isCurrent: { self.current },
                  prepareCommand: { deleting in
                      self.onPrepare?()
                      return {
                          self.commands += 1
                          guard self.commandSucceeds else { return false }
                          if let text = self.text {
                              self.text = TextReplacer.expectedText(
                                  text, start: self.selected.location,
                                  end: self.selected.location + self.selected.length,
                                  replacement: deleting ? "" : self.pb.string(forType: .string) ?? ""
                              )
                          }
                          self.onCommand?()
                          return true
                      }
                  }, pasteboard: pb)
        }
    }

    private func apply(_ editor: Editor, expected: Bool, file: StaticString = #filePath,
                       line: UInt = #line) {
        let done = expectation(description: "write completed")
        TextReplacer.applyViaPasteboard(
            access: editor.access, start: 3, end: 5, matched: "go", replacement: "goes",
            baseline: "He go home"
        ) { success in
            XCTAssertEqual(success, expected, file: file, line: line)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testSuccessfulPasteRestoresAllClipboardTypesAfterVerification() {
        let editor = Editor()
        editor.pb.addTypes([.html], owner: nil)
        editor.pb.setString("<b>original</b>", forType: .html)
        apply(editor, expected: true)
        XCTAssertEqual(editor.text, "He goes home")
        XCTAssertEqual(editor.commands, 1)
        XCTAssertEqual(editor.pb.string(forType: .string), "original clipboard")
        XCTAssertEqual(editor.pb.string(forType: .html), "<b>original</b>")
    }

    func testFocusSwitchDuringSettleDoesNotPasteOrChangeClipboard() {
        let editor = Editor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editor.current = false }
        apply(editor, expected: false)
        XCTAssertEqual(editor.commands, 0)
        XCTAssertEqual(editor.text, "He go home")
        XCTAssertEqual(editor.pb.string(forType: .string), "original clipboard")
    }

    func testSelectionMoveWhilePreparingMenuDoesNotPaste() {
        let editor = Editor()
        editor.onPrepare = { editor.selected = CFRange(location: 0, length: 0) }
        apply(editor, expected: false)
        XCTAssertEqual(editor.commands, 0)
        XCTAssertEqual(editor.text, "He go home")
    }

    func testContentEditDuringSettleDoesNotPaste() {
        let editor = Editor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editor.text = "He go elsewhere" }
        apply(editor, expected: false)
        XCTAssertEqual(editor.commands, 0)
        XCTAssertEqual(editor.text, "He go elsewhere")
    }

    func testUserCopyDuringVerificationSurvivesRestore() {
        let editor = Editor()
        editor.onCommand = {
            editor.pb.clearContents()
            editor.pb.setString("user copied something new", forType: .string)
        }
        apply(editor, expected: true)
        XCTAssertEqual(editor.pb.string(forType: .string), "user copied something new")
    }

    func testLateEarlierWriteIsNotPastedTwice() {
        let editor = Editor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editor.text = "He goes home" }
        apply(editor, expected: true)
        XCTAssertEqual(editor.commands, 0)
        XCTAssertEqual(editor.text, "He goes home")
    }

    func testFailedCommandRestoresClipboardAndNextAttemptCanSucceed() {
        let editor = Editor()
        editor.commandSucceeds = false
        apply(editor, expected: false)
        XCTAssertEqual(editor.commands, 1) // No key-event fallback after uncertain AXPress.
        XCTAssertEqual(editor.pb.string(forType: .string), "original clipboard")
        editor.commandSucceeds = true
        apply(editor, expected: true)
        XCTAssertEqual(editor.commands, 2)
        XCTAssertEqual(editor.text, "He goes home")
    }

    func testUnreadableWriteResultRestoresClipboardAndReportsFailure() {
        let editor = Editor()
        editor.onCommand = { editor.text = nil }
        apply(editor, expected: false)
        XCTAssertEqual(editor.pb.string(forType: .string), "original clipboard")
    }

    func testCrossPageReplacementVerifiesWholeDocumentAfterReflow() {
        let editor = Editor()
        let baseline = "page1😀--page2--page3"
        editor.text = baseline
        let done = expectation(description: "cross-page replacement verified")
        TextReplacer.applyViaPasteboard(
            access: editor.access, start: 5, end: 14, matched: "😀--page2",
            replacement: "跨页", baseline: baseline, useMenuCommands: true
        ) { ok in
            XCTAssertTrue(ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(editor.text, "page1跨页--page3")
        XCTAssertEqual(editor.commands, 1)
    }

    func testFocusChangeDuringCommandPreparationAbortsBeforeClipboardMutation() {
        let editor = Editor()
        editor.onPrepare = { editor.current = false }
        apply(editor, expected: false)
        XCTAssertEqual(editor.commands, 0)
        XCTAssertEqual(editor.pb.string(forType: .string), "original clipboard")
    }

    func testSameLengthUnrelatedEditAfterPasteDoesNotVerifyAsSuccess() {
        let editor = Editor()
        editor.onCommand = { editor.text = "He goes xxxx" }
        apply(editor, expected: false)
        XCTAssertEqual(editor.pb.string(forType: .string), "original clipboard")
    }

    func testDeletionMustPreserveEntireTail() {
        XCTAssertFalse(TextReplacer.pasteVerified(
            current: "ab XX tail", after: "ab  xxxx", start: 3, end: 5, replacement: ""
        ))
    }

    func testAXSuccessMustPreserveUnchangedContent() {
        XCTAssertEqual(TextReplacer.decide(
            setOK: true, current: "He go home", after: "He goes elsewhere",
            start: 3, end: 5, replacement: "goes"
        ), .failNoPaste)
    }
}
