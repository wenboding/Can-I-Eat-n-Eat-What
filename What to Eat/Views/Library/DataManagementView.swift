import SwiftData
import SwiftUI

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false

    var body: some View {
        ZStack {
            MealCoachBackground()

            Form {
                Section {
                    Button(LocalizedText.ui("Generate JSON Export", "生成 JSON 导出")) {
                        generateExportFile()
                    }
                    .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.teal))

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label(
                                LocalizedText.ui("Share Export File", "分享导出文件"),
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.navy))
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Export", "导出"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Button(LocalizedText.ui("Delete All Local Data", "删除所有本地数据"), role: .destructive) {
                        showingDeleteAlert = true
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Delete", "删除"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Text(
                        LocalizedText.ui(
                            "All app data is stored on this device. If you use AI-powered analysis, only the selected content is sent to the selected model provider API, and this app does not use that data for training.",
                            "应用数据仅存储在本机。如果你使用 AI 分析，仅会将所选内容发送到当前选择的模型提供方 API，本应用不会将这些数据用于训练。"
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
                } header: {
                    sectionHeader(LocalizedText.ui("Privacy", "隐私"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(MealCoachTheme.listRowBackground)
                }
            }
            .foregroundStyle(MealCoachTheme.ink)
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle(LocalizedText.ui("Data Management", "数据管理"))
        .alert(LocalizedText.ui("Delete all data?", "删除所有数据？"), isPresented: $showingDeleteAlert) {
            Button(LocalizedText.ui("Delete", "删除"), role: .destructive) {
                deleteAllData()
            }
            Button(LocalizedText.ui("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(
                LocalizedText.ui(
                    "This removes all meals, summaries, health descriptions, and local images.",
                    "这将删除所有餐食、每日汇总、健康描述和本地图片。"
                )
            )
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(MealCoachTheme.ink)
            .textCase(nil)
    }

    @MainActor
    private func generateExportFile() {
        do {
            let meals = try modelContext.fetch(FetchDescriptor<MealEntry>())
            let summaries = try modelContext.fetch(FetchDescriptor<DailySummary>())
            let records = try modelContext.fetch(FetchDescriptor<MedicalRecordEntry>())

            let payload = AppExportPayload(
                exportedAt: .now,
                meals: meals.map(MealExport.init),
                summaries: summaries.map(DailySummaryExport.init),
                medicalRecords: records.map(MedicalRecordExport.init)
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(payload)
            let filename = "meal-coach-export-\(Int(Date().timeIntervalSince1970)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            try data.write(to: url, options: [.atomic])
            exportURL = url
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteAllData() {
        do {
            try modelContext.fetch(FetchDescriptor<MealEntry>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<DailySummary>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<MedicalRecordEntry>()).forEach(modelContext.delete)

            FileStorage.deleteAllImages()

            try modelContext.save()
            exportURL = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppExportPayload: Codable {
    let exportedAt: Date
    let meals: [MealExport]
    let summaries: [DailySummaryExport]
    let medicalRecords: [MedicalRecordExport]
}

private struct MealExport: Codable {
    let id: UUID
    let dateTime: Date
    let mealType: String
    let photoFilename: String?
    let caloriesEstimate: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let notes: String
    let foods: [MealAnalysisFood]
    let dietFlags: [String]
    let allergenWarnings: [String]
    let createdFromRecommendation: Bool

    init(_ value: MealEntry) {
        id = value.id
        dateTime = value.dateTime
        mealType = value.mealTypeRaw
        photoFilename = value.photoFilename
        caloriesEstimate = value.caloriesEstimate
        proteinG = value.proteinG
        carbsG = value.carbsG
        fatG = value.fatG
        notes = value.notes
        foods = value.foods
        dietFlags = value.dietFlags
        allergenWarnings = value.allergenWarnings
        createdFromRecommendation = value.createdFromRecommendation
    }
}

private struct DailySummaryExport: Codable {
    let date: Date
    let mealCount: Int
    let caloriesTotalEstimate: Double
    let proteinTotalG: Double
    let carbsTotalG: Double
    let fatTotalG: Double
    let note: String
    let healthSnapshot: HealthSnapshot?

    init(_ value: DailySummary) {
        date = value.date
        mealCount = value.mealCount
        caloriesTotalEstimate = value.caloriesTotalEstimate
        proteinTotalG = value.proteinTotalG
        carbsTotalG = value.carbsTotalG
        fatTotalG = value.fatTotalG
        note = value.note
        healthSnapshot = value.healthSnapshot
    }
}

private struct MedicalRecordExport: Codable {
    let id: UUID
    let dateUploaded: Date
    let photoFilename: String?
    let photoFilenames: [String]
    let rawText: String

    init(_ value: MedicalRecordEntry) {
        id = value.id
        dateUploaded = value.dateUploaded
        photoFilename = value.photoFilename
        photoFilenames = value.photoFilenames
        rawText = value.rawText
    }
}
