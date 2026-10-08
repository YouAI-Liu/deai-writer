import Foundation

enum LLMError: LocalizedError {
    case invalidBaseURL(String)
    /// `kind` carries the status-mapped prefix; `server` is the server's own
    /// message (already truncated) — both render per language in `message`.
    case http(status: Int, kind: HTTPErrorKind, server: String)
    case badResponse(BadResponseKind)

    enum HTTPErrorKind {
        case generic
        case unauthorized
        case rateLimited
    }

    enum BadResponseKind {
        case unparseable
        case emptyText
    }

    /// Default (zh) — `LocalizedError` conformance for legacy callers.
    var errorDescription: String? { message(.zh) }

    func message(_ lang: UILanguage) -> String {
        switch self {
        case .invalidBaseURL(let u):
            return L10n.f(.errorInvalidBaseURL, lang, u)
        case .http(let status, let kind, let server):
            let prefix: String?
            switch kind {
            case .generic: prefix = nil
            case .unauthorized: prefix = L10n.t(.errorHTTPAuth, lang)
            case .rateLimited: prefix = L10n.t(.errorHTTPRate, lang)
            }
            if let prefix {
                return server.isEmpty
                    ? prefix
                    : prefix + (lang == .zh ? "：" : ": ") + server
            }
            return server.isEmpty ? "HTTP \(status)" : server
        case .badResponse(.unparseable):
            return L10n.t(.errorParseResponse, lang)
        case .badResponse(.emptyText):
            return L10n.t(.errorNoText, lang)
        }
    }
}

extension Error {
    /// Localized UI text: `LLMError` renders in the UI language, other
    /// errors (URLError etc.) keep the system-localized description.
    func deaiMessage(_ lang: UILanguage) -> String {
        (self as? LLMError)?.message(lang) ?? localizedDescription
    }
}

/// Non-streaming chat with an OpenAI/Anthropic-compatible endpoint.
/// `makeRequest`/`parseResponse`/`cleanOutput` are pure statics for tests.
/// Never log the API key or the rewrite text — lengths and statuses only.
struct LLMClient {
    var session: URLSession = .shared
    var timeout: TimeInterval = 60

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.1"
    }

    static func makeRequest(
        config: ProviderConfig,
        apiKey: String?,
        system: String,
        user: String,
        sessionId: String
    ) throws -> URLRequest {
        let base = config.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        let path: String
        let body: [String: Any]
        switch config.format {
        case .openAIChat:
            path = "/chat/completions"
            body = [
                "model": config.model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
                "stream": false,
            ]
        case .openAIResponses:
            path = "/responses"
            body = [
                "model": config.model,
                "instructions": system,
                "input": user,
                "stream": false,
            ]
        case .anthropicMessages:
            path = "/messages"
            body = [
                "model": config.model,
                "system": system,
                "messages": [
                    ["role": "user", "content": user],
                ],
                "max_tokens": 4096,
            ]
        }
        guard let url = URL(string: trimmed + path) else {
            throw LLMError.invalidBaseURL(config.baseURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("DeAI/\(version)", forHTTPHeaderField: "User-Agent")
        // OpenCode session affinity; harmless everywhere else.
        req.setValue(sessionId, forHTTPHeaderField: "x-opencode-session")
        if config.format == .anthropicMessages {
            // protocol version header — required regardless of auth
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        if let key = apiKey, !key.isEmpty {
            switch config.format {
            case .openAIChat, .openAIResponses:
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            case .anthropicMessages:
                req.setValue(key, forHTTPHeaderField: "x-api-key")
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extract the assistant text from a 2xx response; map non-2xx bodies to
    /// a human-readable error (Chinese status prefix + server message).
    static func parseResponse(
        format: APIFormat, data: Data, statusCode: Int
    ) throws -> String {
        guard (200..<300).contains(statusCode) else {
            throw LLMError.http(
                status: statusCode,
                kind: Self.httpErrorKind(statusCode),
                server: serverMessage(from: data)
            )
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
            throw LLMError.badResponse(.unparseable)
        }
        switch format {
        case .openAIChat:
            if let choices = obj["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                return content
            }
        case .openAIResponses:
            var parts: [String] = []
            if let output = obj["output"] as? [[String: Any]] {
                for item in output {
                    guard let content = item["content"] as? [[String: Any]]
                    else { continue }
                    for part in content
                    where part["type"] as? String == "output_text" {
                        if let t = part["text"] as? String { parts.append(t) }
                    }
                }
            }
            if parts.isEmpty, let t = obj["output_text"] as? String {
                parts.append(t)
            }
            if !parts.isEmpty { return parts.joined() }
        case .anthropicMessages:
            var parts: [String] = []
            if let content = obj["content"] as? [[String: Any]] {
                for part in content where part["type"] as? String == "text" {
                    if let t = part["text"] as? String { parts.append(t) }
                }
            }
            if !parts.isEmpty { return parts.joined() }
        }
        throw LLMError.badResponse(.emptyText)
    }

    /// Server error message: `error.message` (object), `error` (string), or
    /// `message`; otherwise the raw body truncated to 200 chars.
    private static func serverMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] {
            if let err = obj["error"] as? [String: Any],
               let m = err["message"] as? String {
                return m
            }
            if let e = obj["error"] as? String { return e }
            if let m = obj["message"] as? String { return m }
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return String(raw.prefix(200))
    }

    /// Status → localized prefix bucket; `LLMError.http` renders the actual
    /// "prefix: server" composition per language.
    private static func httpErrorKind(_ status: Int) -> LLMError.HTTPErrorKind {
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .generic
        }
    }

    /// Model hygiene: drop think blocks, one surrounding code fence, and
    /// echoed <<< >>> scope markers.
    static func cleanOutput(_ input: String) -> String {
        var out = input
        if let re = try? NSRegularExpression(
            pattern: "<think>.*?</think>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) {
            out = re.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: ""
            )
        }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // one surrounding ``` fence (optional language tag on first line)
        var lines = out.components(separatedBy: "\n")
        if lines.count >= 2,
           lines.first!.hasPrefix("```"),
           lines.last!.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeFirst()
            lines.removeLast()
            out = lines.joined(separator: "\n")
        }
        lines = out.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "<<<" {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == ">>>" {
            lines.removeLast()
        }
        out = lines.joined(separator: "\n")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One rewrite round-trip. Cancellation propagates (Task.cancel →
    /// CancellationError). The debug mock bypasses the network entirely.
    func complete(
        config: ProviderConfig,
        apiKey: String?,
        system: String,
        user: String
    ) async throws -> String {
        if UserDefaults.standard.string(forKey: "deai.debugStatePath") != nil,
           let mock = UserDefaults.standard.string(
               forKey: "deai.debugMockRewrite"
           ) {
            try await Task.sleep(nanoseconds: 300_000_000)
            return mock
        }
        var req = try Self.makeRequest(
            config: config,
            apiKey: apiKey,
            system: system,
            user: user,
            sessionId: UUID().uuidString
        )
        req.timeoutInterval = timeout
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return Self.cleanOutput(
            try Self.parseResponse(
                format: config.format, data: data, statusCode: status
            )
        )
    }
}
