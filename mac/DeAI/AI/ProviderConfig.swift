import Foundation

/// Wire protocol used to talk to a provider.
enum APIFormat: String, Codable, CaseIterable {
    case openAIChat
    case openAIResponses
    case anthropicMessages

    var label: String {
        switch self {
        case .openAIChat: return "OpenAI Chat Completions"
        case .openAIResponses: return "OpenAI Responses"
        case .anthropicMessages: return "Anthropic Messages"
        }
    }
}

enum ProviderPreset: String, Codable, CaseIterable {
    case opencodeGo
    case openAI
    case anthropic
    case deepseek
    case gemini
    case ollama
    case lmStudio
    case custom

    var label: String {
        switch self {
        case .opencodeGo: return "OpenCode Go"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .deepseek: return "DeepSeek"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .custom: return "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .opencodeGo: return "https://opencode.ai/zen/go/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .ollama: return "http://localhost:11434/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        self == .opencodeGo ? "deepseek-v4-flash" : ""
    }

    var defaultFormat: APIFormat {
        switch self {
        case .opencodeGo:
            return OpenCodeGoModels.format(for: defaultModel) ?? .openAIChat
        case .anthropic:
            return .anthropicMessages
        default:
            return .openAIChat
        }
    }

    /// Local servers accept requests without an API key.
    var requiresKey: Bool {
        switch self {
        case .ollama, .lmStudio: return false
        default: return true
        }
    }
}

/// OpenCode Go model id → API format. The settings UI offers these as a
/// picker; choosing a known model sets the format automatically.
enum OpenCodeGoModels {
    static let chat: [String] = [
        "deepseek-v4-flash", "deepseek-v4.1-flash", "deepseek-v4-pro",
        "glm-5.3", "glm-5.3-flash", "kimi-k3", "kimi-k2.6",
        "mimo-v2.6-pro", "mimo-v2.6-flash",
    ]
    static let messages: [String] = [
        "qwen3.8-max", "qwen3.8-flash", "qwen3.7-plus",
        "minimax-m3", "minimax-m2.7",
    ]
    static let responses: [String] = [
        "gpt-6-luna", "gpt-5.6-luna", "grok-4.7", "grok-4.6",
    ]

    static var all: [String] { chat + messages + responses }

    static func format(for model: String) -> APIFormat? {
        if chat.contains(model) { return .openAIChat }
        if messages.contains(model) { return .anthropicMessages }
        if responses.contains(model) { return .openAIResponses }
        return nil
    }
}

struct ProviderConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var preset: ProviderPreset
    var format: APIFormat
    var baseURL: String
    var model: String

    init(
        id: UUID = UUID(), name: String, preset: ProviderPreset,
        format: APIFormat, baseURL: String, model: String
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.format = format
        self.baseURL = baseURL
        self.model = model
    }

    init(preset: ProviderPreset) {
        self.init(
            name: preset.label,
            preset: preset,
            format: preset.defaultFormat,
            baseURL: preset.defaultBaseURL,
            model: preset.defaultModel
        )
    }

    /// For opencodeGo the wire format is decided by the chosen model; call
    /// after mutating `model` so the format follows the table.
    mutating func syncFormatWithModel() {
        if preset == .opencodeGo, let f = OpenCodeGoModels.format(for: model) {
            format = f
        }
    }
}
