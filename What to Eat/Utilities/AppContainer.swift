import Combine
import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    @Published private(set) var version = 1

    let healthKitManager = HealthKitManager()
    let locationManager = LocationManager()
    let llmClient: LLMClient

    init() {
        llmClient = LLMClient(
            responseLanguageProvider: { AppLanguage.current },
            configurationProvider: {
                LLMRequestConfiguration.current
            },
            keyProvider: { configuration in
                guard let key = KeychainService.shared.loadAPIKey(for: configuration.provider, region: configuration.keychainRegion), !key.isEmpty else {
                    throw LLMClientError.missingAPIKey
                }
                return key
            }
        )
    }

    var maskedAPIKey: String? {
        let configuration = LLMRequestConfiguration.current
        return KeychainService.shared.maskedAPIKey(for: configuration.provider, region: configuration.keychainRegion)
    }

    var activeLLMConfiguration: LLMRequestConfiguration {
        LLMRequestConfiguration.current
    }
}
