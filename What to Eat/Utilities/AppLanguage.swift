import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let storageKey = "appLanguageCode"

    var id: String { rawValue }

    var localeIdentifier: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    var openAIResponseLanguageDirective: String {
        switch self {
        case .english:
            return "Write all human-readable JSON text values in English."
        case .simplifiedChinese:
            return "Write all human-readable JSON text values in Simplified Chinese."
        }
    }

    static var current: AppLanguage {
        let code = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.english.rawValue
        return AppLanguage(rawValue: code) ?? .english
    }
}

enum LocalizedText {
    static func ui(_ english: String, _ simplifiedChinese: String) -> String {
        AppLanguage.current == .simplifiedChinese ? simplifiedChinese : english
    }
}
