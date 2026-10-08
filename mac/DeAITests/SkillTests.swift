import Foundation
import XCTest
@testable import DeAI

// MARK: - frontmatter parsing

final class SkillFrontmatterTests: XCTestCase {
    func testNormalFrontmatter() {
        let data = Data(
            """
            ---
            name: My Skill
            description: a long description on one line
            language: zh
            ---
            Body text here.
            """.utf8
        )
        let parsed = RewriteSkillStore.parse(data, fallbackName: "fallback")
        XCTAssertEqual(parsed.name, "My Skill")
        XCTAssertEqual(parsed.description, "a long description on one line")
        XCTAssertEqual(parsed.language, .zh)
        XCTAssertEqual(parsed.body, "Body text here.")
    }

    func testNoFrontmatter() {
        let data = Data("just a body".utf8)
        let parsed = RewriteSkillStore.parse(data, fallbackName: "stem")
        XCTAssertEqual(parsed.name, "stem")
        XCTAssertEqual(parsed.description, "")
        XCTAssertEqual(parsed.language, .any)
        XCTAssertEqual(parsed.body, "just a body")
    }

    func testCRLFFrontmatter() {
        let data = Data("---\r\nname: CRLF\r\nlanguage: en\r\n---\r\nbody\r\n".utf8)
        let parsed = RewriteSkillStore.parse(data, fallbackName: "x")
        XCTAssertEqual(parsed.name, "CRLF")
        XCTAssertEqual(parsed.language, .en)
        XCTAssertEqual(parsed.body, "body\n")
    }

    func testMissingKeysAndUnknownIgnored() {
        let data = Data(
            """
            ---
            description: only a description
            author: ignored
            ---
            body
            """.utf8
        )
        let parsed = RewriteSkillStore.parse(data, fallbackName: "file-stem")
        XCTAssertEqual(parsed.name, "file-stem")
        XCTAssertEqual(parsed.description, "only a description")
        XCTAssertEqual(parsed.language, .any)
        XCTAssertEqual(parsed.body, "body")
    }

    func testUnclosedFrontmatterIsBody() {
        let data = Data("---\nname: x\nno closing".utf8)
        let parsed = RewriteSkillStore.parse(data, fallbackName: "x")
        XCTAssertEqual(parsed.body, "---\nname: x\nno closing")
    }
}

// MARK: - language detection

final class RewriteLanguageDetectTests: XCTestCase {
    func testPureChinese() {
        XCTAssertEqual(
            RewriteLanguageDetect.language(of: "这是一段中文文本。"), .zh
        )
    }

    func testPureEnglish() {
        XCTAssertEqual(
            RewriteLanguageDetect.language(of: "This is an English sentence."),
            .en
        )
    }

    func testChineseDominant() {
        // 10 CJK vs 3 latin letters: cjk*3 (30) >= latin (3) → zh
        XCTAssertEqual(
            RewriteLanguageDetect.language(of: "我们需要完成这个task。"), .zh
        )
    }

    func testMostlyEnglishWithOneTerm() {
        let text = "We discussed the OKR process and it went well overall."
        XCTAssertEqual(
            RewriteLanguageDetect.language(of: text + "中文"), .en
        )
    }

    func testEmptyIsEnglish() {
        XCTAssertEqual(RewriteLanguageDetect.language(of: ""), .en)
    }
}

// MARK: - RewriteSkillStore

