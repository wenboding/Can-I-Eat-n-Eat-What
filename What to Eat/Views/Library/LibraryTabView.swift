import SwiftData
import SwiftUI

struct LibraryTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DailySummary.date, order: .reverse)
    private var summaries: [DailySummary]

    @Query(sort: \MedicalRecordEntry.dateUploaded, order: .reverse)
    private var medicalRecords: [MedicalRecordEntry]

    @State private var showingMedicalUpload = false
    @State private var libraryError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MealCoachBackground()

                List {
                    Section {
                        NavigationLink {
                            DailyHistoryListView()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedText.ui("Open Daily History", "打开每日历史"))
                                    .font(.headline)
                                Text(
                                    LocalizedText.ui(
                                        "\(summaries.count) days saved",
                                        "已保存 \(summaries.count) 天"
                                    )
                                )
                                    .font(.subheadline)
                                    .foregroundStyle(MealCoachTheme.secondaryInk)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(MealCoachTheme.listRowBackground)

                        Button {
                            recomputeDailySummaries()
                        } label: {
                            Label("Recompute Daily Totals", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .foregroundStyle(MealCoachTheme.ink)
                        .listRowBackground(MealCoachTheme.listRowBackground)
                    } header: {
                        sectionHeader("Daily History")
                    }

                    Section {
                        Button {
                            showingMedicalUpload = true
                        } label: {
                            Label(
                                LocalizedText.ui("Describe Your Health Status", "描述你的健康状态"),
                                systemImage: "doc.text.viewfinder"
                            )
                        }
                        .foregroundStyle(MealCoachTheme.ink)
                        .listRowBackground(MealCoachTheme.listRowBackground)

                        if medicalRecords.isEmpty {
                            Text(LocalizedText.ui("No description given.", "未提供描述。"))
                                .foregroundStyle(MealCoachTheme.secondaryInk)
                                .listRowBackground(MealCoachTheme.listRowBackground)
                        } else {
                            ForEach(medicalRecords) { record in
                                NavigationLink {
                                    MedicalRecordDetailView(record: record)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.dateUploaded.formattedDateTime())
                                            .font(.headline)
                                        Text(record.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LocalizedText.ui("No description given.", "未提供描述。") : record.rawText)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                            .foregroundStyle(MealCoachTheme.secondaryInk)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .listRowBackground(MealCoachTheme.listRowBackground)
                            }
                            .onDelete(perform: deleteMedicalRecords)
                        }
                    } header: {
                        sectionHeader(LocalizedText.ui("Health Status", "健康状态"))
                    }

                    Section {
                        NavigationLink {
                            AccessManagementView()
                        } label: {
                            Label("Access Management", systemImage: "lock.shield")
                        }
                        .listRowBackground(MealCoachTheme.listRowBackground)

                        NavigationLink {
                            APIKeySettingsView()
                        } label: {
                            Label("API Key Setup", systemImage: "key.fill")
                        }
                        .listRowBackground(MealCoachTheme.listRowBackground)

                        NavigationLink {
                            PreferencesView()
                        } label: {
                            Label("Preferences", systemImage: "slider.horizontal.3")
                        }
                        .listRowBackground(MealCoachTheme.listRowBackground)

                        NavigationLink {
                            LanguageSettingsView()
                        } label: {
                            Label("Language", systemImage: "character.book.closed")
                        }
                        .listRowBackground(MealCoachTheme.listRowBackground)

                        NavigationLink {
                            DataManagementView()
                        } label: {
                            Label("Data Management", systemImage: "externaldrive.fill.badge.icloud")
                        }
                        .listRowBackground(MealCoachTheme.listRowBackground)
                    } header: {
                        sectionHeader("Settings")
                    }

                    if let libraryError {
                        Section {
                            Text(libraryError)
                                .foregroundStyle(.red)
                                .listRowBackground(MealCoachTheme.listRowBackground)
                        }
                    }
                }
                .foregroundStyle(MealCoachTheme.ink)
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .sheet(isPresented: $showingMedicalUpload) {
                MedicalRecordUploadView()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(MealCoachTheme.ink)
            .textCase(nil)
    }

    @MainActor
    private func recomputeDailySummaries() {
        do {
            try DailySummaryCalculator.recomputeAll(context: modelContext)
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteMedicalRecords(offsets: IndexSet) {
        for index in offsets {
            let record = medicalRecords[index]
            for photoFilename in record.photoFilenames {
                FileStorage.deleteImage(filename: photoFilename)
            }
            modelContext.delete(record)
        }

        do {
            try modelContext.save()
        } catch {
            libraryError = error.localizedDescription
        }
    }
}

struct DailyHistoryListView: View {
    @Query(sort: \DailySummary.date, order: .reverse)
    private var summaries: [DailySummary]

    var body: some View {
        ZStack {
            MealCoachBackground()

            List {
                Section {
                    if summaries.isEmpty {
                        Text(LocalizedText.ui("No daily summaries yet.", "暂无每日汇总。"))
                            .foregroundStyle(MealCoachTheme.secondaryInk)
                    } else {
                        ForEach(summaries) { summary in
                            NavigationLink {
                                DailyHistoryDetailView(date: summary.date)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.date.formattedShortDate())
                                        .font(.headline)
                                    Text(
                                        LocalizedText.ui(
                                            "Meals: \(summary.mealCount) • Calories: \(Int(summary.caloriesTotalEstimate))",
                                            "餐次：\(summary.mealCount) • 热量：\(Int(summary.caloriesTotalEstimate))"
                                        )
                                    )
                                        .font(.subheadline)
                                        .foregroundStyle(MealCoachTheme.secondaryInk)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Saved Days", "已保存天数"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)
            }
            .foregroundStyle(MealCoachTheme.ink)
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle(LocalizedText.ui("Daily History", "每日历史"))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(MealCoachTheme.ink)
            .textCase(nil)
    }
}

struct APIKeySettingsView: View {
    @AppStorage(LLMProvider.storageKey) private var llmProviderRawValue = LLMProvider.openAI.rawValue
    @AppStorage(QwenRegion.storageKey) private var qwenRegionRawValue = QwenRegion.beijing.rawValue

    @State private var providerSelection = LLMProvider.openAI
    @State private var apiKeyInput = ""
    @State private var maskedKey: String?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showingRemoveConfirmation = false

    private var selectedProvider: LLMProvider {
        providerSelection
    }

    private var selectedRegionForKeychain: QwenRegion? {
        selectedProvider == .qwen ? .beijing : nil
    }

    private var providerBinding: Binding<LLMProvider> {
        Binding(
            get: { selectedProvider },
            set: { providerSelection = $0 }
        )
    }

    var body: some View {
        ZStack {
            MealCoachBackground()

            Form {
                Section {
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

                    Link(
                        LocalizedText.ui("Get your own key", "获取你自己的密钥"),
                        destination: selectedProvider.docsURL
                    )
                    .font(.footnote)
                } header: {
                    sectionHeader("Provider")
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    if let maskedKey {
                        Text(maskedKey)
                            .font(.body.monospaced())
                    } else {
                        Text(LocalizedText.ui("No API key saved for the selected provider.", "当前选择的提供方尚未保存 API Key。"))
                            .foregroundStyle(MealCoachTheme.secondaryInk)
                    }
                } header: {
                    sectionHeader("Stored Key")
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    SecureField("Paste API key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button("Save Key") {
                        saveKey()
                    }
                    .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))
                } header: {
                    sectionHeader("Update API Key")
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Button("Remove Key", role: .destructive) {
                        showingRemoveConfirmation = true
                    }
                    .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
                } header: {
                    sectionHeader("Danger Zone")
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.green)
                    }
                    .listRowBackground(MealCoachTheme.listRowBackground)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(MealCoachTheme.listRowBackground)
                }

                Section {
                    Text(
                        LocalizedText.ui(
                            "Only one API key is stored at a time. Saving a new OpenAI or Qwen key removes the other provider key and switches the app to that provider.",
                            "应用一次只保存一个 API Key。保存新的 OpenAI 或 Qwen Key 时，会删除另一个提供方的 Key，并自动切换到对应提供方。"
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
                }
                .listRowBackground(MealCoachTheme.listRowBackground)
            }
            .foregroundStyle(MealCoachTheme.ink)
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("API Key Setup")
        .confirmationDialog(
            "Remove the saved API key?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Key", role: .destructive) {
                removeKey()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            providerSelection = LLMProvider(rawValue: llmProviderRawValue) ?? .openAI
            qwenRegionRawValue = QwenRegion.beijing.rawValue
            refreshStoredKey()
        }
        .onChange(of: providerSelection) { _, _ in
            clearTransientState()
            refreshStoredKey()
        }
    }

    private func saveKey() {
        do {
            try KeychainService.shared.saveAPIKey(
                apiKeyInput,
                for: selectedProvider,
                region: selectedRegionForKeychain
            )
            llmProviderRawValue = selectedProvider.rawValue
            qwenRegionRawValue = QwenRegion.beijing.rawValue
            apiKeyInput = ""
            refreshStoredKey()
            statusMessage = LocalizedText.ui("API key saved.", "API Key 已保存。")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func removeKey() {
        do {
            try KeychainService.shared.deleteAPIKey(
                for: selectedProvider,
                region: selectedRegionForKeychain
            )
            apiKeyInput = ""
            refreshStoredKey()
            statusMessage = LocalizedText.ui("API key removed.", "API Key 已移除。")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func refreshStoredKey() {
        maskedKey = KeychainService.shared.maskedAPIKey(
            for: selectedProvider,
            region: selectedRegionForKeychain
        )
    }

    private func clearTransientState() {
        apiKeyInput = ""
        statusMessage = nil
        errorMessage = nil
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(MealCoachTheme.ink)
            .textCase(nil)
    }
}
