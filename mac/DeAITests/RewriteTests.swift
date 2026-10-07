import AppKit
import Carbon
import Foundation
import XCTest
@testable import DeAI

// MARK: - LLMClient.makeRequest

final class LLMRequestTests: XCTestCase {
    private func cfg(
        format: APIFormat,
        base: String = "https://api.example.com/v1",
        model: String = "m1"
    ) -> ProviderConfig {
        ProviderConfig(
            id: UUID(), name: "t", preset: .custom,
            format: format, baseURL: base, model: model
        )
    }

    private func body(_ req: URLRequest) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: req.httpBody!)
        return obj as! [String: Any]
    }

    func testChatRequest() throws {
        let c = cfg(format: .openAIChat, base: "https://api.x.com/v1/")
        let req = try LLMClient.makeRequest(
            config: c, apiKey: "k1", system: "sys", user: "usr",
            sessionId: "sess-1"
        )
        XCTAssertEqual(
            req.url?.absoluteString,
            "https://api.x.com/v1/chat/completions" // trailing / trimmed
        )
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Authorization"), "Bearer k1"
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "x-opencode-session"), "sess-1"
        )
        XCTAssertTrue(
            req.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("DeAI/")
                ?? false
        )
        let b = try body(req)
        XCTAssertEqual(b["model"] as? String, "m1")
        XCTAssertEqual(b["stream"] as? Bool, false)
        XCTAssertNil(b["temperature"]) // reasoning models reject it
        let msgs = b["messages"] as? [[String: Any]]
        XCTAssertEqual(msgs?[0]["role"] as? String, "system")
        XCTAssertEqual(msgs?[0]["content"] as? String, "sys")
        XCTAssertEqual(msgs?[1]["role"] as? String, "user")
        XCTAssertEqual(msgs?[1]["content"] as? String, "usr")
    }

    func testResponsesRequest() throws {
        let req = try LLMClient.makeRequest(
            config: cfg(format: .openAIResponses),
            apiKey: nil, system: "sys", user: "usr", sessionId: "s"
        )
        XCTAssertEqual(
            req.url?.absoluteString, "https://api.example.com/v1/responses"
        )
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(req.value(forHTTPHeaderField: "x-api-key"))
        let b = try body(req)
        XCTAssertEqual(b["instructions"] as? String, "sys")
        XCTAssertEqual(b["input"] as? String, "usr")
        XCTAssertNil(b["temperature"])
        XCTAssertNil(b["messages"])
    }

    func testAnthropicRequest() throws {
        let req = try LLMClient.makeRequest(
            config: cfg(format: .anthropicMessages),
            apiKey: "sk-ant", system: "sys", user: "usr", sessionId: "s"
        )
        XCTAssertEqual(
            req.url?.absoluteString, "https://api.example.com/v1/messages"
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "x-api-key"), "sk-ant"
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-ant"
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01"
        )
        let b = try body(req)
        XCTAssertEqual(b["system"] as? String, "sys")
        XCTAssertEqual(b["max_tokens"] as? Int, 4096)
        XCTAssertNil(b["temperature"])
        let msgs = b["messages"] as? [[String: Any]]
        XCTAssertEqual(msgs?.count, 1)
        XCTAssertEqual(msgs?[0]["content"] as? String, "usr")
    }

    func testNoAuthHeaderWhenKeyEmpty() throws {
        for format in APIFormat.allCases {
            let req = try LLMClient.makeRequest(
                config: cfg(format: format),
                apiKey: "", system: "s", user: "u", sessionId: "x"
            )
            XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(req.value(forHTTPHeaderField: "x-api-key"))
        }
    }
}

// MARK: - LLMClient.parseResponse

