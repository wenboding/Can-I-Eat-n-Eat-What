import AVFoundation
import CoreLocation
import Photos
import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    private static let openAIDataPolicyURL = URL(string: "https://developers.openai.com/api/docs/guides/your-data")!
    private static let californiaCCPAURL = URL(string: "https://oag.ca.gov/privacy/ccpa")!
    private static let consentStepIndex = 5

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(LLMProvider.storageKey) private var llmProviderRawValue = LLMProvider.openAI.rawValue
    @AppStorage(QwenRegion.storageKey) private var qwenRegionRawValue = QwenRegion.beijing.rawValue

    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext

    @State private var stepIndex = 0
    @State private var apiKeyInput = ""
    @State private var onboardingError: String?
    @State private var photosStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var onboardingDietTarget: DietTarget = .maintainHealth
    @State private var hasAcceptedDataConsent = false

    private let steps: [LocalizedStringKey] = [
        "Intro",
        "Diet Target",
        "Health",
        "Location",
        "Photos",
        "Consent",
        "API Key"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                MealCoachBackground()

                VStack(spacing: 16) {
                    stepHeader

                    Group {
                        switch stepIndex {
                        case 0:
                            introStep
                        case 1:
                            dietTargetStep
                        case 2:
                            healthStep
                        case 3:
                            locationStep
                        case 4:
                            photosStep
                        case 5:
                            consentStep
                        default:
                            apiKeyStep
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .mealCoachCard(tint: stepTint)

                    if let onboardingError {
                        Text(onboardingError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    HStack(spacing: 10) {
                        if stepIndex > 0 {
                            Button("Back") {
                                onboardingError = nil
                                stepIndex -= 1
                            }
                            .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.navy))
                        }

                        Spacer()

                        if stepIndex < steps.count - 1 {
                            Button("Continue") {
                                handleContinue()
                            }
                            .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))
                        } else {
                            Button("Finish") {
                                completeOnboarding()
                            }
                            .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Meal Coach Setup")
        }
        .onAppear {
            photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            qwenRegionRawValue = QwenRegion.beijing.rawValue
            loadDietTargetPreference()
        }
    }

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: llmProviderRawValue) ?? .openAI
    }

    private var providerBinding: Binding<LLMProvider> {
        Binding(
            get: { selectedProvider },
            set: { llmProviderRawValue = $0.rawValue }
        )
    }

    private var selectedRegionForKeychain: QwenRegion? {
        selectedProvider == .qwen ? .beijing : nil
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedText.ui("Step \(stepIndex + 1) of \(steps.count)", "第 \(stepIndex + 1) / \(steps.count) 步"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(MealCoachTheme.secondaryInk)

            Text(steps[stepIndex])
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(MealCoachTheme.ink)

            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index <= stepIndex ? MealCoachTheme.coral : .white.opacity(0.6))
                        .frame(height: 8)
                }
            }
        }
        .mealCoachCard(tint: MealCoachTheme.amber)
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Meal Coach")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text("This demo app helps you analyze meals and generate one-shot meal suggestions.")
            Text("Disclaimer: This app is not medical advice. Always consult a qualified professional for medical or nutrition decisions.")
                .foregroundStyle(MealCoachTheme.secondaryInk)
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Health Access", systemImage: "heart.text.square.fill")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(MealCoachTheme.ink)
            Text(
                LocalizedText.ui(
                    "Allow read-only HealthKit access to tailor recommendations using activity, workout sessions (type and calories), sleep, and body metrics.",
                    "允许只读 HealthKit 权限，以便基于活动、运动记录（类型与消耗热量）、睡眠和身体指标进行个性化建议。"
                )
            )
            Text(healthStatusText)
                .font(.subheadline)
                .foregroundStyle(MealCoachTheme.secondaryInk)

            Button("Grant Health Access") {
                Task {
                    _ = await appContainer.healthKitManager.requestAuthorization()
                }
            }
            .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.teal))
        }
    }

    private var dietTargetStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Diet Target", systemImage: "target")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(MealCoachTheme.ink)

            Text(
                LocalizedText.ui(
                    "Set your main goal so recommendations and analysis align with your nutrition direction.",
                    "设置你的主要目标，让推荐和分析更符合你的营养方向。"
                )
            )

            Picker("Diet Target", selection: $onboardingDietTarget) {
                ForEach(DietTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }

            if onboardingDietTarget == .loseWeight {
                Text(
                    LocalizedText.ui(
                        "Lose weight target = about a 200-300 kcal daily deficit, combined with exercise and adjusted for age/body weight/activity.",
                        "减脂目标 = 每日约 200-300 千卡热量缺口，并结合运动，同时按年龄/体重/活动量调整。"
                    )
                )
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.secondaryInk)
            }
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Location Access", systemImage: "location.fill")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(MealCoachTheme.ink)
            Text("Allow location to optionally include nearby restaurant suggestions.")
            Text(locationStatusText)
                .font(.subheadline)
                .foregroundStyle(MealCoachTheme.secondaryInk)

            Button("Grant Location Access") {
                appContainer.locationManager.requestWhenInUsePermission()
            }
            .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.coral, endColor: MealCoachTheme.amber))
        }
    }

    private var photosStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Photos Access", systemImage: "photo.on.rectangle.angled")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(MealCoachTheme.ink)
            Text(LocalizedText.ui("Allow photo and camera access for meal photos and medical record uploads.", "允许照片与相机权限，用于上传餐食照片和健康记录图片。"))
            Text(photosStatusText)
                .font(.subheadline)
                .foregroundStyle(MealCoachTheme.secondaryInk)
            Text(cameraStatusText)
                .font(.subheadline)
                .foregroundStyle(MealCoachTheme.secondaryInk)

            HStack(spacing: 10) {
                Button("Grant Photos Access") {
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                        Task { @MainActor in
                            photosStatus = status
                        }
                    }
                }
                .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))

                Button("Grant Camera Access") {
                    requestCameraAccess()
                }
                .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))
            }
        }
    }

    private var consentStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(LocalizedText.ui("Consent & Data Use", "知情同意与数据使用"), systemImage: "checkmark.shield.fill")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(MealCoachTheme.ink)

                Text(
                    LocalizedText.ui(
                        "By tapping Continue, you agree to the following consent and data-use terms:",
                        "点击“继续”即表示你同意以下知情同意与数据使用条款："
                    )
                )
                .font(.subheadline.weight(.semibold))

                consentBullet(
                    english: "No company-side storage/use: we do not store your personal content on our servers and we do not use your content to train our own models. Unless you use an AI feature, your data stays on your device.",
                    chinese: "我们不在公司服务器存储你的个人内容，也不会使用你的内容训练我们自己的模型。除非你主动使用 AI 功能，否则数据仅保留在你的设备上。"
                )

                consentBullet(
                    english: "Local storage on device: meal records, preferences, and settings stay in local app storage. Your API key (OpenAI or Qwen) is stored in iOS Keychain.",
                    chinese: "本地存储：餐食记录、偏好和设置保存在本机应用存储中；API Key（OpenAI 或 Qwen）保存在 iOS Keychain。"
                )

                consentBullet(
                    english: "When you use AI-powered features, selected inputs (for example meal photos, medical record images, and text context) are sent to the selected model provider (OpenAI US or Alibaba Cloud DashScope) over encrypted transport.",
                    chinese: "当你使用 AI 功能时，所选输入（如餐食照片、医疗记录图片和文本上下文）会通过加密传输发送到当前选择的模型提供方（OpenAI US 或阿里云百炼 DashScope）。"
                )

                consentBullet(
                    english: selectedProvider == .openAI
                        ? "OpenAI API policy notice: under OpenAI API policy, data sent to OpenAI API may be retained by OpenAI for up to 30 days for abuse monitoring and is not used to train OpenAI models (policy terms may change)."
                        : "DashScope notice: data handling, retention, and regional compliance depend on Alibaba Cloud service terms and the selected region. Review the provider documentation before using AI features.",
                    chinese: selectedProvider == .openAI
                        ? "OpenAI API 政策说明：根据 OpenAI API 政策，发送到 OpenAI API 的数据可能会被 OpenAI 保留最多 30 天用于滥用监测，且不会用于训练 OpenAI 模型（政策条款可能调整）。"
                        : "DashScope 说明：数据处理、保留期限和区域合规要求取决于阿里云服务条款及所选区域；使用 AI 功能前请先查阅相关文档。"
                )

                consentBullet(
                    english: "US/California notice: we do not sell personal information or share it for cross-context behavioral advertising. If laws such as CCPA/CPRA apply, this page is intended to function as a notice at collection; you can delete local app data anytime in Data Management.",
                    chinese: "美国/加州说明：我们不会出售个人信息，也不会将其用于跨情境行为广告共享。若 CCPA/CPRA 等法律适用，本页面旨在作为收集时告知；你可随时在“数据管理”中删除本地应用数据。"
                )

                Toggle(isOn: $hasAcceptedDataConsent) {
                    Text(LocalizedText.ui("I have read and agree to this consent notice.", "我已阅读并同意上述知情同意说明。"))
                        .font(.subheadline.weight(.semibold))
                }
                .tint(MealCoachTheme.teal)

                if selectedProvider == .openAI {
                    Link(
                        LocalizedText.ui("OpenAI API data controls and retention policy", "OpenAI API 数据控制与保留政策"),
                        destination: Self.openAIDataPolicyURL
                    )
                    .font(.footnote)
                    .foregroundStyle(MealCoachTheme.navy)
                }

                Link(
                    LocalizedText.ui("Selected provider key setup and documentation", "当前提供方的 Key 设置与文档"),
                    destination: selectedProvider.docsURL
                )
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.navy)

                Link(
                    LocalizedText.ui("California CCPA consumer rights overview", "加州 CCPA 消费者权利说明"),
                    destination: Self.californiaCCPAURL
                )
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.navy)

                Text(LocalizedText.ui("This notice is for product transparency and is not legal advice.", "本说明用于产品透明披露，不构成法律意见。"))
                    .font(.footnote)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("API Key Setup", systemImage: "key.fill")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(MealCoachTheme.ink)

            Picker("Provider", selection: providerBinding) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.providerDisplayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            if selectedProvider == .qwen {
                Text(
                    LocalizedText.ui(
                        "Qwen uses the Beijing DashScope endpoint for Chinese users.",
                        "Qwen 使用北京 DashScope 接口，面向中国用户。"
                    )
                )
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.secondaryInk)
            }

            if let masked = KeychainService.shared.maskedAPIKey(for: selectedProvider, region: selectedRegionForKeychain) {
                Text(LocalizedText.ui("Saved key: \(masked)", "已保存密钥：\(masked)"))
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
            } else {
                Text("No API key saved yet.")
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
            }

            Link(
                LocalizedText.ui(
                    "Get your own key",
                    "获取你自己的密钥"
                ),
                destination: selectedProvider.docsURL
            )
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.navy)

            SecureField("Paste API key", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(12)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button("Save Key") {
                    saveAPIKey()
                }
                .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))

                Button("Remove Key", role: .destructive) {
                    removeAPIKey()
                }
                .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
            }

            Text(
                LocalizedText.ui(
                    "Only one API key is stored at a time. Saving a new OpenAI or Qwen key removes the other provider key and switches the app to that provider.",
                    "应用一次只保存一个 API Key。保存新的 OpenAI 或 Qwen Key 时，会删除另一个提供方的 Key，并自动切换到对应提供方。"
                )
            )
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.secondaryInk)
        }
    }

    private var stepTint: Color {
        switch stepIndex {
        case 0: return MealCoachTheme.amber
        case 1: return MealCoachTheme.coral
        case 2: return MealCoachTheme.teal
        case 3: return MealCoachTheme.coral
        case 4: return MealCoachTheme.navy
        case 5: return MealCoachTheme.amber
        default: return MealCoachTheme.teal
        }
    }

    private var healthStatusText: LocalizedStringKey {
        switch appContainer.healthKitManager.permissionState {
        case .authorized:
            return "Health access granted."
        case .denied:
            return "Health access denied. You can still use the app with reduced personalization."
        case .unavailable:
            return "Health data unavailable on this device."
        case .unknown:
            return "Not requested yet."
        }
    }

    private var locationStatusText: LocalizedStringKey {
        switch appContainer.locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Location access granted."
        case .denied, .restricted:
            return "Location denied. Recommendations will work without nearby options."
        case .notDetermined:
            return "Not requested yet."
        @unknown default:
            return "Unknown location permission status."
        }
    }

    private var photosStatusText: LocalizedStringKey {
        switch photosStatus {
        case .authorized, .limited:
            return "Photo access granted."
        case .denied, .restricted:
            return "Photo access denied. Meal and medical image upload will not work."
        case .notDetermined:
            return "Not requested yet."
        @unknown default:
            return "Unknown photo permission status."
        }
    }

    private var cameraStatusText: LocalizedStringKey {
        switch cameraStatus {
        case .authorized:
            return "Camera access granted."
        case .denied, .restricted:
            return "Camera access denied. In-app camera capture will not work."
        case .notDetermined:
            return "Camera permission not requested yet."
        @unknown default:
            return "Unknown camera permission status."
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onboardingError = LocalizedText.ui("Please enter an API key before saving.", "请先输入 API Key 再保存。")
            return
        }

        do {
            try KeychainService.shared.saveAPIKey(
                trimmed,
                for: selectedProvider,
                region: selectedRegionForKeychain
            )
            llmProviderRawValue = selectedProvider.rawValue
            if selectedProvider == .qwen {
                qwenRegionRawValue = QwenRegion.beijing.rawValue
            }
            apiKeyInput = ""
            onboardingError = nil
        } catch {
            onboardingError = error.localizedDescription
        }
    }

    private func removeAPIKey() {
        do {
            try KeychainService.shared.deleteAPIKey(
                for: selectedProvider,
                region: selectedRegionForKeychain
            )
            onboardingError = nil
        } catch {
            onboardingError = error.localizedDescription
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    cameraStatus = granted ? .authorized : .denied
                }
            }
        case .denied, .restricted:
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        @unknown default:
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func handleContinue() {
        onboardingError = nil

        if stepIndex == Self.consentStepIndex && !hasAcceptedDataConsent {
            onboardingError = LocalizedText.ui(
                "Please review and accept the consent terms before continuing.",
                "继续前请先阅读并勾选同意知情同意条款。"
            )
            return
        }

        stepIndex += 1
    }

    private func completeOnboarding() {
        guard hasAcceptedDataConsent else {
            onboardingError = LocalizedText.ui(
                "Please complete the consent step before finishing onboarding.",
                "完成引导前请先完成知情同意步骤。"
            )
            return
        }

        guard KeychainService.shared.loadAPIKey(for: selectedProvider, region: selectedRegionForKeychain) != nil else {
            onboardingError = LocalizedText.ui("Please save an API key for the selected provider before continuing.", "请先为当前选择的提供方保存 API Key 再继续。")
            return
        }

        do {
            let preferences = try UserPreferencesStore.fetchOrCreate(in: modelContext)
            preferences.dietTarget = onboardingDietTarget
            try modelContext.save()
        } catch {
            onboardingError = error.localizedDescription
            return
        }

        hasCompletedOnboarding = true
    }

    private func loadDietTargetPreference() {
        do {
            let preferences = try UserPreferencesStore.fetchOrCreate(in: modelContext)
            onboardingDietTarget = preferences.dietTarget
        } catch {
            onboardingError = error.localizedDescription
        }
    }

    private func consentBullet(english: String, chinese: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .padding(.top, 6)
                .foregroundStyle(MealCoachTheme.navy)

            Text(LocalizedText.ui(english, chinese))
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
