import Foundation

enum CompletionTier: String, Codable, CaseIterable {
    case none
    case bronze
    case silver
    case gold

    var displayName: String {
        switch self {
        case .none:
            return LocalizedText.ui("None", "无")
        case .bronze:
            return LocalizedText.ui("Bronze", "铜")
        case .silver:
            return LocalizedText.ui("Silver", "银")
        case .gold:
            return LocalizedText.ui("Gold", "金")
        }
    }
}

struct ProgressDay: Hashable {
    let date: Date
    let mealCount: Int
    let mainMealsLoggedCount: Int
    let intakeKcal: Double
    let activeEnergyKcal: Double?
    let restingEnergyKcal: Double?
    let netKcal: Double?
    let sleepHours: Double?
    let stepCount: Double?
    let tier: CompletionTier

    var hasAnyMeal: Bool {
        mealCount > 0
    }

    var hasIntakeData: Bool {
        mealCount > 0 && intakeKcal > 0
    }
}