final class RewriteSkillStoreTests: XCTestCase {
    private var tempDir: URL!
    private var styleFile: URL!
    private var store: RewriteSkillStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "deai-skill-test-\(UUID().uuidString)", isDirectory: true
            )
        styleFile = tempDir.appendingPathComponent("style.md")
        store = RewriteSkillStore(
            directory: tempDir.appendingPathComponent(
                "skills", isDirectory: true
            ),
            legacyStyleFile: styleFile
        )
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeSkillFile(
        _ name: String,
        body: String = "body",
        language: String? = nil
    ) throws -> URL {
        var front = "---\nname: \(name)\n"
        if let language { front += "language: \(language)\n" }
        front += "---\n"
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).md")
        try Data((front + body).utf8).write(to: url)
        return url
    }

    func testBuiltinAlwaysPresent() {
        XCTAssertEqual(store.skills.first?.id, RewriteSkillStore.builtinId)
        XCTAssertTrue(store.skills.first?.isBuiltin ?? false)
        XCTAssertEqual(
            store.skills.first?.body, RewritePrompt.defaultStyle
        )
        XCTAssertEqual(store.skills.first?.language, .any)
    }

    func testDuplicateBuiltinNamesAreLocalizedAndUnique() {
        let builtin = RewriteSkillStore.builtin
        let zh = store.duplicate(builtin, language: .zh)
        let zh2 = store.duplicate(builtin, language: .zh)
        let en = store.duplicate(builtin, language: .en)
        let en2 = store.duplicate(builtin, language: .en)
        XCTAssertEqual(zh.name, "去 AI 味（默认）副本")
        XCTAssertEqual(zh2.name, "去 AI 味（默认）副本 2")
        XCTAssertEqual(en.name, "De-AI (default) copy")
        XCTAssertEqual(en2.name, "De-AI (default) copy 2")
        XCTAssertEqual(Set([zh.id, zh2.id, en.id, en2.id]).count, 4)
        for copy in [zh, zh2, en, en2] {
            XCTAssertFalse(copy.isBuiltin)
            XCTAssertEqual(copy.body, builtin.body)
            XCTAssertEqual(copy.language, builtin.language)
        }
        store.reload()
        for copy in [zh, zh2, en, en2] {
            XCTAssertEqual(store.skills.first { $0.id == copy.id }, copy)
        }
        XCTAssertEqual(store.skills.first, builtin)
    }

    func testDuplicateSkipsExistingNamesAndPreservesImportedName() {
        let original = RewriteSkill(
            id: "custom", name: "中文自定义技能", description: "说明",
            language: .zh, body: "原始内容", isBuiltin: false
        )
        _ = store.save(original)
        for suffix in ["", " 2"] {
            _ = store.save(RewriteSkill(
                id: "collision\(suffix)", name: original.name + " copy" + suffix,
                description: "", language: .any, body: "", isBuiltin: false
            ))
        }
        let copy = store.duplicate(original, language: .en)
        XCTAssertEqual(copy.name, "中文自定义技能 copy 3")
        XCTAssertEqual(copy.description, original.description)
        XCTAssertEqual(copy.body, original.body)
        XCTAssertEqual(copy.language, original.language)
        XCTAssertEqual(original.displayName(.en), original.name)
    }

    func testPickerEligibility() {
        store.skills = [
            RewriteSkillStore.builtin,
            RewriteSkill(
                id: "z", name: "z", description: "", language: .zh,
                body: "", isBuiltin: false
            ),
            RewriteSkill(
                id: "e", name: "e", description: "", language: .en,
                body: "", isBuiltin: false
            ),
            RewriteSkill(
                id: "a", name: "a", description: "", language: .any,
                body: "", isBuiltin: false
            ),
        ]
        XCTAssertEqual(
            Set(store.eligible(for: .zh).map(\.id)),
            [RewriteSkillStore.builtinId, "z", "a"]
        )
        XCTAssertEqual(
            Set(store.eligible(for: .en).map(\.id)),
            [RewriteSkillStore.builtinId, "e", "a"]
        )
    }

    func testDeletedSelectionFallsBackToBuiltin() throws {
        let url = try makeSkillFile("Gone Skill")
        guard case .success(let skill) = store.importSkill(from: url) else {
            return XCTFail("import failed")
        }
        XCTAssertEqual(
            store.resolved(id: skill.id, for: .zh).id, skill.id
        )
        store.delete(id: skill.id)
        XCTAssertEqual(
            store.resolved(id: skill.id, for: .zh).id,
            RewriteSkillStore.builtinId
        )
        // en picker can't use a zh-only skill
        store.skills.append(
            RewriteSkill(
                id: "zhonly", name: "z", description: "", language: .zh,
                body: "", isBuiltin: false
            )
        )
        XCTAssertEqual(
            store.resolved(id: "zhonly", for: .en).id,
            RewriteSkillStore.builtinId
        )
    }

    func testImportRejectsOverLimit() throws {
        let big = String(repeating: "字", count: 60_001)
        let url = try makeSkillFile("Big", body: big)
        guard case .failure(let error) = store.importSkill(from: url) else {
            return XCTFail("expected rejection")
        }
        XCTAssertEqual(
            error, .tooLarge(60_001, RewriteSkillStore.maxBodyLength)
        )
    }

    func testImportAccepts28kBody() throws {
        // realistic size (~28 KB like the user's real SKILL.md)
        let body = String(repeating: "中文改写规则内容。", count: 2800) // 25.2k
        let url = try makeSkillFile("Real Size", body: body)
        guard case .success(let skill) = store.importSkill(from: url) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(skill.body.count, body.count)
        XCTAssertEqual(skill.language, .any)
    }

    func testImportFolderFindsSkillMd() throws {
        let folder = tempDir.appendingPathComponent(
            "a-skill-dir", isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        try Data("---\nname: Folder Skill\nlanguage: en\n---\nfb\n".utf8)
            .write(to: folder.appendingPathComponent("SKILL.md"))
        guard case .success(let skill) = store.importSkill(from: folder)
        else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(skill.name, "Folder Skill")
        XCTAssertEqual(skill.language, .en)
    }

    func testUniqueIdGeneration() {
        XCTAssertEqual(store.uniqueId(for: "My Skill"), "my-skill")
        // collision → suffix
        let first = store.uniqueId(for: "same")
        XCTAssertEqual(first, "same")
        _ = store.save(
            RewriteSkill(
                id: first, name: "Same", description: "", language: .any,
                body: "b", isBuiltin: false
            )
        )
        XCTAssertEqual(store.uniqueId(for: "same"), "same-2")
        // non-ASCII falls back to "skill"
        XCTAssertEqual(store.uniqueId(for: "中文技能"), "skill")
    }

    func testSaveAndReloadRoundTrip() throws {
        let skill = RewriteSkill(
            id: "round-trip", name: "Round Trip",
            description: "d", language: .zh, body: "some body",
            isBuiltin: false
        )
        _ = store.save(skill)
        let reloaded = RewriteSkillStore(
            directory: store.directory, legacyStyleFile: styleFile
        )
        let found = reloaded.skills.first { $0.id == "round-trip" }
        XCTAssertEqual(found?.name, "Round Trip")
        XCTAssertEqual(found?.description, "d")
        XCTAssertEqual(found?.language, .zh)
        XCTAssertEqual(found?.body, "some body")
    }

    func testMigrationCustomStyle() throws {
        try Data("我的自定义风格".utf8).write(to: styleFile)
        let migrated = RewriteSkillStore(
            directory: tempDir.appendingPathComponent(
                "skills2", isDirectory: true
            ),
            legacyStyleFile: styleFile
        )
        XCTAssertEqual(migrated.migratedSkillId, "migrated-style")
        let skill = migrated.skills.first { $0.id == "migrated-style" }
        XCTAssertEqual(skill?.body, "我的自定义风格")
        XCTAssertEqual(skill?.language, .any)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: styleFile.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: styleFile.deletingPathExtension()
                    .appendingPathExtension("md.migrated").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: migrated.directory
                    .appendingPathComponent("migrated-style.md").path
            )
        )
    }

    func testMigrationDefaultStyleIgnored() throws {
        try Data(RewritePrompt.defaultStyle.utf8).write(to: styleFile)
        let migrated = RewriteSkillStore(
            directory: tempDir.appendingPathComponent(
                "skills3", isDirectory: true
            ),
            legacyStyleFile: styleFile
        )
        XCTAssertNil(migrated.migratedSkillId)
        XCTAssertEqual(migrated.skills.count, 1) // builtin only
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: styleFile.path)
        )
    }

    func testMigrationAbsentStyleDoesNothing() {
        XCTAssertNil(store.migratedSkillId)
        XCTAssertEqual(store.skills.count, 1)
    }

    func testEstimatedTokens() {
        // CJK counts 1/char; latin ~4 chars/token
        let cjk = RewriteSkillStore.estimatedTokens(
            String(repeating: "字", count: 100)
        )
        XCTAssertEqual(cjk, 100)
        let latin = RewriteSkillStore.estimatedTokens(
            String(repeating: "a", count: 400)
        )
        XCTAssertEqual(latin, 100)
    }
}

