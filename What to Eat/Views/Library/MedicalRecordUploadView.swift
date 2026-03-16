import PhotosUI
import SwiftData
import SwiftUI

struct MedicalRecordUploadView: View {
    private static let maxReportImageCount = 3

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [SelectedMedicalImage] = []
    @State private var skipNextSelectionProcessing = false

    @State private var transcript: MedicalTranscript?
    @State private var customDescription = ""
    @State private var isProcessingImage = false
    @State private var isTranscribing = false
    @State private var errorMessage: String?
    @State private var healthStatusUploadCountToday = 0

    private let previewColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                MealCoachBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: Self.maxReportImageCount,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label(
                                LocalizedText.ui("Select up to 3 images", "最多选择 3 张图片"),
                                systemImage: "doc.text.viewfinder"
                            )
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))
                        .disabled(isUploadLockedForToday)

                        Text(uploadUsageMessage)
                            .font(.footnote)
                            .foregroundStyle(MealCoachTheme.secondaryInk)

                        Text(
                            LocalizedText.ui(
                                "Selected images: \(selectedImages.count)/\(Self.maxReportImageCount)",
                                "已选图片：\(selectedImages.count)/\(Self.maxReportImageCount)"
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(MealCoachTheme.secondaryInk)

                        if isUploadLockedForToday {
                            Text(uploadLimitReachedMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if isProcessingImage {
                            ProgressView(LocalizedText.ui("Processing images...", "正在处理图片..."))
                        }

                        if !selectedImages.isEmpty {
                            LazyVGrid(columns: previewColumns, spacing: 10) {
                                ForEach(selectedImages) { selectedImage in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImage.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(.white.opacity(0.75), lineWidth: 1)
                                            }

                                        Button {
                                            removeSelectedImage(id: selectedImage.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundStyle(.white, MealCoachTheme.coral)
                                                .padding(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Button(LocalizedText.ui("Analyze Report Text (Optional)", "识别报告文字（可选）")) {
                            Task { await transcribe() }
                        }
                        .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))
                        .disabled(selectedImages.isEmpty || isProcessingImage || isTranscribing || isUploadLockedForToday)

                        if isTranscribing {
                            ProgressView(LocalizedText.ui("Analyzing...", "分析中..."))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                LocalizedText.ui("Describe your health status", "描述你的健康状态"),
                                systemImage: "note.text"
                            )
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MealCoachTheme.ink)

                            TextEditor(text: $customDescription)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.white.opacity(0.7))
                                )
                        }
                        .mealCoachCard(tint: MealCoachTheme.navy)

                        Text(
                            LocalizedText.ui(
                                "You can save with text only, photo + text, or photo + analyzed report text.",
                                "你可以仅保存文字，或保存图片+文字，或保存图片+识别后的报告文字。"
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(MealCoachTheme.secondaryInk)

                        if let transcript {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    LocalizedText.ui("Extracted Report Text", "识别到的报告文字"),
                                    systemImage: "text.viewfinder"
                                )
                                .font(.system(.headline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MealCoachTheme.ink)
                                Text(transcript.rawText)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                            .mealCoachCard(tint: MealCoachTheme.teal)
                        }

                        Button(LocalizedText.ui("Save Health Description", "保存健康描述")) {
                            saveRecord()
                        }
                        .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))
                        .disabled(isProcessingImage || isTranscribing || isUploadLockedForToday)

                        Text(
                            LocalizedText.ui(
                                "Privacy claim: Your data is stored only on this phone. If you tap \"Analyze Report Text\", that image is sent to the selected model provider API for processing. Provider API data is not used by this app for training.",
                                "隐私声明：你的数据仅存储在本机。只有当你点击“识别报告文字”时，图片才会发送到当前选择的模型提供方 API 处理。本应用不会将这些数据用于训练。"
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(MealCoachTheme.secondaryInk)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white.opacity(0.62))
                        )

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
            .navigationTitle(LocalizedText.ui("Describe Your Health Status", "描述你的健康状态"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedText.ui("Close", "关闭")) {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedItems) { _, newValue in
                if skipNextSelectionProcessing {
                    skipNextSelectionProcessing = false
                    return
                }
                Task { await processSelections(newValue) }
            }
            .task {
                refreshDailyUploadLock()
            }
        }
    }

    @MainActor
    private func processSelections(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            selectedImages = []
            transcript = nil
            errorMessage = nil
            return
        }

        isProcessingImage = true
        defer { isProcessingImage = false }

        var processedImages: [SelectedMedicalImage] = []
        var failedCount = 0

        for item in items.prefix(Self.maxReportImageCount) {
            do {
                guard let rawData = try await item.loadTransferable(type: Data.self) else {
                    throw ImageProcessingError.loadFailed
                }
                let processed = try ImageProcessing.processImageData(rawData, profile: .healthReport)
                let selectedImage = SelectedMedicalImage(
                    image: processed.image,
                    jpegData: processed.jpegData,
                    dataURL: processed.dataURL
                )
                processedImages.append(selectedImage)
            } catch {
                failedCount += 1
            }
        }

        guard !processedImages.isEmpty else {
            errorMessage = LocalizedText.ui(
                "Unable to load the selected images. Please try again.",
                "无法加载所选图片，请重试。"
            )
            return
        }

        selectedImages = processedImages
        transcript = nil
        if failedCount > 0 {
            errorMessage = LocalizedText.ui(
                "\(failedCount) image(s) could not be processed.",
                "有 \(failedCount) 张图片处理失败。"
            )
        } else {
            errorMessage = nil
        }
    }

    @MainActor
    private func transcribe() async {
        guard !selectedImages.isEmpty else {
            errorMessage = LocalizedText.ui("Please select at least one report image first.", "请先选择至少一张图片。")
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let result = try await appContainer.llmClient.transcribeMedical(
                imageDataURLs: selectedImages.map(\.dataURL)
            )
            let combinedTranscript = result.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combinedTranscript.isEmpty else {
                errorMessage = LocalizedText.ui("No text was detected in the selected images.", "所选图片中未识别到文字。")
                return
            }

            transcript = MedicalTranscript(rawText: combinedTranscript)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveRecord() {
        refreshDailyUploadLock()
        guard !isUploadLockedForToday else {
            errorMessage = uploadLimitReachedMessage
            return
        }

        guard let recordText = composedRecordText else {
            errorMessage = LocalizedText.ui(
                "Please enter a health description, or analyze report text from an image before saving.",
                "请先输入健康描述，或先从图片识别报告文字后再保存。"
            )
            return
        }

        do {
            var photoFilenames: [String] = []
            for selectedImage in selectedImages {
                let filename = try FileStorage.saveJPEGData(selectedImage.jpegData, prefix: "health")
                photoFilenames.append(filename)
            }

            let entry = MedicalRecordEntry(rawText: recordText)
            entry.photoFilenames = photoFilenames
            modelContext.insert(entry)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshDailyUploadLock() {
        let dayStart = Date().startOfDay
        let dayEnd = dayStart.endOfDay

        do {
            let descriptor = FetchDescriptor<MedicalRecordEntry>(
                predicate: #Predicate {
                    $0.dateUploaded >= dayStart && $0.dateUploaded < dayEnd
                }
            )
            healthStatusUploadCountToday = try modelContext.fetch(descriptor).count
        } catch {
            healthStatusUploadCountToday = 0
            errorMessage = error.localizedDescription
        }
    }

    private var isUploadLockedForToday: Bool {
        healthStatusUploadCountToday >= 1
    }

    private var uploadUsageMessage: String {
        LocalizedText.ui(
            "Today's health status uploads: \(healthStatusUploadCountToday)/1",
            "今天健康状态上传次数：\(healthStatusUploadCountToday)/1"
        )
    }

    private var uploadLimitReachedMessage: String {
        LocalizedText.ui(
            "Today's health status upload limit is reached (1/1).",
            "今天健康状态上传次数已达上限（1/1）。"
        )
    }

    private var composedRecordText: String? {
        let trimmedCustomDescription = customDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranscript = transcript?.rawText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedCustomDescription.isEmpty && !trimmedTranscript.isEmpty {
            return "\(trimmedCustomDescription)\n\n\(trimmedTranscript)"
        }
        if !trimmedCustomDescription.isEmpty {
            return trimmedCustomDescription
        }
        if !trimmedTranscript.isEmpty {
            return trimmedTranscript
        }
        return nil
    }

    @MainActor
    private func removeSelectedImage(id: UUID) {
        guard let index = selectedImages.firstIndex(where: { $0.id == id }) else { return }
        selectedImages.remove(at: index)
        if index < selectedItems.count {
            skipNextSelectionProcessing = true
            selectedItems.remove(at: index)
        }
        transcript = nil
        errorMessage = nil
    }
}

private struct SelectedMedicalImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpegData: Data
    let dataURL: String
}
