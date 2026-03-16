import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MealLogSheetView: View {
    let mealType: MealType
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var jpegData: Data?
    @State private var imageDataURL: String?
    @State private var showingCameraCapture = false

    @State private var analysis: MealAnalysis?
    @State private var isProcessingImage = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var photoUploadCountForMealType = 0
    @State private var didSaveEntry = false

    @State private var isEditing = false
    @State private var editedCalories = ""
    @State private var editedProtein = ""
    @State private var editedCarbs = ""
    @State private var editedFat = ""
    @State private var editedNotes = ""
    @State private var consumedShareTenths = 10.0
    @State private var extraMealContext = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MealCoachBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isUploadLockedForMealType {
                            Text(uploadLimitReachedMessage)
                            .font(.subheadline)
                            .foregroundStyle(MealCoachTheme.secondaryInk)
                            .mealCoachCard(tint: MealCoachTheme.coral)
                        }

                        Text(uploadUsageMessage)
                            .font(.footnote)
                            .foregroundStyle(MealCoachTheme.secondaryInk)

                        HStack(spacing: 10) {
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label(LocalizedText.ui("Photo Library", "从相册选择"), systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))
                            .disabled(isUploadLockedForMealType)

                            Button {
                                requestCameraAccessAndPresent()
                            } label: {
                                Label(LocalizedText.ui("Open Camera", "打开相机"), systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))
                            .disabled(isUploadLockedForMealType)
                        }

                        if isProcessingImage {
                            ProgressView("Processing image...")
                        }

                        if let selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white.opacity(0.75), lineWidth: 1)
                                }
                        }

                        if analysis == nil {
                            consumedPortionSection
                            extraContextSection
                        }

                        if analysis == nil {
                            Button("Analyze Meal") {
                                dismissKeyboard()
                                Task { await analyzeMeal() }
                            }
                            .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))
                            .disabled(!canAnalyzeMeal || isAnalyzing || isProcessingImage)
                        }

                        if isAnalyzing {
                            ProgressView(LocalizedText.ui("Analyzing with AI...", "正在使用 AI 分析..."))
                        }

                        if let analysis {
                            analysisResultView(analysis)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(LocalizedText.ui("Log \(mealType.displayName)", "记录\(mealType.displayName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task { await processImageSelection(newItem) }
            }
            .sheet(isPresented: $showingCameraCapture) {
                CameraCaptureView(
                    onImagePicked: { image in
                        Task { await processCapturedImage(image) }
                    },
                    onCancel: {}
                )
                .ignoresSafeArea()
            }
            .onDisappear {
                guard didSaveEntry else { return }
                onSaved()
            }
            .task {
                refreshDailyUploadLock()
            }
        }
    }

    @ViewBuilder
    private func analysisResultView(_ analysis: MealAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Analysis", systemImage: "text.badge.checkmark")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            ForEach(Array(analysis.foods.enumerated()), id: \.offset) { _, food in
                Text("• \(food.name) - \(food.portion) (conf: \(String(format: "%.2f", food.confidence)))")
                    .font(.subheadline)
            }

            Text(LocalizedText.ui("Calories: \(Int(currentCalories(from: analysis))) kcal", "热量：\(Int(currentCalories(from: analysis))) 千卡"))
                .font(.subheadline)
            Text(LocalizedText.ui("Protein: \(Int(currentProtein(from: analysis))) g", "蛋白质：\(Int(currentProtein(from: analysis))) 克"))
                .font(.subheadline)
            Text(LocalizedText.ui("Carbs: \(Int(currentCarbs(from: analysis))) g", "碳水：\(Int(currentCarbs(from: analysis))) 克"))
                .font(.subheadline)
            Text(LocalizedText.ui("Fat: \(Int(currentFat(from: analysis))) g", "脂肪：\(Int(currentFat(from: analysis))) 克"))
                .font(.subheadline)

            Text(LocalizedText.ui("Notes: \(currentNotes(from: analysis))", "备注：\(currentNotes(from: analysis))"))
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.secondaryInk)

            if isEditing {
                editSection(analysis)
            }

            HStack(spacing: 10) {
                Button(isEditing ? LocalizedText.ui("Cancel Edit", "取消编辑") : LocalizedText.ui("Edit", "编辑")) {
                    toggleEdit(analysis)
                }
                .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.navy))

                Button("Save") {
                    saveEntry(analysis)
                }
                .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))
            }
        }
        .mealCoachCard(tint: MealCoachTheme.teal)
    }

    private var consumedPortionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LocalizedText.ui("Consumed Portion", "食用比例"), systemImage: "chart.pie")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            HStack {
                Text(LocalizedText.ui("How much did you eat?", "你实际吃了多少？"))
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
                Spacer()
                Text(consumedShareLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MealCoachTheme.ink)
            }

            Slider(
                value: $consumedShareTenths,
                in: 1 ... 10,
                step: 1
            )
            .tint(MealCoachTheme.navy)
        }
        .mealCoachCard(tint: MealCoachTheme.navy)
    }

    private var extraContextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedText.ui("Extra Meal Info (Optional)", "补充信息（可选）"), systemImage: "square.and.pencil")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            TextField(
                LocalizedText.ui(
                    "Describe the meal if you have no photo, or add extra details about what you ate.",
                    "如果没有照片，请直接描述这餐；如果有照片，也可补充食用细节。"
                ),
                text: $extraMealContext,
                axis: .vertical
            )
            .lineLimit(3 ... 6)
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(MealCoachTheme.ink)
        }
        .mealCoachCard(tint: MealCoachTheme.coral)
    }

    @ViewBuilder
    private func editSection(_ analysis: MealAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Calories", text: $editedCalories)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Protein (g)", text: $editedProtein)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Carbs (g)", text: $editedCarbs)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Fat (g)", text: $editedFat)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Notes", text: $editedNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    @MainActor
    private func processImageSelection(_ item: PhotosPickerItem) async {
        guard !isUploadLockedForMealType else { return }

        isProcessingImage = true
        defer { isProcessingImage = false }

        do {
            guard let rawData = try await item.loadTransferable(type: Data.self) else {
                throw ImageProcessingError.loadFailed
            }
            try applyImageData(rawData)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func processCapturedImage(_ image: UIImage) async {
        guard !isUploadLockedForMealType else { return }

        isProcessingImage = true
        defer { isProcessingImage = false }

        do {
            guard let rawData = image.jpegData(compressionQuality: 0.9) else {
                throw ImageProcessingError.encodeFailed
            }
            try applyImageData(rawData)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func analyzeMeal() async {
        dismissKeyboard()
        refreshDailyUploadLock()
        guard canAnalyzeMeal else {
            errorMessage = LocalizedText.ui(
                "Add a meal photo or describe the meal first.",
                "请先添加餐食照片或输入餐食描述。"
            )
            return
        }

        guard !isUploadLockedForMealType || imageDataURL == nil else {
            errorMessage = uploadLimitReachedMessage
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let preferences = try UserPreferencesStore.fetchOrCreate(in: modelContext)
            let result = try await appContainer.llmClient.analyzeMeal(
                imageDataURL: imageDataURL,
                mealDescription: sanitizedMealDescription,
                consumptionShare: consumptionShare,
                extraContext: nil,
                dietTarget: preferences.dietTarget
            )
            analysis = result
            isEditing = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleEdit(_ analysis: MealAnalysis) {
        if isEditing {
            isEditing = false
            return
        }

        editedCalories = String(format: "%.0f", analysis.caloriesEstimate)
        editedProtein = String(format: "%.0f", analysis.macrosEstimate.proteinG)
        editedCarbs = String(format: "%.0f", analysis.macrosEstimate.carbsG)
        editedFat = String(format: "%.0f", analysis.macrosEstimate.fatG)
        editedNotes = analysis.notes
        isEditing = true
    }

    @MainActor
    private func saveEntry(_ analysis: MealAnalysis) {
        let calories = currentCalories(from: analysis)
        let protein = currentProtein(from: analysis)
        let carbs = currentCarbs(from: analysis)
        let fat = currentFat(from: analysis)
        let notes = currentNotes(from: analysis)

        do {
            let filename = try jpegData.map { try FileStorage.saveJPEGData($0, prefix: "meal") }

            let entry = MealEntry(
                mealType: mealType,
                photoFilename: filename,
                caloriesEstimate: calories,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                notes: notes,
                foods: analysis.foods,
                dietFlags: analysis.dietFlags,
                allergenWarnings: analysis.allergenWarnings,
                createdFromRecommendation: false
            )

            modelContext.insert(entry)
            try modelContext.save()
            try DailySummaryCalculator.recomputeSummary(for: Date(), context: modelContext)

            didSaveEntry = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyImageData(_ rawData: Data) throws {
        let processed = try ImageProcessing.processImageData(rawData, profile: .mealPhoto)
        selectedItem = nil
        selectedImage = processed.image
        jpegData = processed.jpegData
        imageDataURL = processed.dataURL
        analysis = nil
        isEditing = false
        errorMessage = nil
    }

    private func requestCameraAccessAndPresent() {
        guard !isUploadLockedForMealType else { return }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = LocalizedText.ui("Camera is unavailable on this device.", "此设备暂不支持相机。")
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showingCameraCapture = true
            errorMessage = nil
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        showingCameraCapture = true
                        errorMessage = nil
                    } else {
                        errorMessage = LocalizedText.ui(
                            "Camera access denied. Enable camera permission in Settings to take meal photos.",
                            "相机权限被拒绝。请在系统设置中开启相机权限后再拍摄餐食照片。"
                        )
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = LocalizedText.ui(
                "Camera access denied. Enable camera permission in Settings to take meal photos.",
                "相机权限被拒绝。请在系统设置中开启相机权限后再拍摄餐食照片。"
            )
        @unknown default:
            errorMessage = LocalizedText.ui("Unable to access camera right now.", "当前无法访问相机。")
        }
    }

    private func currentCalories(from analysis: MealAnalysis) -> Double {
        guard isEditing else { return analysis.caloriesEstimate }
        return Double(editedCalories) ?? analysis.caloriesEstimate
    }

    private func currentProtein(from analysis: MealAnalysis) -> Double {
        guard isEditing else { return analysis.macrosEstimate.proteinG }
        return Double(editedProtein) ?? analysis.macrosEstimate.proteinG
    }

    private func currentCarbs(from analysis: MealAnalysis) -> Double {
        guard isEditing else { return analysis.macrosEstimate.carbsG }
        return Double(editedCarbs) ?? analysis.macrosEstimate.carbsG
    }

    private func currentFat(from analysis: MealAnalysis) -> Double {
        guard isEditing else { return analysis.macrosEstimate.fatG }
        return Double(editedFat) ?? analysis.macrosEstimate.fatG
    }

    private func currentNotes(from analysis: MealAnalysis) -> String {
        guard isEditing else { return analysis.notes }
        return editedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? analysis.notes : editedNotes
    }

    private var consumptionShare: Double {
        max(0.1, min(1.0, consumedShareTenths / 10.0))
    }

    private var consumedShareLabel: String {
        let roundedTenths = Int(consumedShareTenths.rounded())
        return LocalizedText.ui(
            "\(roundedTenths)/10 (\(roundedTenths * 10)%)",
            "\(roundedTenths)/10（\(roundedTenths * 10)%）"
        )
    }

    private var sanitizedExtraContext: String? {
        let trimmed = extraMealContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(400))
    }

    private var sanitizedMealDescription: String? {
        sanitizedExtraContext
    }

    private var canAnalyzeMeal: Bool {
        imageDataURL != nil || sanitizedMealDescription != nil
    }

    @MainActor
    private func refreshDailyUploadLock() {
        let dayStart = Date().startOfDay
        let dayEnd = dayStart.endOfDay

        do {
            let descriptor = FetchDescriptor<MealEntry>(
                predicate: #Predicate {
                    $0.dateTime >= dayStart && $0.dateTime < dayEnd
                }
            )
            let todaysEntries = try modelContext.fetch(descriptor)
            photoUploadCountForMealType = todaysEntries.reduce(into: 0) { count, entry in
                if entry.photoFilename != nil && entry.mealType == mealType {
                    count += 1
                }
            }
        } catch {
            photoUploadCountForMealType = 0
            errorMessage = error.localizedDescription
        }
    }

    private var isUploadLockedForMealType: Bool {
        photoUploadCountForMealType >= mealType.dailyPhotoUploadQuota
    }

    private var uploadUsageMessage: String {
        LocalizedText.ui(
            "Today's \(mealType.displayName.lowercased()) uploads: \(photoUploadCountForMealType)/\(mealType.dailyPhotoUploadQuota)",
            "今天\(mealType.displayName)上传次数：\(photoUploadCountForMealType)/\(mealType.dailyPhotoUploadQuota)"
        )
    }

    private var uploadLimitReachedMessage: String {
        LocalizedText.ui(
            "Today's \(mealType.displayName.lowercased()) upload limit is reached (\(mealType.dailyPhotoUploadQuota)/\(mealType.dailyPhotoUploadQuota)).",
            "今天\(mealType.displayName)上传次数已达上限（\(mealType.dailyPhotoUploadQuota)/\(mealType.dailyPhotoUploadQuota)）。"
        )
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
