import SwiftUI
import SwiftData

struct MedicalRecordDetailView: View {
    let record: MedicalRecordEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            MealCoachBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !record.photoFilenames.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(record.photoFilenames, id: \.self) { photoFilename in
                                if let image = FileStorage.loadImage(filename: photoFilename) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedText.ui("Saved: \(record.dateUploaded.formattedDateTime())", "保存时间：\(record.dateUploaded.formattedDateTime())"))
                            .font(.subheadline)
                            .foregroundStyle(MealCoachTheme.secondaryInk)

                        Text(record.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LocalizedText.ui("No description given.", "未提供描述。") : record.rawText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .mealCoachCard(tint: MealCoachTheme.teal)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(LocalizedText.ui("Health Status", "健康状态"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(LocalizedText.ui("Delete", "删除"), role: .destructive) {
                    showingDeleteAlert = true
                }
            }
        }
        .alert(LocalizedText.ui("Delete this entry?", "删除这条记录？"), isPresented: $showingDeleteAlert) {
            Button(LocalizedText.ui("Delete", "删除"), role: .destructive) {
                deleteRecord()
            }
            Button(LocalizedText.ui("Cancel", "取消"), role: .cancel) {}
        }
    }

    @MainActor
    private func deleteRecord() {
        for photoFilename in record.photoFilenames {
            FileStorage.deleteImage(filename: photoFilename)
        }
        modelContext.delete(record)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
