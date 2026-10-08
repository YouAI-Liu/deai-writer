import Foundation
import XCTest
@testable import DeAI

// MARK: - PersonalLexiconStore

final class PersonalLexiconStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: PersonalLexiconStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deai-lexicon-test-\(UUID().uuidString)",
                                    isDirectory: true)
        store = PersonalLexiconStore(directory: tempDir)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAddEntryValidation() throws {
        XCTAssertThrowsError(try store.addEntry(
            kind: .keep, term: "  "
        ).get()) { XCTAssertEqual($0 as? LexiconError, .emptyTerm) }

        XCTAssertThrowsError(try store.addEntry(
            kind: .keep, term: String(repeating: "字", count: 101)
        ).get()) { XCTAssertEqual($0 as? LexiconError, .termTooLong) }

        _ = try store.addEntry(kind: .keep, term: "保留词").get()
        XCTAssertThrowsError(try store.addEntry(
            kind: .keep, term: "保留词"
        ).get()) { XCTAssertEqual($0 as? LexiconError, .duplicate) }
        // same term, different kind is allowed
        XCTAssertNoThrow(try store.addEntry(kind: .avoid, term: "保留词").get())
    }

    func testLimit() {
        for i in 0..<PersonalLexiconStore.maxEntries {
            _ = store.addEntry(kind: .keep, term: "t\(i)")
        }
        XCTAssertThrowsError(
            try store.addEntry(kind: .keep, term: "overflow").get()
        ) { XCTAssertEqual($0 as? LexiconError, .limitReached) }
        // addDraft is also capped
        XCTAssertNil(store.addDraft())
    }

    func testPersistenceRoundTrip() throws {
        _ = try store.addEntry(
            kind: .replace, term: "赋能", replacement: "帮助"
        ).get()
        _ = try store.addEntry(kind: .avoid, term: "说白了").get()
        _ = try store.addEntry(
            kind: .keep, term: "ACME", match: .wholeWord, note: "产品名"
        ).get()
        store.setStyle("我的风格")

        let reloaded = PersonalLexiconStore(directory: tempDir)
        XCTAssertEqual(reloaded.entries.count, 3)
        let replace = reloaded.entries.first { $0.kind == .replace }
        XCTAssertEqual(replace?.term, "赋能")
        XCTAssertEqual(replace?.replacement, "帮助")
        XCTAssertEqual(
            reloaded.entries.first { $0.kind == .keep }?.match, .wholeWord
        )
        XCTAssertEqual(reloaded.entries.first { $0.kind == .keep }?.note, "产品名")
        XCTAssertEqual(reloaded.style, "我的风格")
    }

    /// Regression: the directory watcher alone misses in-place (non-atomic)
    /// writes because they don't touch directory entries — the per-file
    /// DispatchSource must catch them.
    func testInPlaceWriteTriggersReload() throws {
        _ = try store.addEntry(kind: .avoid, term: "旧词").get()
        let url = tempDir.appendingPathComponent("lexicon.json")
        let replacement = """
        [{"id":"00000000-0000-0000-0000-000000000001","kind":"avoid","term":"新词","match":"exact"}]
        """
        let fh = try FileHandle(forWritingTo: url)
        try fh.truncate(atOffset: 0)
        try fh.write(contentsOf: Data(replacement.utf8))
        try fh.close()

        let deadline = Date().addingTimeInterval(2)
        while store.entries.first?.term != "新词", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(store.entries.map(\.term), ["新词"])
    }

    /// A file created after store init must start being watched (the dir
    /// event re-arms the file watcher); a later in-place write then reloads.
    func testFileCreatedAfterLaunchIsWatched() throws {
        // store init already ran with no files — write one atomically, let
        // the directory watcher arm the file source, then edit in place.
        let url = tempDir.appendingPathComponent("lexicon.json")
        try Data(
            """
            [{"id":"00000000-0000-0000-0000-000000000002","kind":"avoid","term":"先词","match":"exact"}]
            """.utf8
        ).write(to: url, options: .atomic)
        var deadline = Date().addingTimeInterval(2)
        while store.entries.first?.term != "先词", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(store.entries.first?.term, "先词")

        let fh = try FileHandle(forWritingTo: url)
        try fh.truncate(atOffset: 0)
        try fh.write(contentsOf: Data(
            """
            [{"id":"00000000-0000-0000-0000-000000000003","kind":"keep","term":"后词","match":"wholeWord"}]
            """.utf8
        ))
        try fh.close()
        deadline = Date().addingTimeInterval(2)
        while store.entries.first?.term != "后词", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(store.entries.first?.term, "后词")
        XCTAssertEqual(store.entries.first?.kind, .keep)
        XCTAssertEqual(store.entries.first?.match, .wholeWord)
    }

    func testCorruptLexiconIsRenamedNotOverwritten() throws {
        let url = tempDir.appendingPathComponent("lexicon.json")
        try Data("{bad json".utf8).write(to: url)
        let s = PersonalLexiconStore(directory: tempDir)
        XCTAssertEqual(s.entries, [])
        // the corrupt file was moved aside, not deleted
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        )
        XCTAssertTrue(
            contents.contains {
                $0.lastPathComponent.hasPrefix("lexicon.corrupt-")
            }
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        // and a later save writes a fresh lexicon.json
        _ = try s.addEntry(kind: .keep, term: "x").get()
        let s2 = PersonalLexiconStore(directory: tempDir)
        XCTAssertEqual(s2.entries.map(\.term), ["x"])
    }

    func testCorruptStyleIsRenamed() throws {
        let url = tempDir.appendingPathComponent("style.md")
        try Data([0xFF, 0xFE, 0x01]).write(to: url)
        let s = PersonalLexiconStore(directory: tempDir)
        XCTAssertEqual(s.style, RewritePrompt.defaultStyle)
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        )
        XCTAssertTrue(
            contents.contains {
                $0.lastPathComponent.hasPrefix("style.corrupt-")
            }
        )
    }

    func testDraftRowsAndValidityFilter() {
        // the 添加词条 button appends a blank draft — invalid until edited
        let draft = store.addDraft()
        XCTAssertNotNil(draft)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(
            store.validationError(for: store.entries[0]), "词条不能为空"
        )
        // invalid entries never cross the FFI boundary
        XCTAssertNil(store.entries[0].ffi)
        var e = store.entries[0]
        e.term = "赋能"
        // replace without a replacement is still incomplete
        XCTAssertNil(e.ffi)
        e.replacement = "帮助"
        XCTAssertNotNil(e.ffi)
        store.updateEntry(e)
        XCTAssertEqual(store.entries[0].term, "赋能")
    }
}

