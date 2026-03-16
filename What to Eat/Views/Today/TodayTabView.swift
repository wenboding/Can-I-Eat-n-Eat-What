import CoreLocation
import Combine
import SwiftData
import SwiftUI

struct TodayTabView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var todaySnapshot: HealthSnapshot?
    @State private var snapshotError: String?
    @State private var isLoadingSnapshot = false

    @State private var recommendation: RecommendationResponse?
    @State private var recommendationError: String?
    @State private var isRequestingRecommendation = false

    @State private var selectedMealTypeForLogger: MealType?
    @State private var mealPhotoUploadCountByType: [MealType: Int] = [:]
    @State private var mealUploadLockError: String?
    @State private var animateCards = false
    @State private var recommendationCooldownRemaining: TimeInterval = 0
    @State private var showingProgressCalendar = false
    @State private var hasCompletedInitialLoad = false
    @StateObject private var progressViewModel = TodayProgressViewModel()

    private let metricsColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    private let recommendationCooldownSeconds: TimeInterval = 5 * 60
    private let recommendationCooldownTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let recommendationCooldownStorageKey = "mealcoach.recommendation.lastRequestedAt"

    var body: some View {
        NavigationStack {
            ZStack {
                MealCoachBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        if appContainer.healthKitManager.permissionState == .denied {
                            PermissionBanner(
                                title: "Health Access Needed",
                                message: "Enable Health access for activity, sleep, and body metrics in Today Statistics."
                            )
                            .opacity(animateCards ? 1 : 0)
                            .offset(y: animateCards ? 0 : 18)
                            .animation(.easeOut(duration: 0.55), value: animateCards)
                        }

                        if appContainer.locationManager.authorizationStatus == .denied || appContainer.locationManager.authorizationStatus == .restricted {
                            PermissionBanner(
                                title: "Location Optional",
                                message: "Location is disabled. Recommendations will still work without nearby restaurant options."
                            )
                            .opacity(animateCards ? 1 : 0)
                            .offset(y: animateCards ? 0 : 18)
                            .animation(.easeOut(duration: 0.65), value: animateCards)
                        }

                        ProgressCardView(viewModel: progressViewModel) {
                            showingProgressCalendar = true
                        }
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 18)
                        .animation(.easeOut(duration: 0.8), value: animateCards)

                        mealLoggingCard
                            .opacity(animateCards ? 1 : 0)
                            .offset(y: animateCards ? 0 : 18)
                            .animation(.easeOut(duration: 0.85), value: animateCards)

                        recommendationCard
                            .opacity(animateCards ? 1 : 0)
                            .offset(y: animateCards ? 0 : 18)
                            .animation(.easeOut(duration: 0.95), value: animateCards)

                        todaySnapshotCard
                            .opacity(animateCards ? 1 : 0)
                            .offset(y: animateCards ? 0 : 18)
                            .animation(.easeOut(duration: 1.0), value: animateCards)
                    }
                    .foregroundStyle(MealCoachTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
            }
            .task {
                if !animateCards {
                    animateCards = true
                }
                await loadTodaySnapshotIfNeeded()
                refreshMealUploadLockState()
                refreshRecommendationCooldown()
                await progressViewModel.loadRecentProgress(
                    context: modelContext,
                    healthKitManager: appContainer.healthKitManager
                )
                hasCompletedInitialLoad = true
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                guard hasCompletedInitialLoad else { return }
                guard newPhase == .active, oldPhase != .active else { return }

                Task {
                    await refreshOnAppForeground()
                }
            }
            .sheet(item: $selectedMealTypeForLogger) { mealType in
                MealLogSheetView(mealType: mealType) {
                    Task { @MainActor in
                        await refreshAfterMealSaved()
                    }
                }
                .environmentObject(appContainer)
            }
            .sheet(isPresented: $showingProgressCalendar) {
                ProgressCalendarSheet()
            }
            .onReceive(recommendationCooldownTicker) { _ in
                guard recommendationCooldownRemaining > 0 else { return }
                refreshRecommendationCooldown()
            }
        }
    }

    private var todaySnapshotCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today Statistics", systemImage: "waveform.path.ecg")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MealCoachTheme.ink)

                Spacer()

                if isLoadingSnapshot {
                    ProgressView()
                        .tint(MealCoachTheme.teal)
                }
            }

            if let snapshot = todaySnapshot {
                LazyVGrid(columns: metricsColumns, spacing: 10) {
                    metricTile(title: "Sleep", value: "\(formattedNumber(snapshot.sleepHours, decimals: 1)) h", icon: "moon.stars.fill", tint: MealCoachTheme.navy)
                    metricTile(title: "Energy", value: "\(formattedNumber(snapshot.activeEnergyKcal, decimals: 0)) kcal", icon: "flame.fill", tint: MealCoachTheme.coral)
                    metricTile(title: "Exercise", value: "\(formattedNumber(snapshot.exerciseMinutes, decimals: 0)) min", icon: "figure.run", tint: MealCoachTheme.teal)
                    metricTile(title: "Steps", value: "\(formattedNumber(snapshot.stepCount, decimals: 0))", icon: "shoeprints.fill", tint: MealCoachTheme.amber)
                    metricTile(title: "Weight", value: "\(formattedNumber(snapshot.bodyMassKg, decimals: 1)) kg", icon: "scalemass.fill", tint: MealCoachTheme.navy)
                    metricTile(title: "Body Fat", value: "\(formattedNumber(snapshot.bodyFatPercentage, decimals: 1))%", icon: "percent", tint: MealCoachTheme.teal)
                }
            } else if let snapshotError {
                Text(snapshotError)
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
            } else {
                Text("No snapshot yet.")
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
            }

            Button {
                Task {
                    await loadTodaySnapshotIfNeeded(force: true)
                    await progressViewModel.loadRecentProgress(
                        context: modelContext,
                        healthKitManager: appContainer.healthKitManager
                    )
                }
            } label: {
                Label(
                    isLoadingSnapshot
                        ? LocalizedText.ui("Refreshing...", "刷新中...")
                        : LocalizedText.ui("Refresh Snapshot", "刷新快照"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.navy))
            .disabled(isLoadingSnapshot)
        }
        .mealCoachCard(tint: MealCoachTheme.teal)
    }

    private var mealLoggingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Log a Meal", systemImage: "camera.viewfinder")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            Text(
                LocalizedText.ui(
                    "Breakfast, lunch, and dinner can be uploaded once per day. Snack/drink/sweet logs can be uploaded up to 4 times per day.",
                    "早餐、午餐、晚餐每天可上传一次；加餐/饮品/甜点每天最多可上传 4 次。"
                )
            )
                .font(.subheadline)
                .foregroundStyle(MealCoachTheme.secondaryInk)

            if MealType.allCases.allSatisfy({ isMealUploadLocked(for: $0) }) {
                Text(
                    LocalizedText.ui(
                        "Today's upload quota for all meal types is fully used.",
                        "今天所有餐别的上传配额都已用完。"
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
            }

            if let mealUploadLockError {
                Text(mealUploadLockError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        openMealLogger(for: .breakfast)
                    } label: {
                        Label("Log Breakfast", systemImage: "sunrise.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.amber))
                    .disabled(isMealUploadLocked(for: .breakfast))

                    Button {
                        openMealLogger(for: .lunch)
                    } label: {
                        Label("Log Lunch", systemImage: "sun.max.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.amber, endColor: MealCoachTheme.coral))
                    .disabled(isMealUploadLocked(for: .lunch))
                }

                HStack(spacing: 10) {
                    Button {
                        openMealLogger(for: .dinner)
                    } label: {
                        Label("Log Dinner", systemImage: "moon.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.teal))
                    .disabled(isMealUploadLocked(for: .dinner))

                    Button {
                        openMealLogger(for: .snack)
                    } label: {
                        Label(
                            LocalizedText.ui("Log Sweets", "记录甜点"),
                            systemImage: "cup.and.saucer.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.coral, endColor: MealCoachTheme.amber))
                    .disabled(isMealUploadLocked(for: .snack))
                }
            }
        }
        .mealCoachCard(tint: MealCoachTheme.amber)
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next Meal Recommendation", systemImage: "sparkles")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(MealCoachTheme.ink)

            if isRequestingRecommendation {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(MealCoachTheme.coral)
                    Text("Generating recommendation...")
                        .font(.subheadline)
                        .foregroundStyle(MealCoachTheme.secondaryInk)
                }
            }

            if let recommendation {
                Text(recommendation.recommendedMeal.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(recommendation.recommendedMeal.why)
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)

                Text(
                    LocalizedText.ui(
                        "Estimated: \(Int(recommendation.recommendedMeal.estimatedCalories)) kcal",
                        "估算：\(Int(recommendation.recommendedMeal.estimatedCalories)) 千卡"
                    )
                )
                    .font(.subheadline)
                Text(
                    LocalizedText.ui(
                        "Macros P/C/F: \(Int(recommendation.recommendedMeal.estimatedMacros.proteinG))/\(Int(recommendation.recommendedMeal.estimatedMacros.carbsG))/\(Int(recommendation.recommendedMeal.estimatedMacros.fatG)) g",
                        "三大营养素 蛋白/碳水/脂肪：\(Int(recommendation.recommendedMeal.estimatedMacros.proteinG))/\(Int(recommendation.recommendedMeal.estimatedMacros.carbsG))/\(Int(recommendation.recommendedMeal.estimatedMacros.fatG)) 克"
                    )
                )
                    .font(.subheadline)

                if !recommendation.nearbyOptions.isEmpty {
                    Divider()
                    Text("Nearby options")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))

                    ForEach(Array(recommendation.nearbyOptions.enumerated()), id: \.offset) { _, option in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(MealCoachTheme.coral)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    LocalizedText.ui(
                                        "\(option.name) • \(String(format: "%.1f", option.distanceMiles)) mi",
                                        "\(option.name) • \(String(format: "%.1f", option.distanceMiles)) 英里"
                                    )
                                )
                                    .font(.subheadline.weight(.semibold))
                                Text(option.reason)
                                    .font(.footnote)
                                    .foregroundStyle(MealCoachTheme.secondaryInk)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                HStack(spacing: 10) {
                    Button("Try Another") {
                        Task { await requestRecommendation() }
                    }
                    .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.navy))
                    .disabled(isRecommendationOnCooldown || isRequestingRecommendation)
                }
            } else {
                Text("Tap below for a single recommendation. This is one-shot, not a conversation.")
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)

                Button {
                    Task { await requestRecommendation() }
                } label: {
                    Label("Get Next Meal Recommendation", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))
                .disabled(isRecommendationOnCooldown || isRequestingRecommendation)
            }

            if isRecommendationOnCooldown {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(MealCoachTheme.navy)
                    Text(
                        LocalizedText.ui(
                            "Cooldown active: \(cooldownDisplayText)",
                            "冷却中：\(cooldownDisplayText)"
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
                }
            }

            if let recommendationError {
                Text(recommendationError)
                    .font(.footnote)
                    .foregroundStyle(.red)

                Button("Retry") {
                    Task { await requestRecommendation() }
                }
                .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
                .disabled(isRecommendationOnCooldown || isRequestingRecommendation)
            }
        }
        .mealCoachCard(tint: MealCoachTheme.coral)
    }

    private func metricTile(title: LocalizedStringKey, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @MainActor
    private func refreshOnAppForeground() async {
        await loadTodaySnapshotIfNeeded(force: true)
        refreshMealUploadLockState()
        refreshRecommendationCooldown()
        await progressViewModel.loadRecentProgress(
            context: modelContext,
            healthKitManager: appContainer.healthKitManager
        )
    }

    @MainActor
    private func refreshAfterMealSaved() async {
        refreshMealUploadLockState()
        await loadTodaySnapshotIfNeeded(force: true)
        await progressViewModel.loadRecentProgress(
            context: modelContext,
            healthKitManager: appContainer.healthKitManager
        )
    }

    @MainActor
    private func loadTodaySnapshotIfNeeded(force: Bool = false) async {
        if isLoadingSnapshot { return }
        if todaySnapshot != nil && !force { return }

        isLoadingSnapshot = true
        defer { isLoadingSnapshot = false }

#if DEBUG
        print("[Today] Snapshot refresh started. force=\(force), permissionState=\(appContainer.healthKitManager.permissionState)")
#endif

        if appContainer.healthKitManager.permissionState == .unknown {
            _ = await appContainer.healthKitManager.requestAuthorization()
#if DEBUG
            print("[Today] Health authorization requested. newState=\(appContainer.healthKitManager.permissionState)")
#endif
        }

        do {
            let snapshot = try await appContainer.healthKitManager.fetchTodaySnapshot()
            todaySnapshot = snapshot
            snapshotError = nil

            try DailySummaryCalculator.recomputeSummary(
                for: .now,
                context: modelContext,
                healthSnapshot: snapshot
            )
#if DEBUG
            print("[Today] Snapshot refresh succeeded.")
#endif
        } catch {
            snapshotError = error.localizedDescription
#if DEBUG
            print("[Today] Snapshot refresh failed: \(error)")
#endif
        }
    }

    @MainActor
    private func requestRecommendation() async {
        guard !isRequestingRecommendation else { return }
        refreshRecommendationCooldown()
        guard !isRecommendationOnCooldown else {
            recommendationError = LocalizedText.ui(
                "Recommendation is limited to once every 5 minutes. Try again in \(cooldownDisplayText).",
                "推荐功能每 5 分钟只能使用一次。请在 \(cooldownDisplayText) 后重试。"
            )
            return
        }

        isRequestingRecommendation = true
        recommendationError = nil
        markRecommendationRequested()
        defer {
            isRequestingRecommendation = false
            refreshRecommendationCooldown()
        }

        do {
            let preferences = try UserPreferencesStore.fetchOrCreate(in: modelContext)

            let todayIntake = try fetchTodayIntake()
            let recentMeals = try fetchRecentMeals(daysBack: 3)

            let nearbyRestaurants: [NearbyRestaurantContext]
            if appContainer.locationManager.authorizationStatus == .authorizedAlways || appContainer.locationManager.authorizationStatus == .authorizedWhenInUse {
                let restaurants = try await appContainer.locationManager.nearbyRestaurants(radiusMiles: preferences.radiusMiles)
                nearbyRestaurants = restaurants.map {
                    NearbyRestaurantContext(name: $0.name, distanceMiles: $0.distanceMiles, category: $0.category)
                }
            } else {
                nearbyRestaurants = []
            }

            let context = RecommendationContext(
                generatedAt: .now,
                currentLocalTime: currentTimeContext(for: .now),
                todayIntake: todayIntake,
                healthSnapshot: todaySnapshot,
                recentMeals: recentMeals,
                nearbyRestaurants: nearbyRestaurants,
                preferences: preferences.toPayload()
            )

            let result = try await appContainer.llmClient.recommendNextMeal(context: context)
            recommendation = result
        } catch {
            recommendationError = error.localizedDescription
        }
    }

    private func fetchRecentMeals(daysBack: Int) throws -> [RecentMealContext] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date().addingTimeInterval(-259200)

        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.dateTime >= cutoff },
            sortBy: [SortDescriptor(\MealEntry.dateTime, order: .reverse)]
        )

        let entries = try modelContext.fetch(descriptor)

        return entries.prefix(30).map {
            RecentMealContext(
                date: $0.dateTime,
                mealType: $0.mealType,
                calories: $0.caloriesEstimate,
                macros: $0.macroEstimate,
                notes: $0.notes
            )
        }
    }

    private func fetchTodayIntake() throws -> TodayIntakeContext {
        let dayStart = Date().startOfDay
        let dayEnd = dayStart.endOfDay

        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate {
                $0.dateTime >= dayStart && $0.dateTime < dayEnd
            }
        )

        let entries = try modelContext.fetch(descriptor)
        let totalCalories = entries.reduce(0) { partial, entry in
            partial + max(0, entry.caloriesEstimate)
        }

        return TodayIntakeContext(
            mealCount: entries.count,
            totalCalories: totalCalories
        )
    }

    private func inferredMealType(for date: Date) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 11 { return .breakfast }
        if hour < 16 { return .lunch }
        return .dinner
    }

    private func currentTimeContext(for date: Date) -> CurrentTimeContext {
        let timeZone = TimeZone.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone

        return CurrentTimeContext(
            localDateTime: formatter.string(from: date),
            timezoneIdentifier: timeZone.identifier,
            timezoneOffsetMinutes: timeZone.secondsFromGMT(for: date) / 60,
            inferredMealType: inferredMealType(for: date)
        )
    }

    private func formattedNumber(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "-" }
        return String(format: "%.*f", decimals, value)
    }

    @MainActor
    private func refreshMealUploadLockState() {
        let dayStart = Date().startOfDay
        let dayEnd = dayStart.endOfDay

        do {
            let descriptor = FetchDescriptor<MealEntry>(
                predicate: #Predicate {
                    $0.dateTime >= dayStart && $0.dateTime < dayEnd
                }
            )
            let todaysEntries = try modelContext.fetch(descriptor)
            var counts: [MealType: Int] = [:]
            for entry in todaysEntries where entry.photoFilename != nil {
                counts[entry.mealType, default: 0] += 1
            }
            mealPhotoUploadCountByType = counts
            mealUploadLockError = nil
        } catch {
            mealPhotoUploadCountByType = [:]
            mealUploadLockError = error.localizedDescription
        }
    }

    @MainActor
    private func openMealLogger(for mealType: MealType) {
        guard !isMealUploadLocked(for: mealType) else { return }
        selectedMealTypeForLogger = mealType
    }

    private func isMealUploadLocked(for mealType: MealType) -> Bool {
        mealPhotoUploadCount(for: mealType) >= mealType.dailyPhotoUploadQuota
    }

    private func mealPhotoUploadCount(for mealType: MealType) -> Int {
        mealPhotoUploadCountByType[mealType] ?? 0
    }

    private var isRecommendationOnCooldown: Bool {
        recommendationCooldownRemaining > 0.5
    }

    private var cooldownDisplayText: String {
        let totalSeconds = Int(recommendationCooldownRemaining.rounded(.up))
        let minutes = max(0, totalSeconds / 60)
        let seconds = max(0, totalSeconds % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @MainActor
    private func refreshRecommendationCooldown(referenceDate: Date = .now) {
        guard let lastRequestedAt = UserDefaults.standard.object(forKey: Self.recommendationCooldownStorageKey) as? Date else {
            recommendationCooldownRemaining = 0
            return
        }

        let elapsed = referenceDate.timeIntervalSince(lastRequestedAt)
        recommendationCooldownRemaining = max(0, recommendationCooldownSeconds - elapsed)
    }

    @MainActor
    private func markRecommendationRequested(at date: Date = .now) {
        UserDefaults.standard.set(date, forKey: Self.recommendationCooldownStorageKey)
        refreshRecommendationCooldown(referenceDate: date)
    }
}
