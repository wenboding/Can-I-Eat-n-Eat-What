import Foundation

enum StreakCalculator {
    static func isEffectiveDay(summary: DailySummary?) -> Bool {
        (summary?.mealCount ?? 0) >= 1
    }

    static func isEffectiveDay(meals: [MealEntry]) -> Bool {
        !meals.isEmpty
    }

    static func isEffectiveDay(progressDay: ProgressDay) -> Bool {
        progressDay.mealCount >= 1
    }

    static func completionTier(mainMealsLoggedCount: Int, hasAnyMeal: Bool) -> CompletionTier {
        if mainMealsLoggedCount >= 3 { return .gold }
        if mainMealsLoggedCount == 2 { return .silver }
        if mainMealsLoggedCount == 1 || hasAnyMeal { return .bronze }
        return .none
    }

    static func currentStreak(summariesByDay: [Date: DailySummary], today: Date) -> Int {
        let todayStart = today.startOfDay
        let startDay: Date

        if isEffectiveDay(summary: summariesByDay[todayStart]) {
            startDay = todayStart
        } else {
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: todayStart)?.startOfDay else {
                return 0
            }
            startDay = yesterday
        }

        var streak = 0
        var cursor = startDay

        while true {
            let summary = summariesByDay[cursor]
            guard isEffectiveDay(summary: summary) else { break }
            streak += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous.startOfDay
        }

        return streak
    }

    static func currentStreak(progressDays: [ProgressDay], today: Date) -> Int {
        let dayMap = Dictionary(uniqueKeysWithValues: progressDays.map { ($0.date.startOfDay, $0) })
        let todayStart = today.startOfDay
        let startDay: Date

        if let todayDay = dayMap[todayStart], isEffectiveDay(progressDay: todayDay) {
            startDay = todayStart
        } else {
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: todayStart)?.startOfDay else {
                return 0
            }
            startDay = yesterday
        }

        var streak = 0
        var cursor = startDay

        while true {
            guard let day = dayMap[cursor], isEffectiveDay(progressDay: day) else { break }
            streak += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous.startOfDay
        }

        return streak
    }
}
