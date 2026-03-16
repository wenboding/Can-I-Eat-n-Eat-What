import Foundation
import SwiftData

enum DailySummaryCalculator {
    private static let mainMealTypes: Set<MealType> = [.breakfast, .lunch, .dinner]

    static func aggregate(meals: [MealEntry]) -> NutritionTotals {
        let calories = meals.reduce(0) { $0 + $1.caloriesEstimate }
        let protein = meals.reduce(0) { $0 + $1.proteinG }
        let carbs = meals.reduce(0) { $0 + $1.carbsG }
        let fat = meals.reduce(0) { $0 + $1.fatG }

        return NutritionTotals(
            calories: calories,
            macros: MacroEstimate(proteinG: protein, carbsG: carbs, fatG: fat)
        )
    }

    @MainActor
    static func recomputeSummary(
        for date: Date,
        context: ModelContext,
        healthSnapshot: HealthSnapshot? = nil
    ) throws {
        let dayStart = date.startOfDay
        let dayEnd = dayStart.endOfDay

        let mealsDescriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate {
                $0.dateTime >= dayStart && $0.dateTime < dayEnd
            }
        )
        let meals = try context.fetch(mealsDescriptor)
        let totals = aggregate(meals: meals)
        let mainMealsLoggedCount = Set(meals.map(\.mealType)).intersection(mainMealTypes).count

        let summaryDescriptor = FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.date == dayStart }
        )

        let summary = try context.fetch(summaryDescriptor).first ?? {
            let value = DailySummary(date: dayStart)
            context.insert(value)
            return value
        }()

        summary.mealCount = meals.count
        summary.mainMealsLoggedCount = mainMealsLoggedCount
        summary.caloriesTotalEstimate = totals.calories
        summary.proteinTotalG = totals.macros.proteinG
        summary.carbsTotalG = totals.macros.carbsG
        summary.fatTotalG = totals.macros.fatG

        if let healthSnapshot {
            summary.healthSnapshot = healthSnapshot
            summary.activeEnergyKcal = healthSnapshot.activeEnergyKcal
            summary.restingEnergyKcal = healthSnapshot.restingEnergyKcal
        } else if let existingSnapshot = summary.healthSnapshot {
            summary.activeEnergyKcal = existingSnapshot.activeEnergyKcal
            summary.restingEnergyKcal = existingSnapshot.restingEnergyKcal
        }

        let hasIntakeData = summary.mealCount > 0 && summary.caloriesTotalEstimate > 0
        if hasIntakeData,
           let active = summary.activeEnergyKcal,
           let resting = summary.restingEnergyKcal {
            summary.netEnergyKcal = summary.caloriesTotalEstimate - (active + resting)
        } else {
            summary.netEnergyKcal = nil
        }

        try context.save()
    }

    @MainActor
    static func recomputeAll(context: ModelContext) throws {
        let mealDescriptor = FetchDescriptor<MealEntry>()
        let meals = try context.fetch(mealDescriptor)

        let grouped = Dictionary(grouping: meals) { $0.dateTime.startOfDay }

        let summaryDescriptor = FetchDescriptor<DailySummary>()
        let existingSummaries = try context.fetch(summaryDescriptor)

        for summary in existingSummaries where grouped[summary.date] == nil && summary.healthSnapshot == nil {
            context.delete(summary)
        }

        for (day, dayMeals) in grouped {
            let totals = aggregate(meals: dayMeals)
            let mainMealsLoggedCount = Set(dayMeals.map(\.mealType)).intersection(mainMealTypes).count
            let existing = existingSummaries.first { $0.date == day }
            let summary = existing ?? {
                let value = DailySummary(date: day)
                context.insert(value)
                return value
            }()

            summary.mealCount = dayMeals.count
            summary.mainMealsLoggedCount = mainMealsLoggedCount
            summary.caloriesTotalEstimate = totals.calories
            summary.proteinTotalG = totals.macros.proteinG
            summary.carbsTotalG = totals.macros.carbsG
            summary.fatTotalG = totals.macros.fatG

            if let snapshot = summary.healthSnapshot {
                summary.activeEnergyKcal = snapshot.activeEnergyKcal
                summary.restingEnergyKcal = snapshot.restingEnergyKcal
            }

            let hasIntakeData = summary.mealCount > 0 && summary.caloriesTotalEstimate > 0
            if hasIntakeData,
               let active = summary.activeEnergyKcal,
               let resting = summary.restingEnergyKcal {
                summary.netEnergyKcal = summary.caloriesTotalEstimate - (active + resting)
            } else {
                summary.netEnergyKcal = nil
            }
        }

        try context.save()
    }
}