// MARK: - prompt composition + settings decode

final class SkillPromptAndSettingsTests: XCTestCase {
    func testBuiltinSkillIncludesFixedSafetyRules() {
        let safety = """
        你是一名中英文文字编辑，只做一件事：去掉文字里的"AI 腔"，让它读起来像作者本人写的。

        硬性规则：
        1. 不增加、不删除任何事实、数字、日期、人名、机构名、引文、链接、出处和限定语（如"可能""约""部分""一些"）。
        2. 保持原文语言：中文仍为中文，英文仍为英文，中英混排保持原样。
        3. 保留原文中的缩写、专有名词、术语、代码、公式和单位，不得改写、展开或翻译。
        4. 保持原文的段落数量和顺序，不合并、不拆分段落；不添加标题、列表、加粗等 Markdown 格式。原文中残留的 Markdown 符号（**、#、行首的 - 或 * 列表符、`、> 等）要去掉，保留其中的文字。
        5. 篇幅与原文相近，通常不超过原文的 110%。
        6. 如果原文没有需要修改的地方，原样输出原文。

        输出格式：只输出改写后的正文。不要解释，不要加引号或代码块，不要写"改写如下"之类的话。
        """
        XCTAssertEqual(RewritePrompt.safetyBlock, safety)
        let expected = safety
            + "\n\n写作风格与偏好（用户自定义）：\n"
            + RewritePrompt.defaultStyle
        XCTAssertEqual(
            RewritePrompt.system(skill: RewriteSkillStore.builtin),
            expected
        )
    }