// MARK: - checkPersonal (FFI)

final class PersonalCheckTests: XCTestCase {
    private func slice(_ text: String, _ f: Finding) -> String {
        (text as NSString).substring(
            with: NSRange(
                location: Int(f.start), length: Int(f.end - f.start)
            )
        )
    }

    func testReplaceAndAvoidFindings() {
        let text = "说白了，赋能 ACME 保留词"
        let entries = [
            PersonalEntry(
                kind: .replace, term: "赋能",
                replacement: "帮助", matchKind: .exact
            ),
            PersonalEntry(
                kind: .avoid, term: "说白了",
                replacement: nil, matchKind: .exact
            ),
            PersonalEntry(
                kind: .keep, term: "保留词",
                replacement: nil, matchKind: .exact
            ),
        ]
        let findings = checkPersonal(text: text, entries: entries)
        XCTAssertEqual(findings.count, 2)
        XCTAssertTrue(findings.allSatisfy { $0.category == .personal })
        XCTAssertTrue(findings.allSatisfy { $0.tier == 1 })
        let avoid = findings.first { $0.ruleId == "personal.avoid" }
        XCTAssertEqual(avoid.map { slice(text, $0) }, "说白了")
        XCTAssertEqual(avoid?.suggestions, [])
        let replace = findings.first { $0.ruleId == "personal.replace" }
        XCTAssertEqual(replace.map { slice(text, $0) }, "赋能")
        XCTAssertEqual(replace?.suggestions, ["帮助"])
        // keep never produces a finding
        XCTAssertFalse(findings.contains { slice(text, $0) == "保留词" })
        // and the keep range covers exactly 保留词 (UTF-16 offsets)
        let keep = personalKeepRanges(text: text, entries: entries)
        XCTAssertEqual(keep.count, 1)
        XCTAssertEqual(keep.first?.start, 12)
        XCTAssertEqual(keep.first?.end, 15)
    }

    func testCaseInsensitiveAndWholeWord() {
        let text = "We delve into Tapestry and cat categories"
        let entries = [
            PersonalEntry(
                kind: .avoid, term: "delve",
                replacement: nil, matchKind: .caseInsensitive
            ),
            PersonalEntry(
                kind: .avoid, term: "tapestry",
                replacement: nil, matchKind: .caseInsensitive
            ),
            PersonalEntry(
                kind: .avoid, term: "cat",
                replacement: nil, matchKind: .wholeWord
            ),
        ]
        let findings = checkPersonal(text: text, entries: entries)
        let matched = findings.map { slice(text, $0) }
        XCTAssertTrue(matched.contains("delve"))
        XCTAssertTrue(matched.contains("Tapestry"))
        XCTAssertTrue(matched.contains("cat"))
        // wholeWord must not flag "categories"
        XCTAssertFalse(matched.contains { $0.hasPrefix("categor") })
    }

