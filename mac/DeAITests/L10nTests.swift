import XCTest
@testable import DeAI

final class L10nTests: XCTestCase {

    private func hasCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3000...0x303F).contains(scalar.value)  // CJK punctuation 。「」
                || (0xFF00...0xFFEF).contains(scalar.value)  // fullwidth forms
        }
    }

    /// Every key exists in both tables with non-empty text.
    func testAllKeysHaveBothLanguages() {
        for key in L10n.Key.allCases {
            let zh = L10n.zh[key]
            let en = L10n.en[key]
            XCTAssertNotNil(zh, "missing zh entry for \(key.rawValue)")
            XCTAssertNotNil(en, "missing en entry for \(key.rawValue)")
            XCTAssertFalse(zh?.isEmpty ?? true, "empty zh for \(key.rawValue)")
            XCTAssertFalse(en?.isEmpty ?? true, "empty en for \(key.rawValue)")
        }
    }

    /// No CJK characters (incl. CJK punctuation / fullwidth forms) may leak
    /// into English strings. `languageRow` is the one exemption: the picker
    /// label stays bilingual ("语言 / Language") so it's findable in either
    /// language.
    func testNoCJKInEnglishStrings() {
        for key in L10n.Key.allCases where key != .languageRow {
            guard let en = L10n.en[key] else { continue }
            XCTAssertFalse(hasCJK(en), "CJK in en[\(key.rawValue)]: \(en)")
        }
    }

    /// zh/en format strings must interpolate the same number of placeholders.
    func testFormatPlaceholderParity() {
        func count(_ s: String, _ marker: String) -> Int {
            s.components(separatedBy: marker).count - 1
        }
        for key in L10n.Key.allCases {
            guard let zh = L10n.zh[key], let en = L10n.en[key] else { continue }
            for marker in ["%@", "%d"] {
                XCTAssertEqual(
                    count(zh, marker), count(en, marker),
                    "\(key.rawValue): \(marker) count differs"
                )
            }
        }
    }

    /// English rule explanations exist for every non-Harper rule id the
    /// core can emit (fixture list mirrors the Rust rule sources).
    func testEnglishRuleMessageCoverage() {
        for id in L10n.coreRuleIds {
            // ASCII fixture data: personal.* interpolate the matched text /
            // suggestion verbatim, so CJK there would mask a zh fallback
            let finding = Finding(
                category: .aiToneZh, ruleId: id, message: "中文消息",
                start: 0, end: 1, suggestions: ["alt"], tier: 1
            )
            let en = L10n.findingMessage(finding, matched: "term", lang: .en)
            XCTAssertFalse(en.isEmpty, "no en message for \(id)")
            XCTAssertFalse(hasCJK(en), "CJK in en message for \(id): \(en)")
            XCTAssertNotEqual(en, "中文消息", "\(id) fell back to the zh message")
        }
    }

    /// Personal messages interpolate the matched text / suggestion.
    func testPersonalRuleMessagesEnglish() {
        let replace = Finding(
            category: .personal, ruleId: "personal.replace", message: "个人偏好",
            start: 0, end: 2, suggestions: ["help"], tier: 1
        )
        let en = L10n.findingMessage(replace, matched: "赋能", lang: .en)
        XCTAssertTrue(en.contains("help"), "suggestion missing: \(en)")
        XCTAssertTrue(en.contains("赋能"), "matched text missing: \(en)")

        let avoid = Finding(
            category: .personal, ruleId: "personal.avoid", message: "个人偏好",
            start: 0, end: 3, suggestions: [], tier: 1
        )
        let enAvoid = L10n.findingMessage(avoid, matched: "说白了", lang: .en)
        XCTAssertTrue(enAvoid.contains("说白了"), "matched text missing: \(enAvoid)")
    }

    /// Harper messages are already English — pass through verbatim in both
    /// languages. Unknown ids fall back to the core message.
    func testHarperAndUnknownPassthrough() {
        let harper = Finding(
            category: .grammar, ruleId: "harper.Agreement",
            message: "subject-verb agreement", start: 0, end: 2,
            suggestions: ["goes"], tier: 1
        )
        XCTAssertEqual(
            L10n.findingMessage(harper, matched: "go", lang: .en),
            "subject-verb agreement"
        )
        XCTAssertEqual(
            L10n.findingMessage(harper, matched: "go", lang: .zh),
            "subject-verb agreement"
        )

        let unknown = Finding(
            category: .grammar, ruleId: "x.unknown", message: "原始消息",
            start: 0, end: 1, suggestions: [], tier: 1
        )
        XCTAssertEqual(
            L10n.findingMessage(unknown, matched: "", lang: .en), "原始消息"
        )
        // zh mode always keeps the core message, even for known ids
        let zhRule = Finding(
            category: .aiToneZh, ruleId: "zh.dash", message: "破折号炫技",
            start: 0, end: 1, suggestions: [], tier: 1
        )
        XCTAssertEqual(
            L10n.findingMessage(zhRule, matched: "—", lang: .zh), "破折号炫技"
        )
    }

    /// Saved settings that predate the field (valid payload, no
    /// `uiLanguage` key) decode as Chinese.
    func testOldSettingsPayloadDecodesAsChinese() throws {
        let suite = "l10n.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        defer { ud.removePersistentDomain(forName: suite) }
        // a complete pre-language payload — every non-optional Stored key,
        // no `uiLanguage`
        let json: [String: Any] = [
            "schemaVersion": 1,
            "autoUnderline": true, "grammar": true,
            "aiToneZh": true, "aiToneEn": true, "markdown": true,
            "personal": true, "sensitivity": 2,
            "disabledRuleIds": [String](), "appRules": [String: Any](),
            "underline": [
                "styles": [String: Any](), "thickness": 1.2, "opacity": 1.0,
                "offset": 1.0, "dimLowConfidence": true, "highlightFill": false,
            ],
            "groupRules": [String: Any](),
        ]
        ud.set(try JSONSerialization.data(withJSONObject: json), forKey: AppSettings.defaultsKey)
        let s = AppSettings(
            userDefaults: ud,
            secrets: InMemorySecretStore(),
            lexicon: PersonalLexiconStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("l10n-\(UUID().uuidString)")
            )
        )
        XCTAssertEqual(s.uiLanguage, .zh)
    }

    /// A truly fresh install (no stored payload at all) follows the system
    /// language — the test just asserts the code path picks `systemDefault`.
    func testFreshInstallFollowsSystemLanguage() {
        let s = AppSettings(
            userDefaults: UserDefaults(suiteName: "l10n.\(UUID().uuidString)")!,
            secrets: InMemorySecretStore(),
            lexicon: PersonalLexiconStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("l10n-\(UUID().uuidString)")
            )
        )
        XCTAssertEqual(s.uiLanguage, UILanguage.systemDefault)
    }

    /// Representative live-switch: display strings resolve through the
    /// current language, so mutating `uiLanguage` changes what views render.
    func testLanguageSwitchChangesRenderedStrings() {
        let s = AppSettings(
            userDefaults: UserDefaults(suiteName: "l10n.\(UUID().uuidString)")!,
            secrets: InMemorySecretStore(),
            lexicon: PersonalLexiconStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("l10n-\(UUID().uuidString)")
            )
        )
        s.uiLanguage = .zh
        XCTAssertEqual(L10n.t(.tabCheck, s.uiLanguage), "检查")
        XCTAssertEqual(AppGroup.office.displayName(s.uiLanguage), "Office 与文档")
        s.uiLanguage = .en
        XCTAssertEqual(L10n.t(.tabCheck, s.uiLanguage), "Check")
        XCTAssertEqual(AppGroup.office.displayName(s.uiLanguage), "Office & documents")
    }

    /// LLMError renders per language (typed cases keep the message
    /// switchable after the error was created).
    func testLLMErrorIsLanguageSwitchable() {
        let err = LLMError.http(status: 401, kind: .unauthorized, server: "")
        XCTAssertEqual(err.deaiMessage(.zh), "API Key 无效或未授权")
        XCTAssertEqual(err.deaiMessage(.en), "Invalid or unauthorized API key")
        XCTAssertEqual(err.errorDescription, "API Key 无效或未授权")
    }
}