final class LLMResponseTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testChatSuccess() throws {
        let json = """
            {"choices":[{"message":{"role":"assistant","content":"改写后的文字"}}]}
            """
        XCTAssertEqual(
            try LLMClient.parseResponse(
                format: .openAIChat, data: data(json), statusCode: 200
            ),
            "改写后的文字"
        )
    }

    func testResponsesSuccessMultipleParts() throws {
        let json = """
            {"output":[
              {"type":"reasoning","summary":[]},
              {"type":"message","content":[
                {"type":"output_text","text":"第一段"},
                {"type":"output_text","text":"第二段"}
              ]}
            ]}
            """
        XCTAssertEqual(
            try LLMClient.parseResponse(
                format: .openAIResponses, data: data(json), statusCode: 200
            ),
            "第一段第二段"
        )
    }

    func testResponsesTopLevelFallback() throws {
        let json = """
            {"output_text":"hello"}
            """
        XCTAssertEqual(
            try LLMClient.parseResponse(
                format: .openAIResponses, data: data(json), statusCode: 200
            ),
            "hello"
        )
    }

    func testAnthropicSuccess() throws {
        let json = """
            {"content":[{"type":"text","text":"你好"},{"type":"text","text":"世界"}]}
            """
        XCTAssertEqual(
            try LLMClient.parseResponse(
                format: .anthropicMessages, data: data(json), statusCode: 200
            ),
            "你好世界"
        )
    }

    /// Real 401 body from OpenCode Go — the mapped prefix + server message.
    func testOpenCode401() throws {
        let json = """
            {"type":"error","error":{"type":"AuthError","message":"Missing API key."}}
            """
        do {
            _ = try LLMClient.parseResponse(
                format: .openAIChat, data: data(json), statusCode: 401
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("API Key 无效或未授权")
            )
            XCTAssertTrue(
                error.localizedDescription.contains("Missing API key.")
            )
        }
    }

    func testStringErrorBody() throws {
        let json = """
            {"error":"rate limited"}
            """
        XCTAssertThrowsError(
            try LLMClient.parseResponse(
                format: .openAIChat, data: data(json), statusCode: 429
            )
        ) { err in
            XCTAssertTrue(
                err.localizedDescription.contains("请求过于频繁或额度已用完")
            )
            XCTAssertTrue(err.localizedDescription.contains("rate limited"))
        }
    }

    func testNonJsonErrorTruncated() throws {
        let raw = String(repeating: "x", count: 500)
        XCTAssertThrowsError(
            try LLMClient.parseResponse(
                format: .openAIChat, data: data(raw), statusCode: 500
            )
        ) { err in
            XCTAssertEqual(err.localizedDescription.count, 200)
        }
    }
}

// MARK: - LLMClient.cleanOutput

final class CleanOutputTests: XCTestCase {
    func testThinkBlock() {
        XCTAssertEqual(
            LLMClient.cleanOutput("<think>推理过程…</think>正文"),
            "正文"
        )
    }

    func testFences() {
        XCTAssertEqual(
            LLMClient.cleanOutput("```\nhello\n```"),
            "hello"
        )
        XCTAssertEqual(
            LLMClient.cleanOutput("```markdown\nhello\n```"),
            "hello"
        )
    }

    func testEchoedMarkers() {
        XCTAssertEqual(
            LLMClient.cleanOutput("<<<\n正文\n>>>"),
            "正文"
        )
    }

    func testPlainUntouched() {
        XCTAssertEqual(LLMClient.cleanOutput("  正文  "), "正文")
        XCTAssertEqual(
            LLMClient.cleanOutput("a\nb\nc"), "a\nb\nc"
        )
    }
}

// MARK: - RewriteScope

final class RewriteScopeTests: XCTestCase {
    private let para1 = "第一段文字"
    private let para2 = "第二段文字"