    /// CJK terms have no ASCII word boundaries — wholeWord behaves as exact.
    func testWholeWordCJKIsExact() {
        let text = "这个方案值得深入探讨"
        let entries = [
            PersonalEntry(
                kind: .avoid, term: "值得",
                replacement: nil, matchKind: .wholeWord
            ),
        ]
        XCTAssertEqual(checkPersonal(text: text, entries: entries).count, 1)
    }

    func testUTF16OffsetsAcrossEmoji() {
        // 😀 = 2 UTF-16 units; the term's offsets must be in UTF-16
        let text = "😀 赋能"
        let entries = [
            PersonalEntry(
                kind: .avoid, term: "赋能",
                replacement: nil, matchKind: .exact
            ),
        ]
        let findings = checkPersonal(text: text, entries: entries)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].start, 3)
        XCTAssertEqual(findings[0].end, 5)
        XCTAssertEqual(slice(text, findings[0]), "赋能")
    }

    func testOverlapLongerTermWins() {
        let text = "深度赋能中"
        let entries = [
            PersonalEntry(
                kind: .avoid, term: "赋能",
                replacement: nil, matchKind: .exact
            ),
            PersonalEntry(
                kind: .avoid, term: "深度赋能",
                replacement: nil, matchKind: .exact
            ),
        ]
        let findings = checkPersonal(text: text, entries: entries)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(slice(text, findings[0]), "深度赋能")
    }
}

// MARK: - KeepSuppression

final class KeepSuppressionTests: XCTestCase {
    private func mk(_ cat: DeAI.Category, _ s: UInt32, _ e: UInt32) -> Finding {
        Finding(category: cat, ruleId: "r", message: "", start: s, end: e,
                suggestions: [], tier: 1)
    }

    func testDropsOverlappingOtherCategories() {
        let keep = [PersonalRange(start: 10, end: 14)]
        let findings = [
            mk(.markdown, 10, 14),     // fully inside
            mk(.grammar, 12, 20),      // partial overlap
            mk(.aiToneZh, 0, 5),       // disjoint — survives
            mk(.personal, 10, 14),     // personal never suppressed
            mk(.grammar, 14, 16),      // touches the edge — survives
        ]
        let out = KeepSuppression.apply(findings, keepRanges: keep)
        XCTAssertEqual(out.count, 3)
        XCTAssertTrue(out.contains { $0.category == .aiToneZh })
        XCTAssertTrue(out.contains { $0.category == .personal })
        XCTAssertTrue(out.contains { $0.category == .grammar && $0.start == 14 })
    }

    func testEmptyRangesNoop() {
        let findings = [mk(.grammar, 0, 4)]
        XCTAssertEqual(KeepSuppression.apply(findings, keepRanges: []), findings)
    }
}

// MARK: - FindingFilter (personal)

final class PersonalFilterTests: XCTestCase {
    private func freshSettings() -> AppSettings {
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return AppSettings(
            userDefaults: ud,
            lexicon: PersonalLexiconStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "deai-lex-\(UUID().uuidString)", isDirectory: true
                    )
            )
        )
    }

    private func personalFinding() -> Finding {
        Finding(category: .personal, ruleId: "personal.replace",
                message: "", start: 0, end: 2, suggestions: ["x"], tier: 1)
    }

    func testPersonalToggle() {
        let s = freshSettings()
        let text = "赋能"
        let f = [personalFinding()]
        XCTAssertEqual(
            FindingFilter.apply(f, text: text, settings: s,
                                bundleId: "com.apple.TextEdit").count, 1
        )
        s.personal = false
        XCTAssertTrue(
            FindingFilter.apply(f, text: text, settings: s,
                                bundleId: "com.apple.TextEdit").isEmpty
        )
    }

    func testPersonalGroupChip() {
        let s = freshSettings()
        let f = [personalFinding()]
        var rule = s.groupRules[.notes]!
        rule.checks.remove(.personal)
        s.groupRules[.notes] = rule
        XCTAssertTrue(
            FindingFilter.apply(f, text: "赋能", settings: s,
                                bundleId: "com.apple.TextEdit").isEmpty
        )
        // other groups unaffected
        XCTAssertEqual(
            FindingFilter.apply(f, text: "赋能", settings: s,
                                bundleId: "com.microsoft.Word").count, 1
        )
    }

    func testCheckOptionsPersonal() {
        let s = freshSettings()
        // default on, including the code group
        XCTAssertTrue(s.checkOptions(for: "com.microsoft.VSCode").personal)
        s.personal = false
        XCTAssertFalse(s.checkOptions(for: "com.apple.TextEdit").personal)
    }
}

