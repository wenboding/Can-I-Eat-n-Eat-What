import SwiftUI
import UIKit

struct PermissionBanner: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(MealCoachTheme.secondaryInk)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
        }
        .mealCoachCard(tint: MealCoachTheme.amber)
    }
}
