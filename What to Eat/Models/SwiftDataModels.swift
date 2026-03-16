import Foundation
import SwiftData

@Model
final class MealEntry {
    @Attribute(.unique) var id: UUID
    var dateTime: Date
    var mealTypeRaw: String
    var photoFilename: String?

    var caloriesEstimate: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    var notes: String
    var foodsData: Data?
    var dietFlagsData: Data?
    var allergenWarningsData: Data?
    var createdFromRecommendation: Bool

    init(
        id: UUID = UUID(),
        dateTime: Date = .now,
        mealType: MealType,
        photoFilename: String? = nil,
        caloriesEstimate: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        notes: String,
        foods: [MealAnalysisFood] = [],
        dietFlags: [String] = [],
        allergenWarnings: [String] = [],
        createdFromRecommendation: Bool = false
    ) {
        self.id = id
        self.dateTime = dateTime
        self.mealTypeRaw = mealType.rawValue
        self.photoFilename = photoFilename
        self.caloriesEstimate = caloriesEstimate
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.notes = notes
        self.foodsData = CodableBlob.encode(foods)
        self.dietFlagsData = CodableBlob.encode(dietFlags)
        self.allergenWarningsData = CodableBlob.encode(allergenWarnings)
        self.createdFromRecommendation = createdFromRecommendation
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .dinner }
        set { mealTypeRaw = newValue.rawValue }
    }

    var foods: [MealAnalysisFood] {
        get { CodableBlob.decode(foodsData) ?? [] }
        set { foodsData = CodableBlob.encode(newValue) }
    }

    var dietFlags: [String] {
        get { CodableBlob.decode(dietFlagsData) ?? [] }
        set { dietFlagsData = CodableBlob.encode(newValue) }
    }

    var allergenWarnings: [String] {
        get { CodableBlob.decode(allergenWarningsData) ?? [] }
        set { allergenWarningsData = CodableBlob.encode(newValue) }
    }

    var macroEstimate: MacroEstimate {
        MacroEstimate(proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}

@Model
final class DailySummary {
    @Attribute(.unique) var date: Date
    var mealCount: Int = 0
    var mainMealsLoggedCount: Int = 0
    var caloriesTotalEstimate: Double = 0
    var proteinTotalG: Double = 0
    var carbsTotalG: Double = 0
    var fatTotalG: Double = 0
    var activeEnergyKcal: Double?
    var restingEnergyKcal: Double?
    var netEnergyKcal: Double?
    var note: String = ""
    var healthSnapshotData: Data?

    init(
        date: Date,
        mealCount: Int = 0,
        mainMealsLoggedCount: Int = 0,
        caloriesTotalEstimate: Double = 0,
        proteinTotalG: Double = 0,
        carbsTotalG: Double = 0,
        fatTotalG: Double = 0,
        activeEnergyKcal: Double? = nil,
        restingEnergyKcal: Double? = nil,
        netEnergyKcal: Double? = nil,
        note: String = "",
        healthSnapshot: HealthSnapshot? = nil
    ) {
        self.date = date.startOfDay
        self.mealCount = mealCount
        self.mainMealsLoggedCount = mainMealsLoggedCount
        self.caloriesTotalEstimate = caloriesTotalEstimate
        self.proteinTotalG = proteinTotalG
        self.carbsTotalG = carbsTotalG
        self.fatTotalG = fatTotalG
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.netEnergyKcal = netEnergyKcal
        self.note = note
        self.healthSnapshotData = CodableBlob.encode(healthSnapshot)
    }

    var healthSnapshot: HealthSnapshot? {
        get { CodableBlob.decode(healthSnapshotData) }
        set { healthSnapshotData = CodableBlob.encode(newValue) }
    }
}

@Model
final class MedicalRecordEntry {
    @Attribute(.unique) var id: UUID
    var dateUploaded: Date
    var photoFilename: String?
    var rawText: String

    init(
        id: UUID = UUID(),
        dateUploaded: Date = .now,
        photoFilename: String? = nil,
        rawText: String
    ) {
        self.id = id
        self.dateUploaded = dateUploaded
        self.photoFilename = photoFilename
        self.rawText = rawText
    }

    var photoFilenames: [String] {
        get { Self.decodePhotoFilenames(from: photoFilename) }
        set { photoFilename = Self.encodePhotoFilenames(newValue) }
    }

    static func encodePhotoFilenames(_ filenames: [String]) -> String? {
        let cleaned = filenames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return nil }
        if cleaned.count == 1 {
            return cleaned[0]
        }

        guard
            let data = try? JSONEncoder().encode(cleaned),
            let encoded = String(data: data, encoding: .utf8)
        else {
            return cleaned[0]
        }
        return encoded
    }

    static func decodePhotoFilenames(from storedValue: String?) -> [String] {
        guard let storedValue else { return [] }
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return [trimmed]
    }
}

