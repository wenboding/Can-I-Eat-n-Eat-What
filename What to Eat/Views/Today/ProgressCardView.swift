import SwiftUI

#if canImport(Charts)
import Charts
#endif

struct ProgressCardView: View {
    @ObservedObject var viewModel: TodayProgressViewModel
    let onTapCalendar: () -> Void

    var body: some View {
        Button(action: onTapCalendar) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    LocalizedText.ui("Progress", "进度"),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

                streakSection
                recentDotsSection
                netTrendSection
                yesterdaySection

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .mealCoachCard(tint: MealCoachTheme.navy)
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let todayLogged = viewModel.progressDays.last?.hasAnyMeal == true
            Text(
                LocalizedText.ui(
                    "Streak: \(viewModel.currentStreak) day(s)",
                    "连续打卡：\(viewModel.currentStreak) 天"
                )
            )
            .font(.system(.title3, design: .rounded).weight(.bold))

            Text(
                todayLogged
                    ? LocalizedText.ui("Today is logged.", "今天已记录。")
                    : LocalizedText.ui("No meal logged yet today.", "今天还未记录餐食。")
            )
            .font(.subheadline)
            .foregroundStyle(MealCoachTheme.secondaryInk)
        }
    }

    private var recentDotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedText.ui("Last 7 days completeness", "最近 7 天完整度"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            HStack(spacing: 8) {
                ForEach(viewModel.recentSevenDays, id: \.date) { day in
                    Circle()
                        .fill(color(for: day.tier))
                        .frame(width: 10, height: 10)
                }
            }

            HStack(spacing: 12) {
                legendItem(title: CompletionTier.bronze.displayName, color: color(for: .bronze))
                legendItem(title: CompletionTier.silver.displayName, color: color(for: .silver))
                legendItem(title: CompletionTier.gold.displayName, color: color(for: .gold))
            }
        }
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(MealCoachTheme.secondaryInk)
        }
    }

    @ViewBuilder
    private var netTrendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedText.ui("Estimated energy balance (7 days)", "估算能量平衡（7天）"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

#if canImport(Charts)
            let netDays = viewModel.recentSevenDays.filter { $0.netKcal != nil }
            let emptyIntakeDays = viewModel.recentSevenDays.filter { !$0.hasIntakeData }

            if netDays.isEmpty && emptyIntakeDays.isEmpty {
                Text(LocalizedText.ui("Not enough data for energy trend yet.", "能量趋势数据暂不足。"))
                    .font(.footnote)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
            } else {
                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(MealCoachTheme.secondaryInk.opacity(0.4))

                    ForEach(netDays, id: \.date) { day in
                        if let net = day.netKcal {
                            LineMark(
                                x: .value("Date", day.date),
                                y: .value("Net", net)
                            )
                            .foregroundStyle(MealCoachTheme.navy)

                            PointMark(
                                x: .value("Date", day.date),
                                y: .value("Net", net)
                            )
                            .foregroundStyle(net <= 0 ? MealCoachTheme.teal : MealCoachTheme.coral)
                        }
                    }

                    // Hollow dots at baseline mark days with no meal intake data.
                    ForEach(emptyIntakeDays, id: \.date) { day in
                        PointMark(
                            x: .value("Date", day.date),
                            y: .value("Net", 0)
                        )
                        .symbolSize(70)
                        .foregroundStyle(MealCoachTheme.secondaryInk.opacity(0.40))

                        PointMark(
                            x: .value("Date", day.date),
                            y: .value("Net", 0)
                        )
                        .symbolSize(28)
                        .foregroundStyle(.white.opacity(0.95))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(MealCoachTheme.secondaryInk.opacity(0.15))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text("\(Int(amount))")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 120)
            }
#else
            Text(LocalizedText.ui("Charts are unavailable on this system.", "当前系统不支持图表显示。"))
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.secondaryInk)
#endif
        }
    }

    private var yesterdaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedText.ui("Yesterday", "昨天"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            Text(viewModel.yesterdaySummaryText)
                .font(.footnote)
                .foregroundStyle(MealCoachTheme.secondaryInk)

            if let hint = viewModel.yesterdayHintText {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(MealCoachTheme.coral)
            }
        }
    }

    private func color(for tier: CompletionTier) -> Color {
        switch tier {
        case .none:
            return MealCoachTheme.secondaryInk.opacity(0.2)
        case .bronze:
            return MealCoachTheme.teal
        case .silver:
            return MealCoachTheme.navy.opacity(0.65)
        case .gold:
            return MealCoachTheme.amber
        }
    }
}
