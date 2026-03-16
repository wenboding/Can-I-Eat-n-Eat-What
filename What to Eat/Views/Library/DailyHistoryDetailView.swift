import SwiftData
import SwiftUI

struct DailyHistoryDetailView: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext

    @State private var summary: DailySummary?
    @State private var meals: [MealEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            MealCoachBackground()

            List {
                Section {
                    if let summary {
                        Text(LocalizedText.ui("Meals: \(summary.mealCount)", "餐次：\(summary.mealCount)"))
                        Text(
                            LocalizedText.ui(
                                "Main meals logged: \(summary.mainMealsLoggedCount)",
                                "正餐记录：\(summary.mainMealsLoggedCount)"
                            )
                        )
                        Text(
                            LocalizedText.ui(
                                "Completeness tier: \(completionTierDisplayName(for: summary))",
                                "完整度等级：\(completionTierDisplayName(for: summary))"
                            )
                        )
                        Text(LocalizedText.ui("Calories: \(Int(summary.caloriesTotalEstimate)) kcal", "热量：\(Int(summary.caloriesTotalEstimate)) 千卡"))
                        Text(LocalizedText.ui("Protein: \(Int(summary.proteinTotalG)) g", "蛋白质：\(Int(summary.proteinTotalG)) 克"))
                        Text(LocalizedText.ui("Carbs: \(Int(summary.carbsTotalG)) g", "碳水：\(Int(summary.carbsTotalG)) 克"))
                        Text(LocalizedText.ui("Fat: \(Int(summary.fatTotalG)) g", "脂肪：\(Int(summary.fatTotalG)) 克"))

                        if let active = summary.activeEnergyKcal ?? summary.healthSnapshot?.activeEnergyKcal {
                            Text(LocalizedText.ui("Active Energy: \(formatted(active, decimals: 0)) kcal", "活动能量：\(formatted(active, decimals: 0)) 千卡"))
                        }
                        if let resting = summary.restingEnergyKcal ?? summary.healthSnapshot?.restingEnergyKcal {
                            Text(LocalizedText.ui("Resting Energy: \(formatted(resting, decimals: 0)) kcal", "静息能量：\(formatted(resting, decimals: 0)) 千卡"))
                        }
                        if let net = estimatedNet(for: summary) {
                            Text(LocalizedText.ui("Estimated Net: \(formatted(net, decimals: 0)) kcal", "估算净值：\(formatted(net, decimals: 0)) 千卡"))
                        }

                        if let snapshot = summary.healthSnapshot {
                            Divider()
                            Text(LocalizedText.ui("Health Snapshot", "健康快照"))
                                .font(.headline)
                            Text(LocalizedText.ui("Sleep: \(formatted(snapshot.sleepHours, decimals: 1)) h", "睡眠：\(formatted(snapshot.sleepHours, decimals: 1)) 小时"))
                            Text(LocalizedText.ui("Exercise: \(formatted(snapshot.exerciseMinutes, decimals: 0)) min", "运动：\(formatted(snapshot.exerciseMinutes, decimals: 0)) 分钟"))
                            Text(LocalizedText.ui("Steps: \(formatted(snapshot.stepCount, decimals: 0))", "步数：\(formatted(snapshot.stepCount, decimals: 0))"))

                            if !snapshot.workouts.isEmpty {
                                Divider()
                                Text(LocalizedText.ui("Workouts", "训练记录"))
                                    .font(.headline)
                                ForEach(Array(snapshot.workouts.enumerated()), id: \.offset) { _, workout in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(
                                            LocalizedText.ui(
                                                "\(workout.activityType): \(formatted(workout.caloriesKcal, decimals: 0)) kcal, \(formatted(workout.durationMinutes, decimals: 0)) min",
                                                "\(workout.activityType)：\(formatted(workout.caloriesKcal, decimals: 0)) 千卡，\(formatted(workout.durationMinutes, decimals: 0)) 分钟"
                                            )
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(MealCoachTheme.secondaryInk)

                                        Text(
                                            LocalizedText.ui(
                                                "Time: \(workout.startDate.formattedDateTime())",
                                                "时间：\(workout.startDate.formattedDateTime())"
                                            )
                                        )
                                        .font(.footnote)
                                        .foregroundStyle(MealCoachTheme.secondaryInk)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(LocalizedText.ui("No summary available for this day.", "当天暂无汇总数据。"))
                            .foregroundStyle(MealCoachTheme.secondaryInk)
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Summary", "汇总"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    if meals.isEmpty {
                        Text(LocalizedText.ui("No meals saved on this day.", "当天没有已保存餐食。"))
                            .foregroundStyle(MealCoachTheme.secondaryInk)
                    } else {
                        ForEach(meals) { meal in
                            HStack(alignment: .top, spacing: 12) {
                                if let filename = meal.photoFilename,
                                   let image = FileStorage.loadImage(filename: filename) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                } else {
                                    Image(systemName: "fork.knife")
                                        .frame(width: 56, height: 56)
                                        .background(Color.gray.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.mealType.displayName)
                                        .font(.headline)
                                    Text(meal.dateTime.formattedDateTime())
                                        .font(.footnote)
                                        .foregroundStyle(MealCoachTheme.secondaryInk)
                                    Text(
                                        LocalizedText.ui(
                                            "\(Int(meal.caloriesEstimate)) kcal • P/C/F \(Int(meal.proteinG))/\(Int(meal.carbsG))/\(Int(meal.fatG)) g",
                                            "\(Int(meal.caloriesEstimate)) 千卡 • 蛋白/碳水/脂肪 \(Int(meal.proteinG))/\(Int(meal.carbsG))/\(Int(meal.fatG)) 克"
                                        )
                                    )
                                        .font(.subheadline)
                                        .foregroundStyle(MealCoachTheme.secondaryInk)
                                    if !meal.notes.isEmpty {
                                        Text(meal.notes)
                                            .font(.footnote)
                                            .lineLimit(2)
                                            .foregroundStyle(MealCoachTheme.secondaryInk)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Meals", "餐食"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

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
        .navigationTitle(date.formattedShortDate())
        .task {
            loadDayData()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(MealCoachTheme.ink)
            .textCase(nil)
    }

    @MainActor
    private func loadDayData() {
        let dayStart = date.startOfDay
        let dayEnd = dayStart.endOfDay

        do {
            let summaryDescriptor = FetchDescriptor<DailySummary>(
                predicate: #Predicate { $0.date == dayStart }
            )
            summary = try modelContext.fetch(summaryDescriptor).first

            let mealDescriptor = FetchDescriptor<MealEntry>(
                predicate: #Predicate {
                    $0.dateTime >= dayStart && $0.dateTime < dayEnd
                },
                sortBy: [SortDescriptor(\MealEntry.dateTime, order: .reverse)]
            )
            meals = try modelContext.fetch(mealDescriptor)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatted(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "-" }
        return String(format: "%.*f", decimals, value)
    }

    private func estimatedNet(for summary: DailySummary) -> Double? {
        guard summary.mealCount > 0, summary.caloriesTotalEstimate > 0 else { return nil }
        if let cached = summary.netEnergyKcal { return cached }
        let active = summary.activeEnergyKcal ?? summary.healthSnapshot?.activeEnergyKcal
        let resting = summary.restingEnergyKcal ?? summary.healthSnapshot?.restingEnergyKcal
        guard let active, let resting else { return nil }
        return summary.caloriesTotalEstimate - (active + resting)
    }

    private func completionTierDisplayName(for summary: DailySummary) -> String {
        let tier = StreakCalculator.completionTier(
            mainMealsLoggedCount: summary.mainMealsLoggedCount,
            hasAnyMeal: summary.mealCount > 0
        )
        return tier.displayName
    }
}