// MARK: - AppSettings migration

final class PersonalMigrationTests: XCTestCase {
    private func tempLexicon() -> PersonalLexiconStore {
        PersonalLexiconStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "deai-lex-\(UUID().uuidString)", isDirectory: true
                )
        )
    }

    /// A v0 payload (no schemaVersion, no personal key, group rules lacking
    /// the personal chip) must decode with personal on and the chip added
    /// to every saved group rule.
    func testV0PayloadMigrates() throws {
        let json = """
        {"autoUnderline":true,"grammar":true,"aiToneZh":true,"aiToneEn":true,
         "markdown":true,"sensitivity":2,"disabledRuleIds":[],"appRules":{},
         "underline":{"styles":{},"thickness":1.2,"opacity":1,"offset":1,
                      "dimLowConfidence":true,"highlightFill":false},
         "groupRules":{"office":{"enabled":true,"checks":["grammar"]}}}
        """
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        ud.set(Data(json.utf8), forKey: AppSettings.defaultsKey)
        let s = AppSettings(userDefaults: ud, lexicon: tempLexicon())
        XCTAssertTrue(s.personal)
        XCTAssertTrue(s.groupRules[.office]!.checks.contains(.personal))
        XCTAssertTrue(s.groupRules[.office]!.checks.contains(.grammar))
        // untouched groups keep their defaults (which include personal)
        XCTAssertTrue(s.groupRules[.code]!.checks.contains(.personal))
    }

    /// Once migrated (v1), turning the chip off must persist.
    func testPersonalChipOffPersists() {
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let s1 = AppSettings(userDefaults: ud, lexicon: tempLexicon())
        var rule = s1.groupRules[.office]!
        rule.checks.remove(.personal)
        s1.groupRules[.office] = rule
        let s2 = AppSettings(userDefaults: ud, lexicon: tempLexicon())
        XCTAssertFalse(s2.groupRules[.office]!.checks.contains(.personal))
        XCTAssertTrue(s2.groupRules[.notes]!.checks.contains(.personal))
    }

    func testPersonalTogglePersists() {
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let s1 = AppSettings(userDefaults: ud, lexicon: tempLexicon())
        s1.personal = false
        let s2 = AppSettings(userDefaults: ud, lexicon: tempLexicon())
        XCTAssertFalse(s2.personal)
    }
}

// MARK: - RewritePrompt lexicon/style

final class RewritePromptLexiconTests: XCTestCase {
    func testEmptyLexiconKeepsUserMessageIdentical() {
        let withNil = RewritePrompt.user(text: "正文", hints: [])
        let withEmpty = RewritePrompt.user(text: "正文", hints: [], lexicon: [])
        XCTAssertEqual(withNil, withEmpty)
        XCTAssertFalse(withEmpty.contains("个人词库"))
    }

    func testLexiconSectionOrderAndContent() {
        let entries = [
            LexiconEntry(kind: .keep, term: "ACME"),
            LexiconEntry(kind: .replace, term: "赋能", replacement: "帮助"),
            LexiconEntry(kind: .avoid, term: "说白了"),
        ]
        let p = RewritePrompt.user(
            text: "正文", hints: [
                RewriteHint(ruleId: "r", matched: "m", message: "msg"),
            ], lexicon: entries
        )
        XCTAssertTrue(p.contains("必须保留原样的词：「ACME」"))
        XCTAssertTrue(p.contains("必须这样替换：「赋能」→「帮助」"))
        XCTAssertTrue(p.contains("避免使用：「说白了」"))
        // order: lexicon, then local hints, then the original
        let li = p.range(of: "个人词库")!.lowerBound
        let hi = p.range(of: "本地规则")!.lowerBound
        let oi = p.range(of: "原文：")!.lowerBound
        XCTAssertTrue(li < hi && hi < oi)
        // invalid drafts never reach the prompt
        let drafts = [LexiconEntry(kind: .keep, term: "")]
        XCTAssertFalse(
            RewritePrompt.user(text: "x", hints: [], lexicon: drafts)
                .contains("个人词库")
        )
    }

