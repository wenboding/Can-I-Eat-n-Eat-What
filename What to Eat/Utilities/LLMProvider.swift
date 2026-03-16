import Foundation

enum LLMProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI = "openai"
    case qwen = "qwen"

    static let storageKey = "llm_provider"

    var id: String { rawValue }

    var providerDisplayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .qwen:
            return "Qwen(中国用户)"
        }
    }

    var docsURL: URL {
        switch self {
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")!
        case .qwen:
            return URL(string: "https://bailian.console.aliyun.com/cn-beijing/?spm=a2c4g.11186623.0.0.2510172aQL12HT&tab=model#/api-key")!
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:
            return LLMSettings.openAIDefaultModel
        case .qwen:
            return LLMSettings.qwenDefaultModel
        }
    }
}

enum QwenRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case beijing = "beijing"

    static let storageKey = "qwen_region"

    var id: String { rawValue }

    var displayName: String {
        LocalizedText.ui("China (Beijing)", "中国（北京）")
    }

    var baseURL: URL {
        URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
    }
}

enum LLMSettings {
    static let debugLoggingStorageKey = "llm_debug_logging"
    static let openAIDefaultModel = "gpt-5.1"
    static let qwenDefaultModel = "qwen3.5-plus"
}

struct LLMRequestConfiguration: Sendable {
    let provider: LLMProvider
    let qwenRegion: QwenRegion?

    var effectiveQwenRegion: QwenRegion {
        .beijing
    }

    var defaultModel: String {
        provider.defaultModel
    }

    var responsesEndpoint: URL {
        switch provider {
        case .openAI:
            return URL(string: "https://api.openai.com/v1/responses")!
        case .qwen:
            return effectiveQwenRegion.baseURL.appendingPathComponent("chat/completions")
        }
    }

    var keychainRegion: QwenRegion? {
        provider == .qwen ? effectiveQwenRegion : nil
    }

    static var current: LLMRequestConfiguration {
        let defaults = UserDefaults.standard
        let provider = LLMProvider(rawValue: defaults.string(forKey: LLMProvider.storageKey) ?? "") ?? .openAI
        let region: QwenRegion? = provider == .qwen ? .beijing : nil
        return LLMRequestConfiguration(provider: provider, qwenRegion: region)
    }
}
