import Combine
import Foundation
import SwiftData

@MainActor
final class TodayProgressViewModel: ObservableObject {
    @Published private(set) var progressDays: [ProgressDay] = []
    @Published private(set) var recentSevenDays: [ProgressDay] = []
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var yesterdaySummaryText: String = ""
    @Published private(set) var yesterdayHintText: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func loadRecentProgress(context: ModelContext, healthKitManager: HealthKitManager) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await backfillRecentSnapshotsIfNeeded(
                context: context,
                healthKitManager: healthKitManager
            )

            let today = Date().startOfDay
            let start = Calendar.current.date(byAdding: .day, value: -13, to: today)?.startOfDay ?? today
            let summaries = try fetchSummaries(from: start, to: today.endOfDay, context: context)
            let summaryByDay = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date.startOfDay, $0) })

            var days: [ProgressDay] = []
            for offset in stride(from: 13, through: 0, by: -1) {
                let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)?.startOfDay ?? today
                let summary = summaryByDay[day]
                days.append(buildProgressDay(for: day, summary: summary))
            }

            let effectiveSummaries = try fetchEffectiveSummaries(upTo: today.endOfDay, context: context)
            let effectiveByDay = Dictionary(uniqueKeysWithValues: effectiveSummaries.map { ($0.date.startOfDay, $0) })

            progressDays = days
            recentSevenDays = Array(days.suffix(7))
            currentStreak = StreakCalculator.currentStreak(summariesByDay: effectiveByDay, today: today)
            updateYesterdaySummary(today: today)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchSummaries(from start: Date, to end: Date, context: ModelContext) throws -> [DailySummary] {
        let descriptor = FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\DailySummary.date, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchEffectiveSummaries(upTo end: Date, context: ModelContext) throws -> [DailySummary] {
        let descriptor = FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.date < end && $0.mealCount > 0 }
        )
        return try context.fetch(descriptor)
    }

    private func buildProgressDay(for day: Date, summary: DailySummary?) -> ProgressDay {
        let mealCount = summary?.mealCount ?? 0
        let mainMealsLoggedCount = summary?.mainMealsLoggedCount ?? 0
        let intake = summary?.caloriesTotalEstimate ?? 0

        let snapshot = summary?.healthSnapshot
        let active = summary?.activeEnergyKcal ?? snapshot?.activeEnergyKcal
        let resting = summary?.restingEnergyKcal ?? snapshot?.restingEnergyKcal
        let hasIntakeData = mealCount > 0 && intake > 0
        let net: Double? = {
            guard hasIntakeData else { return nil }
            if let cached = summary?.netEnergyKcal { return cached }
            guard let active, let resting else { return nil }
            return intake - (active + resting)
        }()

        return ProgressDay(
            date: day.startOfDay,
            mealCount: mealCount,
            mainMealsLoggedCount: mainMealsLoggedCount,
            intakeKcal: intake,
            activeEnergyKcal: active,
            restingEnergyKcal: resting,
            netKcal: net,
            sleepHours: snapshot?.sleepHours,
            stepCount: snapshot?.stepCount,
            tier: StreakCalculator.completionTier(
                mainMealsLoggedCount: mainMealsLoggedCount,
                hasAnyMeal: mealCount > 0
            )
        )
    }

    private func updateYesterdaySummary(today: Date) {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)?.startOfDay,
              let day = progressDays.first(where: { $0.date == yesterday }) else {
            yesterdaySummaryText = LocalizedText.ui("Yesterday: no data.", "昨天：暂无数据。")
            yesterdayHintText = LocalizedText.ui("Log at least one meal today to keep your streak.", "今天至少记录一餐以保持连续打卡。")
            return
        }

        var components: [String] = [
            LocalizedText.ui(
                "Meals \(day.mealCount)",
                "餐次 \(day.mealCount)"
            ),
            LocalizedText.ui(
                "Calories \(Int(day.intakeKcal))",
                "热量 \(Int(day.intakeKcal))"
            )
        ]

        if let net = day.netKcal {
            components.append(
                LocalizedText.ui(
                    "Net \(Int(net)) kcal",
                    "净值 \(Int(net)) 千卡"
                )
            )
        }

        if let sleep = day.sleepHours {
            components.append(
                LocalizedText.ui(
                    "Sleep \(String(format: "%.1f", sleep)) h",
                    "睡眠 \(String(format: "%.1f", sleep)) 小时"
                )
            )
        }

        if let steps = day.stepCount {
            components.append(
                LocalizedText.ui(
                    "Steps \(Int(steps))",
                    "步数 \(Int(steps))"
                )
            )
        }

        yesterdaySummaryText = LocalizedText.ui("Yesterday: ", "昨天：") + components.joined(separator: " • ")

        if day.mealCount == 0 {
            yesterdayHintText = LocalizedText.ui(
                "Hint: No meals logged yesterday. One meal is enough to keep the streak alive.",
                "提示：昨天未记录餐食。每天至少一餐即可保持连续打卡。"
            )
        } else if day.mainMealsLoggedCount <= 1 {
            yesterdayHintText = LocalizedText.ui(
                "Hint: Try logging at least two main meals for better trend quality.",
                "提示：尽量记录至少两顿正餐，以提升趋势参考价值。"
            )
        } else {
            yesterdayHintText = nil
        }
    }

    private func backfillRecentSnapshotsIfNeeded(
        context: ModelContext,
        healthKitManager: HealthKitManager
    ) async throws {
        guard healthKitManager.permissionState == .authorized else { return }

        let today = Date().startOfDay
        let windowStart = Calendar.current.date(byAdding: .day, value: -7, to: today)?.startOfDay ?? today
        let summaries = try fetchSummaries(from: windowStart, to: today, context: context)
        let summaryByDay = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date.startOfDay, $0) })

        for offset in stride(from: 7, through: 1, by: -1) {
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)?.startOfDay else { continue }
            let summary = summaryByDay[day]
            let active = summary?.activeEnergyKcal ?? summary?.healthSnapshot?.activeEnergyKcal
            let resting = summary?.restingEnergyKcal ?? summary?.healthSnapshot?.restingEnergyKcal
            guard active == nil || resting == nil else { continue }

            do {
                let snapshot = try await healthKitManager.fetchSnapshot(for: day)
                try DailySummaryCalculator.recomputeSummary(
                    for: day,
                    context: context,
                    healthSnapshot: snapshot
                )
            } catch {
                // Best effort backfill; ignore individual day failures.
            }
        }
    }
}
