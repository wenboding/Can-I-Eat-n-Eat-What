import Foundation

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var displayName: String {
        switch AppLanguage.current {
        case .english:
            switch self {
            case .breakfast: return "Breakfast"
            case .lunch: return "Lunch"
            case .dinner: return "Dinner"
            case .snack: return "Snack"
            }
        case .simplifiedChinese:
            switch self {
            case .breakfast: return "早餐"
            case .lunch: return "午餐"
            case .dinner: return "晚餐"
            case .snack: return "加餐"
            }
        }
    }

    var dailyPhotoUploadQuota: Int {
        switch self {
        case .breakfast, .lunch, .dinner:
            return 1
        case .snack:
            return 4
        }
    }
}

enum DietStyle: String, Codable, CaseIterable, Identifiable {
    case omnivore
    case vegetarian
    case vegan
    case keto
    case paleo
    case halal
    case kosher

    var id: String { rawValue }

    var displayName: String {
        switch AppLanguage.current {
        case .english:
            switch self {
            case .omnivore: return "Omnivore"
            case .vegetarian: return "Vegetarian"
            case .vegan: return "Vegan"
            case .keto: return "Keto"
            case .paleo: return "Paleo"
            case .halal: return "Halal"
            case .kosher: return "Kosher"
            }
        case .simplifiedChinese:
            switch self {
            case .omnivore: return "杂食"
            case .vegetarian: return "素食"
            case .vegan: return "纯素"
            case .keto: return "生酮"
            case .paleo: return "原始饮食"
            case .halal: return "清真"
            case .kosher: return "犹太洁食"
            }
        }
    }
}

enum DietTarget: String, Codable, CaseIterable, Identifiable {
    case loseWeight = "lose_weight"
    case maintainHealth = "maintain_health"
    case gainMuscle = "gain_muscle"

    var id: String { rawValue }

    var displayName: String {
        switch AppLanguage.current {
        case .english:
            switch self {
            case .loseWeight: return "Lose Weight"
            case .maintainHealth: return "Maintain Health"
            case .gainMuscle: return "Gain Muscle"
            }
        case .simplifiedChinese:
            switch self {
            case .loseWeight: return "减脂"
            case .maintainHealth: return "保持健康"
            case .gainMuscle: return "增肌"
            }
        }
    }

    // Shared wording for model prompts.
    var aiGuidance: String {
        switch self {
        case .loseWeight:
            return "Target: lose_weight. Plan for an overall daily 200-300 kcal deficit while preserving protein and supporting exercise recovery. Consider age, body weight, activity, and recent meals when estimating portions and calories."
        case .maintainHealth:
            return "Target: maintain_health. Aim for balanced nutrition, stable energy, and sustainable portions with no aggressive calorie surplus or deficit."
        case .gainMuscle:
            return "Target: gain_muscle. Prioritize adequate protein, nutrient timing around activity, and a modest calorie surplus for training support."
        }
    }
}

enum BudgetLevel: String, Codable, CaseIterable, Identifiable {
    case cheap
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch AppLanguage.current {
        case .english:
            switch self {
            case .cheap: return "Cheap"
            case .medium: return "Medium"
            case .high: return "High"
            }
        case .simplifiedChinese:
            switch self {
            case .cheap: return "低预算"
            case .medium: return "中预算"
            case .high: return "高预算"
            }
        }
    }
}

struct MacroEstimate: Codable, Hashable {
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    enum CodingKeys: String, CodingKey {
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    static let zero = MacroEstimate(proteinG: 0, carbsG: 0, fatG: 0)
}

struct MealAnalysisFood: Codable, Hashable {
    let name: String
    let portion: String
    let confidence: Double
}

struct MealAnalysis: Codable, Hashable {
    var foods: [MealAnalysisFood]
    var caloriesEstimate: Double
    var macrosEstimate: MacroEstimate
    var dietFlags: [String]
    var allergenWarnings: [String]
    var notes: String

    enum CodingKeys: String, CodingKey {
        case foods
        case caloriesEstimate = "calories_estimate"
        case macrosEstimate = "macros_estimate"
        case dietFlags = "diet_flags"
        case allergenWarnings = "allergen_warnings"
        case notes
    }
}

struct MedicalTranscript: Codable, Hashable {
    let rawText: String

    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
    }
}

struct RecommendedMeal: Codable, Hashable {
    let title: String
    let why: String
    let nutritionFocus: [String]
    let suggestedIngredients: [String]
    let estimatedMacros: MacroEstimate
    let estimatedCalories: Double

    enum CodingKeys: String, CodingKey {
        case title
        case why
        case nutritionFocus = "nutrition_focus"
        case suggestedIngredients = "suggested_ingredients"
        case estimatedMacros = "estimated_macros"
        case estimatedCalories = "estimated_calories"
    }
}

struct NearbyOption: Codable, Hashable {
    let name: String
    let reason: String
    let distanceMiles: Double

    enum CodingKeys: String, CodingKey {
        case name
        case reason
        case distanceMiles = "distance_miles"
    }
}

struct RecommendationResponse: Codable, Hashable {
    let recommendedMeal: RecommendedMeal
    let nearbyOptions: [NearbyOption]

    enum CodingKeys: String, CodingKey {
        case recommendedMeal = "recommended_meal"
        case nearbyOptions = "nearby_options"
    }
}

struct RecentMealContext: Codable, Hashable {
    let date: Date
    let mealType: MealType
    let calories: Double
    let macros: MacroEstimate
    let notes: String
}

struct NearbyRestaurantContext: Codable, Hashable {
    let name: String
    let distanceMiles: Double
    let category: String
}

struct UserPreferencesPayload: Codable, Hashable {
    let dietStyle: DietStyle
    let dietTarget: DietTarget
    let allergies: [String]
    let favoriteCuisines: [String]
    let dislikes: [String]
    let budgetLevel: BudgetLevel
    let radiusMiles: Double
}

struct CurrentTimeContext: Codable, Hashable {
    let localDateTime: String
    let timezoneIdentifier: String
    let timezoneOffsetMinutes: Int
    let inferredMealType: MealType

    enum CodingKeys: String, CodingKey {
        case localDateTime = "local_date_time"
        case timezoneIdentifier = "timezone_identifier"
        case timezoneOffsetMinutes = "timezone_offset_minutes"
        case inferredMealType = "inferred_meal_type"
    }
}

struct TodayIntakeContext: Codable, Hashable {
    let mealCount: Int
    let totalCalories: Double

    enum CodingKeys: String, CodingKey {
        case mealCount = "meal_count"
        case totalCalories = "total_calories"
    }
}

struct RecommendationContext: Codable, Hashable {
    let generatedAt: Date
    let currentLocalTime: CurrentTimeContext
    let todayIntake: TodayIntakeContext
    let healthSnapshot: HealthSnapshot?
    let recentMeals: [RecentMealContext]
    let nearbyRestaurants: [NearbyRestaurantContext]
    let preferences: UserPreferencesPayload

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case currentLocalTime = "current_local_time"
        case todayIntake = "today_intake"
        case healthSnapshot = "health_snapshot"
        case recentMeals = "recent_meals"
        case nearbyRestaurants = "nearby_restaurants"
        case preferences
    }
}

struct NutritionTotals: Codable, Hashable {
    var calories: Double
    var macros: MacroEstimate

    static let zero = NutritionTotals(calories: 0, macros: .zero)
}
