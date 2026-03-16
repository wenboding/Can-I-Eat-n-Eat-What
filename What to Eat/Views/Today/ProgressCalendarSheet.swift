import SwiftData
import SwiftUI

private enum ProgressCalendarMetric: String, CaseIterable, Identifiable {
    case completeness
    case net

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .completeness:
            return LocalizedText.ui("Completeness", "完整度")
        case .net:
            return LocalizedText.ui("Net", "净能量")
        }
    }
}

struct ProgressCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var monthAnchor = Date().startOfMonth
    @State private var metric: ProgressCalendarMetric = .completeness
    @State private var summariesByDay: [Date: DailySummary] = [:]
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        NavigationStack {
            ZStack {
                MealCoachBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        monthHeader

                        Picker("", selection: $metric) {
                            ForEach(ProgressCalendarMetric.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        weekdayHeader

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                                if let day {
                                    dayCell(day)
                                } else {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.clear)
                                        .frame(height: 52)
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(LocalizedText.ui("Progress Calendar", "进度日历"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedText.ui("Close", "关闭")) {
                        dismiss()
                    }
                }
            }
            .task {
                loadMonthData()
            }
            .onChange(of: monthAnchor) { _, _ in
                loadMonthData()
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                monthAnchor = Calendar.current.date(byAdding: .month, value: -1, to: monthAnchor)?.startOfMonth ?? monthAnchor
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.navy))

            Spacer()

            Text(monthTitle(for: monthAnchor))
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            Spacer()

            Button {
                monthAnchor = Calendar.current.date(byAdding: .month, value: 1, to: monthAnchor)?.startOfMonth ?? monthAnchor
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.navy))
        }
    }

    private var weekdayHeader: some View {
        let calendar = Calendar.current
        let symbols = reorderedWeekdaySymbols(calendar: calendar)

        return HStack(spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MealCoachTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthCells: [Date?] {
        let calendar = Calendar.current
        let monthStart = monthAnchor.startOfMonth
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let firstWeekdayInMonth = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekdayInMonth - calendar.firstWeekday + 7) % 7

        var cells = Array<Date?>(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(date.startOfDay)
            }
        }

        let trailing = (7 - (cells.count % 7)) % 7
        if trailing > 0 {
            cells.append(contentsOf: Array<Date?>(repeating: nil, count: trailing))
        }

        return cells
    }

    private func dayCell(_ date: Date) -> some View {
        let summary = summariesByDay[date.startOfDay]
        let isToday = Calendar.current.isDateInToday(date)

        return NavigationLink {
            DailyHistoryDetailView(date: date)
        } label: {
            VStack(spacing: 6) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MealCoachTheme.ink)

                metricIndicator(summary: summary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.76))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday ? MealCoachTheme.navy.opacity(0.55) : .white.opacity(0.7), lineWidth: isToday ? 1.4 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func metricIndicator(summary: DailySummary?) -> some View {
        switch metric {
        case .completeness:
            let tier = StreakCalculator.completionTier(
                mainMealsLoggedCount: summary?.mainMealsLoggedCount ?? 0,
                hasAnyMeal: (summary?.mealCount ?? 0) > 0
            )
            Circle()
                .fill(color(for: tier))
                .frame(width: 11, height: 11)
        case .net:
            if let net = estimatedNet(for: summary) {
                Capsule()
                    .fill(color(forNet: net))
                    .frame(width: 24, height: 8)
            } else {
                Capsule()
                    .fill(MealCoachTheme.secondaryInk.opacity(0.2))
                    .frame(width: 24, height: 8)
            }
        }
    }

    private func estimatedNet(for summary: DailySummary?) -> Double? {
        guard let summary else { return nil }
        guard summary.mealCount > 0, summary.caloriesTotalEstimate > 0 else { return nil }
        if let cached = summary.netEnergyKcal { return cached }

        let active = summary.activeEnergyKcal ?? summary.healthSnapshot?.activeEnergyKcal
        let resting = summary.restingEnergyKcal ?? summary.healthSnapshot?.restingEnergyKcal
        guard let active, let resting else { return nil }

        return summary.caloriesTotalEstimate - (active + resting)
    }

    private func color(for tier: CompletionTier) -> Color {
        switch tier {
        case .none:
            return MealCoachTheme.secondaryInk.opacity(0.22)
        case .bronze:
            return MealCoachTheme.teal
        case .silver:
            return MealCoachTheme.navy.opacity(0.65)
        case .gold:
            return MealCoachTheme.amber
        }
    }

    private func color(forNet net: Double) -> Color {
        if net < -80 { return MealCoachTheme.teal }
        if net > 80 { return MealCoachTheme.coral }
        return MealCoachTheme.amber
    }

    @MainActor
    private func loadMonthData() {
        let monthStart = monthAnchor.startOfMonth
        let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart.endOfDay

        do {
            let descriptor = FetchDescriptor<DailySummary>(
                predicate: #Predicate { $0.date >= monthStart && $0.date < monthEnd }
            )
            let summaries = try modelContext.fetch(descriptor)
            summariesByDay = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date.startOfDay, $0) })
            errorMessage = nil
        } catch {
            summariesByDay = [:]
            errorMessage = error.localizedDescription
        }
    }

    private func reorderedWeekdaySymbols(calendar: Calendar) -> [String] {
        var symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        if shift > 0 {
            symbols = Array(symbols[shift...]) + symbols[..<shift]
        }
        return symbols
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }
}

private extension Date {
    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components)?.startOfDay ?? startOfDay
    }
}