    func testCaretMidParagraphLF() {
        let text = para1 + "\n" + para2 + "\n第三段"
        // caret inside para2 → whole para2
        let scope = RewriteScope.compute(
            text: text, selection: CFRange(location: 7, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(scope?.start, 6)
        XCTAssertEqual(scope?.end, 11)
    }

    func testCaretParagraphCR() {
        let text = "one\rtwo\rthree"
        let scope = RewriteScope.compute(
            text: text, selection: CFRange(location: 5, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(scope?.start, 4)
        XCTAssertEqual(scope?.end, 7)
    }

    func testCaretParagraphU2029() {
        let text = "one\u{2029}two"
        let scope = RewriteScope.compute(
            text: text, selection: CFRange(location: 1, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(scope?.start, 0)
        XCTAssertEqual(scope?.end, 3)
    }

    func testCaretAtParagraphStartAndEnd() {
        let text = "abc\ndef"
        // caret at start of "def"
        var s = RewriteScope.compute(
            text: text, selection: CFRange(location: 4, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(s?.start, 4)
        XCTAssertEqual(s?.end, 7)
        // caret at end of "abc" (before the LF)
        s = RewriteScope.compute(
            text: text, selection: CFRange(location: 3, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(s?.start, 0)
        XCTAssertEqual(s?.end, 3)
        // caret at very end
        s = RewriteScope.compute(
            text: text, selection: CFRange(location: 7, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(s?.start, 4)
        XCTAssertEqual(s?.end, 7)
    }

    func testSelectionClamping() {
        let text = "abcde"
        let s = RewriteScope.compute(
            text: text, selection: CFRange(location: 2, length: 100),
            baseOffset: 0
        )
        XCTAssertEqual(s?.start, 2)
        XCTAssertEqual(s?.end, 5)
    }

    /// Word: selection in shared offsets, element text is a page slice.
    func testBaseOffsetTranslation() {
        let text = "页面三内容" // 5 chars, page base = 100
        let s = RewriteScope.compute(
            text: text, selection: CFRange(location: 101, length: 0),
            baseOffset: 100
        )
        XCTAssertEqual(s?.start, 0)
        XCTAssertEqual(s?.end, 5)
    }

    func testWhitespaceOnlyNil() {
        XCTAssertNil(
            RewriteScope.compute(
                text: "  \n  ",
                selection: CFRange(location: 1, length: 0), baseOffset: 0
            )
        )
        XCTAssertNil(
            RewriteScope.compute(
                text: "", selection: nil, baseOffset: 0
            )
        )
    }

    /// Emoji are surrogate pairs — offsets must stay on UTF-16 boundaries.
    func testEmojiBoundary() {
        let text = "a😀b\nc"
        // utf16: a(1) 😀(2) b(1) \n(1) c(1) → len 6
        let s = RewriteScope.compute(
            text: text, selection: CFRange(location: 2, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(s?.start, 0)
        XCTAssertEqual(s?.end, 4) // "a😀b" is 4 UTF-16 units
        // caret after the newline → "c"
        let s2 = RewriteScope.compute(
            text: text, selection: CFRange(location: 6, length: 0),
            baseOffset: 0
        )
        XCTAssertEqual(s2?.start, 5)
        XCTAssertEqual(s2?.end, 6)
    }

    func testNormalizeNewlines() {
        // TextEdit uses CR
        XCTAssertEqual(
            RewriteScope.normalizeNewlines(
                "a\nb", likeOriginal: "x\ry"
            ),
            "a\rb"
        )
        // Word keeps LF
        XCTAssertEqual(
            RewriteScope.normalizeNewlines(
                "a\nb", likeOriginal: "x\ny"
            ),
            "a\nb"
        )
        // U+2029 hosts
        XCTAssertEqual(
            RewriteScope.normalizeNewlines(
                "a\nb", likeOriginal: "x\u{2029}y"
            ),
            "a\u{2029}b"
        )
        // CRLF original → output left alone
        XCTAssertEqual(
            RewriteScope.normalizeNewlines(
                "a\nb", likeOriginal: "x\r\ny"
            ),
            "a\nb"
        )
    }
}

// MARK: - RewritePrompt

final class RewritePromptTests: XCTestCase {
    func testUserPromptWithoutHints() {
        let p = RewritePrompt.user(text: "正文", hints: [])
        XCTAssertTrue(p.contains("原文：\n<<<\n正文\n>>>"))
        XCTAssertFalse(p.contains("本地规则"))
    }

    func testUserPromptWithHints() {
        let p = RewritePrompt.user(
            text: "正文",
            hints: [
                RewriteHint(ruleId: "zh.banned_opener",
                            matched: "说白了，", message: "空洞开场")
            ]
        )
        XCTAssertTrue(p.contains("[zh.banned_opener]"))
        XCTAssertTrue(p.contains("说白了，"))
        XCTAssertTrue(p.contains("空洞开场"))
        XCTAssertTrue(p.hasSuffix(">>>"))
    }
}

// MARK: - Provider config

final class ProviderConfigTests: XCTestCase {
    func testOpencodeGoDefaults() {
        let p = ProviderConfig(preset: .opencodeGo)
        XCTAssertEqual(p.name, "OpenCode Go")
        XCTAssertEqual(p.baseURL, "https://opencode.ai/zen/go/v1")
        XCTAssertEqual(p.model, "deepseek-v4-flash")
        XCTAssertEqual(p.format, .openAIChat)
    }

    func testModelFormatTable() {
        XCTAssertEqual(
            OpenCodeGoModels.format(for: "deepseek-v4-pro"), .openAIChat
        )
        XCTAssertEqual(
            OpenCodeGoModels.format(for: "qwen3.8-max"), .anthropicMessages
        )
        XCTAssertEqual(
            OpenCodeGoModels.format(for: "gpt-6-luna"), .openAIResponses
        )
        XCTAssertNil(OpenCodeGoModels.format(for: "some-custom-model"))
        // syncFormatWithModel follows the table
        var p = ProviderConfig(preset: .opencodeGo)
        p.model = "minimax-m3"
        p.syncFormatWithModel()
        XCTAssertEqual(p.format, .anthropicMessages)
        // unknown model: format unchanged
        p.model = "weird"
        p.format = .openAIResponses
        p.syncFormatWithModel()
        XCTAssertEqual(p.format, .openAIResponses)
    }

    func testPresetDefaults() {
        XCTAssertEqual(
            ProviderConfig(preset: .ollama).baseURL,
            "http://localhost:11434/v1"
        )
        XCTAssertFalse(ProviderPreset.ollama.requiresKey)
        XCTAssertFalse(ProviderPreset.lmStudio.requiresKey)
        XCTAssertTrue(ProviderPreset.openAI.requiresKey)
        XCTAssertEqual(
            ProviderConfig(preset: .anthropic).format, .anthropicMessages
        )
    }
}

// MARK: - AppSettings provider migration

final class SettingsMigrationTests: XCTestCase {
    /// A pre-rewrite settings payload (no provider keys) must still decode
    /// with all old values intact and get the default OpenCode Go provider.
    func testOldSettingsBlobMigrates() {
        let oldJSON = """
            {"autoUnderline":false,"grammar":false,"aiToneZh":true,
             "aiToneEn":false,"markdown":true,"sensitivity":3,
             "disabledRuleIds":["zh.banned_opener"],
             "appRules":{"com.apple.Notes":{"enabled":false,"markdown":true}}}
            """
        let ud = UserDefaults(suiteName: "mig.\(UUID().uuidString)")!
        ud.set(Data(oldJSON.utf8), forKey: AppSettings.defaultsKey)
        let s = AppSettings(userDefaults: ud, secrets: InMemorySecretStore())
        XCTAssertFalse(s.autoUnderline)
        XCTAssertFalse(s.grammar)
        XCTAssertFalse(s.aiToneEn)
        XCTAssertEqual(s.sensitivity, 3)
        XCTAssertTrue(s.disabledRuleIds.contains("zh.banned_opener"))
        XCTAssertEqual(s.appRules["com.apple.Notes"]?.enabled, false)
        // first-launch defaults
        XCTAssertEqual(s.providers.count, 1)
        XCTAssertEqual(s.providers.first?.preset, .opencodeGo)
        XCTAssertEqual(s.activeProviderId, s.providers.first?.id)
        XCTAssertEqual(s.rewriteHotkey, .default)
    }

    func testProvidersRoundTrip() {
        let ud = UserDefaults(suiteName: "rt.\(UUID().uuidString)")!
        let s1 = AppSettings(userDefaults: ud, secrets: InMemorySecretStore())
        let added = s1.addProvider(preset: .ollama)
        XCTAssertEqual(s1.activeProvider?.id, added.id)
        let s2 = AppSettings(userDefaults: ud, secrets: InMemorySecretStore())
        XCTAssertEqual(s2.providers.count, 2)
        XCTAssertEqual(s2.activeProviderId, added.id)
        XCTAssertEqual(s2.activeProvider?.preset, .ollama)
        // delete → next provider becomes active, key wiped
        let mem = InMemorySecretStore()
        let s3 = AppSettings(userDefaults: ud, secrets: mem)
        mem.set("k", for: added.id.uuidString)
        s3.deleteProvider(id: added.id)
        XCTAssertNil(mem.get(added.id.uuidString))
        XCTAssertNotEqual(s3.activeProviderId, added.id)
    }

    func testInMemorySecretStore() {
        let m = InMemorySecretStore()
        m.set("abc", for: "p1")
        XCTAssertEqual(m.get("p1"), "abc")
        m.set(nil, for: "p1")
        XCTAssertNil(m.get("p1"))
    }
}

// MARK: - RewriteHotkey (recorded shortcut)

final class RewriteHotkeyTests: XCTestCase {
    private let ctrlOpt = UInt32(controlKey | optionKey)
    private let cmd = UInt32(cmdKey)
    private let cmdShift = UInt32(cmdKey | shiftKey)

    // legacy preset strings still decode to the same combos
    func testLegacyStringDecode() throws {
        func dec(_ s: String) throws -> RewriteHotkey {
            try JSONDecoder().decode(RewriteHotkey.self, from: Data("\"\(s)\"".utf8))
        }
        func spec(_ s: String) throws -> (UInt32, UInt32) {
            try XCTUnwrap(dec(s).spec.map { ($0.keyCode, $0.modifiers) })
        }
        XCTAssertTrue(try spec("ctrlOptR") == (UInt32(kVK_ANSI_R), ctrlOpt))
        XCTAssertTrue(try spec("ctrlOptE") == (UInt32(kVK_ANSI_E), ctrlOpt))
        XCTAssertTrue(
            try spec("optCmdJ") == (UInt32(kVK_ANSI_J), UInt32(optionKey | cmdKey))
        )
        XCTAssertEqual(try dec("off"), .off)
        XCTAssertEqual(try dec("whatever"), .default)
    }

    /// settings JSON with no hotkey key at all → default
    func testMissingKeyDecodesDefault() throws {
        let json = """
            {"autoUnderline":true,"grammar":true,"aiToneZh":true,
             "aiToneEn":true,"markdown":true,"sensitivity":2,
             "disabledRuleIds":[],"appRules":{}}
            """
        let ud = UserDefaults(suiteName: "hk.\(UUID().uuidString)")!
        ud.set(Data(json.utf8), forKey: AppSettings.defaultsKey)
        let s = AppSettings(userDefaults: ud, secrets: InMemorySecretStore())
        XCTAssertEqual(s.rewriteHotkey, .default)
    }

    /// keyed-object round trip, including the off state (keyCode omitted)
    func testKeyedRoundTrip() throws {
        let combo = RewriteHotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: cmdShift)
        let data = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(RewriteHotkey.self, from: data), combo)
        let off = try JSONDecoder().decode(
            RewriteHotkey.self, from: JSONEncoder().encode(RewriteHotkey.off)
        )
        XCTAssertEqual(off, .off)
        XCTAssertNil(off.spec)
    }

    func testLabels() {
        XCTAssertEqual(
            RewriteHotkey(keyCode: UInt32(kVK_ANSI_R), modifiers: ctrlOpt).label,
            "⌃⌥ R"
        )
        XCTAssertEqual(
            RewriteHotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: cmdShift).label,
            "⇧⌘ K"
        )
        XCTAssertEqual(
            RewriteHotkey(keyCode: UInt32(kVK_F5), modifiers: 0).label, "F5"
        )
        XCTAssertEqual(
            RewriteHotkey(
                keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)
            ).label,
            "⌥ Space"
        )
        XCTAssertEqual(RewriteHotkey.off.label, "未设置")
    }

    func testValidate() {
        XCTAssertEqual(
            RewriteHotkey.validate(keyCode: UInt32(kVK_ANSI_R), modifiers: 0),
            .needsModifier
        )
        XCTAssertEqual(
            RewriteHotkey.validate(
                keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(shiftKey)
            ),
            .needsModifier
        )
        XCTAssertEqual(
            RewriteHotkey.validate(
                keyCode: UInt32(kVK_ANSI_Q), modifiers: cmd
            ),
            .reserved
        )
        XCTAssertEqual(
            RewriteHotkey.validate(
                keyCode: UInt32(kVK_ANSI_R), modifiers: ctrlOpt
            ),
            .ok
        )
        // function keys need no modifier
        XCTAssertEqual(
            RewriteHotkey.validate(keyCode: UInt32(kVK_F6), modifiers: 0), .ok
        )
    }

    func testCarbonModifiersFromNSEvent() {
        XCTAssertEqual(RewriteHotkey.carbonModifiers([.control, .option]), ctrlOpt)
        XCTAssertEqual(RewriteHotkey.carbonModifiers([.command, .shift]), cmdShift)
        XCTAssertEqual(RewriteHotkey.carbonModifiers([]), 0)
        // device-dependent bits don't leak into the mask
        XCTAssertEqual(
            RewriteHotkey.carbonModifiers([.option, .capsLock]),
            UInt32(optionKey)
        )
    }
}