    func testNonBuiltinGetsTrailingReminder() {
        let custom = RewriteSkill(
            id: "x", name: "x", description: "", language: .any,
            body: "custom rules", isBuiltin: false
        )
        let sys = RewritePrompt.system(skill: custom)
        XCTAssertTrue(sys.hasSuffix(RewritePrompt.nonBuiltinSkillReminder))
        // built-in prompt must NOT contain the reminder
        XCTAssertFalse(
            RewritePrompt.system(skill: RewriteSkillStore.builtin)
                .contains(RewritePrompt.nonBuiltinSkillReminder)
        )
        XCTAssertFalse(
            RewritePrompt.system(skill: RewriteSkillStore.builtin)
                .contains("改写指导")
        )
    }

    func testCustomSkillBodyUntruncated() {
        let body = String(repeating: "中文。", count: 20_000) // 60k chars? no: 3*20000 = 60k
        let skill = RewriteSkill(
            id: "x", name: "x", description: "", language: .any,
            body: body, isBuiltin: false
        )
        let sys = RewritePrompt.system(skill: skill)
        XCTAssertTrue(sys.hasPrefix(RewritePrompt.safetyBlock))
        XCTAssertTrue(sys.contains(body))  // body untruncated
        XCTAssertTrue(
            sys.hasSuffix(RewritePrompt.nonBuiltinSkillReminder)
        )
    }

    func testOldSettingsDecodeWithoutSkillKeys() throws {
        // payload like an existing user's deai.settings.v1 — no
        // rewriteSkillZh/En keys at all
        let json = """
        {"schemaVersion":1,"autoUnderline":true,"grammar":true,
         "aiToneZh":true,"aiToneEn":true,"markdown":true,"personal":true,
         "sensitivity":2,"disabledRuleIds":[],"appRules":{},
         "underline":{"categories":{},"opacity":1},"groupRules":{},
         "uiLanguage":"zh"}
        """
        let suite = "deai.skill-decode-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data(json.utf8), forKey: AppSettings.defaultsKey)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("deai-skill-decode-\(UUID().uuidString)")
        let settings = AppSettings(
            userDefaults: defaults,
            secrets: InMemorySecretStore(),
            lexicon: PersonalLexiconStore(directory: temp)
        )
        XCTAssertEqual(
            settings.rewriteSkillZh, RewriteSkillStore.builtinId
        )
        XCTAssertEqual(
            settings.rewriteSkillEn, RewriteSkillStore.builtinId
        )
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: temp)
    }

    func testSkillSelectionsPersist() {
        let suite = "deai.skill-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("deai-skill-persist-\(UUID().uuidString)")
        let settings = AppSettings(
            userDefaults: defaults,
            secrets: InMemorySecretStore(),
            lexicon: PersonalLexiconStore(directory: temp)
        )
        settings.rewriteSkillZh = "some-skill"
        let reloaded = AppSettings(
            userDefaults: defaults,
            secrets: InMemorySecretStore(),
            lexicon: PersonalLexiconStore(directory: temp)
        )
        XCTAssertEqual(reloaded.rewriteSkillZh, "some-skill")
        XCTAssertEqual(
            reloaded.rewriteSkillEn, RewriteSkillStore.builtinId
        )
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: temp)
    }

    func testMigratedStyleUpdatesUnsetSelections() throws {
        let suite = "deai.skill-mig-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("deai-skill-mig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temp, withIntermediateDirectories: true
        )
        try Data("自定义风格内容".utf8)
            .write(to: temp.appendingPathComponent("style.md"))
        let settings = AppSettings(
            userDefaults: defaults,
            secrets: InMemorySecretStore(),
            lexicon: PersonalLexiconStore(directory: temp)
        )
        XCTAssertEqual(settings.rewriteSkillZh, "migrated-style")
        XCTAssertEqual(settings.rewriteSkillEn, "migrated-style")
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: temp)
    }
}