@Model
final class UserPreferencesStore {
    @Attribute(.unique) var singletonKey: String

    var dietStyleRaw: String
    var dietTargetRaw: String?
    var allergiesCSV: String
    var favoriteCuisinesCSV: String
    var dislikesCSV: String
    var budgetLevelRaw: String
    var radiusMiles: Double

    init(
        singletonKey: String = "default",
        dietStyle: DietStyle = .omnivore,
        dietTarget: DietTarget = .maintainHealth,
        allergies: [String] = [],
        favoriteCuisines: [String] = [],
        dislikes: [String] = [],
        budgetLevel: BudgetLevel = .medium,
        radiusMiles: Double = 3
    ) {
        self.singletonKey = singletonKey
        self.dietStyleRaw = dietStyle.rawValue
        self.dietTargetRaw = dietTarget.rawValue
        self.allergiesCSV = allergies.joined(separator: ", ")
        self.favoriteCuisinesCSV = favoriteCuisines.joined(separator: ", ")
        self.dislikesCSV = dislikes.joined(separator: ", ")
        self.budgetLevelRaw = budgetLevel.rawValue
        self.radiusMiles = radiusMiles
    }

    var dietStyle: DietStyle {
        get { DietStyle(rawValue: dietStyleRaw) ?? .omnivore }
        set { dietStyleRaw = newValue.rawValue }
    }

    var dietTarget: DietTarget {
        get { DietTarget(rawValue: dietTargetRaw ?? "") ?? .maintainHealth }
        set { dietTargetRaw = newValue.rawValue }
    }

    var budgetLevel: BudgetLevel {
        get { BudgetLevel(rawValue: budgetLevelRaw) ?? .medium }
        set { budgetLevelRaw = newValue.rawValue }
    }

    var allergies: [String] {
        get { allergiesCSV.asList }
        set { allergiesCSV = newValue.joined(separator: ", ") }
    }

    var favoriteCuisines: [String] {
        get { favoriteCuisinesCSV.asList }
        set { favoriteCuisinesCSV = newValue.joined(separator: ", ") }
    }

    var dislikes: [String] {
        get { dislikesCSV.asList }
        set { dislikesCSV = newValue.joined(separator: ", ") }
    }

    func toPayload() -> UserPreferencesPayload {
        UserPreferencesPayload(
            dietStyle: dietStyle,
            dietTarget: dietTarget,
            allergies: allergies,
            favoriteCuisines: favoriteCuisines,
            dislikes: dislikes,
            budgetLevel: budgetLevel,
            radiusMiles: radiusMiles
        )
    }
}

extension UserPreferencesStore {
    static func fetchOrCreate(in context: ModelContext) throws -> UserPreferencesStore {
        let descriptor = FetchDescriptor<UserPreferencesStore>(
            predicate: #Predicate { $0.singletonKey == "default" }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let created = UserPreferencesStore()
        context.insert(created)
        try context.save()
        return created
    }
}

private extension String {
    var asList: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
