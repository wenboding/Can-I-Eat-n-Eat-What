import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(AppLanguage.storageKey) private var appLanguageCode = AppLanguage.english.rawValue

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                TabView {
                    TodayTabView()
                        .tabItem {
                            Label("Today", systemImage: "sun.max")
                        }

                    LibraryTabView()
                        .tabItem {
                            Label("My Data", systemImage: "books.vertical")
                        }
                }
                .tint(MealCoachTheme.ink)
            } else {
                OnboardingFlowView()
            }
        }
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: appLanguageCode))
    }
}

#Preview {
    ContentView()
}