    func testSystemPromptComposition() {
        let sys = RewritePrompt.system(style: "自定义风格")
        XCTAssertTrue(sys.hasPrefix(RewritePrompt.safetyBlock))
        XCTAssertTrue(sys.contains("写作风格与偏好（用户自定义）：\n自定义风格"))
        // default style keeps the old rule-4/6 semantics
        XCTAssertTrue(RewritePrompt.defaultStyle.contains("AI 腔"))
        // safety rules survived the split
        XCTAssertTrue(RewritePrompt.safetyBlock.contains("不增加、不删除任何事实"))
        XCTAssertTrue(RewritePrompt.safetyBlock.contains("输出格式"))
    }

    func testStyleTruncatedAtLimit() {
        let long = String(repeating: "字", count: 5000)
        let sys = RewritePrompt.system(style: long)
        XCTAssertTrue(
            sys.count <= RewritePrompt.safetyBlock.count + 4000 + 20
        )
    }
}

// MARK: - RewriteDiff

final class RewriteDiffTests: XCTestCase {
    func testChinesePair() {
        let pairs = RewriteDiff.wordPairs(
            original: "说白了，这一段开头太套话。",
            result: "这一段开头直接说重点。"
        )
        XCTAssertFalse(pairs.isEmpty)
        // CJK runs coalesce into whole-phrase pairs
        XCTAssertTrue(
            pairs.contains { $0.from.contains("说白了") && $0.to.contains("直接") }
                || pairs.contains { $0.from.contains("说白了") }
        )
    }

    func testEnglishPairs() {
        let pairs = RewriteDiff.wordPairs(
            original: "We delve into the pivotal tapestry.",
            result: "We look into the key pattern."
        )
        XCTAssertTrue(
            pairs.contains(RewriteDiff.Pair(from: "delve", to: "look"))
        )
        XCTAssertTrue(
            pairs.contains(
                RewriteDiff.Pair(from: "pivotal tapestry", to: "key pattern")
            ) || pairs.contains(RewriteDiff.Pair(from: "pivotal", to: "key"))
        )
    }

    func testIdenticalIsEmpty() {
        XCTAssertTrue(
            RewriteDiff.wordPairs(original: "same text", result: "same text")
                .isEmpty
        )
    }

    func testInsertionAndDeletion() {
        let ins = RewriteDiff.wordPairs(original: "ab", result: "ab cd")
        XCTAssertTrue(ins.contains { $0.from.isEmpty && $0.to == "cd" })
        let del = RewriteDiff.wordPairs(original: "ab cd", result: "ab")
        XCTAssertTrue(del.contains { $0.from == "cd" && $0.to.isEmpty })
    }

    func testLongPairsSkipped() {
        let long = String(repeating: "x", count: 25)
        let pairs = RewriteDiff.wordPairs(
            original: "a", result: "a \(long)"
        )
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: lexiconCandidate

    func testLexiconCandidateReplace() {
        let c = RewriteDiff.Pair(from: "赋能", to: "帮助").lexiconCandidate
        XCTAssertEqual(c?.kind, .replace)
        XCTAssertEqual(c?.term, "赋能")
        XCTAssertEqual(c?.replacement, "帮助")
    }

    func testLexiconCandidateDeletion() {
        // 说白了， → deleted: avoid entry, trailing comma trimmed
        let c = RewriteDiff.Pair(from: "说白了，", to: "").lexiconCandidate
        XCTAssertEqual(c?.kind, .avoid)
        XCTAssertEqual(c?.term, "说白了")
        XCTAssertNil(c?.replacement)
    }

    func testLexiconCandidateDeletionTrims() {
        XCTAssertEqual(RewriteDiff.trimmingEndPunctuation("hello."), "hello")
        XCTAssertEqual(RewriteDiff.trimmingEndPunctuation("词、。"), "词")
        XCTAssertEqual(RewriteDiff.trimmingEndPunctuation("a，。；"), "a")
        XCTAssertEqual(
            RewriteDiff.trimmingEndPunctuation("keep，internal，"), "keep，internal"
        )
        XCTAssertEqual(RewriteDiff.trimmingEndPunctuation("edge case!"), "edge case")
    }

    func testLexiconCandidateDeletionAllPunctuationIsNil() {
        XCTAssertNil(RewriteDiff.Pair(from: "，。", to: "").lexiconCandidate)
    }

    func testLexiconCandidateInsertionIsNil() {
        XCTAssertNil(RewriteDiff.Pair(from: "", to: "new").lexiconCandidate)
    }
}
