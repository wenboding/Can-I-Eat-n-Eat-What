import SwiftUI

struct LanguageSettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageCode = AppLanguage.english.rawValue

    var body: some View {
        ZStack {
            MealCoachBackground()

            Form {
                Section("App Language") {
                    Picker("Language", selection: $appLanguageCode) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Text("This controls both UI text and AI response language.")
                        .font(.footnote)
                        .foregroundStyle(MealCoachTheme.secondaryInk)
                }
                .listRowBackground(MealCoachTheme.listRowBackground)
            }
            .foregroundStyle(MealCoachTheme.ink)
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Language")
    }
}
