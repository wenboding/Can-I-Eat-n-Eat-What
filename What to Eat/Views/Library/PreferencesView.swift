import SwiftData
import SwiftUI

struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var preferences: UserPreferencesStore?

    @State private var dietStyle: DietStyle = .omnivore
    @State private var dietTarget: DietTarget = .maintainHealth
    @State private var allergiesText = ""
    @State private var cuisinesText = ""
    @State private var dislikesText = ""
    @State private var budgetLevel: BudgetLevel = .medium
    @State private var radiusMiles: Double = 3

    @State private var errorMessage: String?
    @State private var saveSuccessShown = false
    @State private var saveResetTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            MealCoachBackground()

            Form {
                Section {
                    Picker("Diet Style", selection: $dietStyle) {
                        ForEach(DietStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Picker("Diet Target", selection: $dietTarget) {
                        ForEach(DietTarget.allCases) { target in
                            Text(target.displayName).tag(target)
                        }
                    }

                    if dietTarget == .loseWeight {
                        Text(
                            LocalizedText.ui(
                                "Lose weight target = about a 200-300 kcal daily deficit, combined with exercise and adjusted for age/body weight/activity.",
                                "减脂目标 = 每日约 200-300 千卡热量缺口，并结合运动，同时按年龄/体重/活动量调整。"
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(MealCoachTheme.secondaryInk)
                    }

                    Picker("Budget", selection: $budgetLevel) {
                        ForEach(BudgetLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text(
                            LocalizedText.ui(
                                "Search Radius: \(String(format: "%.1f", radiusMiles)) mi",
                                "搜索半径：\(String(format: "%.1f", radiusMiles)) 英里"
                            )
                        )
                        Slider(value: $radiusMiles, in: 1...10, step: 0.5)
                            .tint(MealCoachTheme.coral)
                    }
                } header: {
                    sectionHeader("Diet")
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    TextField("Allergies (comma separated)", text: $allergiesText)
                        .textInputAutocapitalization(.never)
                    TextField("Favorite cuisines (comma separated)", text: $cuisinesText)
                    TextField("Dislikes (comma separated)", text: $dislikesText)
                } header: {
                    sectionHeader("Food Preferences")
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Button {
                        savePreferences()
                    } label: {
                        Label(
                            saveSuccessShown ? LocalizedText.ui("Saved", "已保存") : LocalizedText.ui("Save Preferences", "保存偏好"),
                            systemImage: saveSuccessShown ? "checkmark.circle.fill" : "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(
                        MealCoachPrimaryButtonStyle(
                            startColor: saveSuccessShown ? MealCoachTheme.teal : MealCoachTheme.navy,
                            endColor: saveSuccessShown ? MealCoachTheme.navy : MealCoachTheme.coral
                        )
                    )
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                if saveSuccessShown {
                    Section {
                        Label("Preferences saved successfully.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
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
            }
            .foregroundStyle(MealCoachTheme.ink)
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Preferences")
        .task {
            loadPreferences()
        }
        .onDisappear {
            saveResetTask?.cancel()
        }
    }

    @MainActor
    private func loadPreferences() {
        do {
            let value = try UserPreferencesStore.fetchOrCreate(in: modelContext)
            preferences = value

            dietStyle = value.dietStyle
            dietTarget = value.dietTarget
            allergiesText = value.allergiesCSV
            cuisinesText = value.favoriteCuisinesCSV
            dislikesText = value.dislikesCSV
            budgetLevel = value.budgetLevel
            radiusMiles = value.radiusMiles
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func savePreferences() {
        do {
            let value = try UserPreferencesStore.fetchOrCreate(in: modelContext)
            preferences = value

            value.dietStyle = dietStyle
            value.dietTarget = dietTarget
            value.allergiesCSV = allergiesText
            value.favoriteCuisinesCSV = cuisinesText
            value.dislikesCSV = dislikesText
            value.budgetLevel = budgetLevel
            value.radiusMiles = radiusMiles

            try modelContext.save()
            errorMessage = nil
            triggerSaveSuccessFeedback()
        } catch {
            errorMessage = error.localizedDescription
            saveSuccessShown = false
        }
    }

    private func triggerSaveSuccessFeedback() {
        saveResetTask?.cancel()
        saveSuccessShown = true

        saveResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.25)) {
                saveSuccessShown = false
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(MealCoachTheme.ink)
            .textCase(nil)
    }
}
