import Combine
import Foundation
import HealthKit

enum HealthKitManagerError: LocalizedError {
    case unavailable
    case notAuthorized
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return AppLanguage.current == .simplifiedChinese ? "此设备不支持健康数据。" : "Health data is not available on this device."
        case .notAuthorized:
            return AppLanguage.current == .simplifiedChinese ? "需要健康权限才能读取今日快照。" : "Health permission is required to read today's snapshot."
        case .queryFailed:
            return AppLanguage.current == .simplifiedChinese ? "暂时无法加载健康数据。" : "Unable to load health data right now."
        }
    }
}

enum HealthPermissionState {
    case unknown
    case authorized
    case denied
    case unavailable
}

@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var permissionState: HealthPermissionState = .unknown

    private let healthStore = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        let quantityIds: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .basalEnergyBurned,
            .appleExerciseTime,
            .stepCount,
            .bodyMass,
            .bodyFatPercentage
        ]

        quantityIds
            .compactMap { HKQuantityType.quantityType(forIdentifier: $0) }
            .forEach { types.insert($0) }

        types.insert(HKObjectType.workoutType())

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        return types
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            permissionState = .unavailable
            return false
        }

        do {
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }

            permissionState = success ? .authorized : .denied
            return success
        } catch {
            permissionState = .denied
            return false
        }
    }

    func fetchTodaySnapshot() async throws -> HealthSnapshot {
        try await fetchSnapshot(for: .now)
    }

    func fetchSnapshot(for date: Date) async throws -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else {
            permissionState = .unavailable
            throw HealthKitManagerError.unavailable
        }

        let dayStart = date.startOfDay
        let dayEnd = dayStart.endOfDay

        async let energy = safeCumulativeQuantity(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: dayStart,
            end: dayEnd
        )

        async let restingEnergy = safeCumulativeQuantity(
            // Use basal energy as resting-energy proxy for daily net estimate.
            identifier: .basalEnergyBurned,
            unit: .kilocalorie(),
            start: dayStart,
            end: dayEnd
        )

        async let exercise = safeCumulativeQuantity(
            identifier: .appleExerciseTime,
            unit: .minute(),
            start: dayStart,
            end: dayEnd
        )

        async let steps = safeCumulativeQuantity(
            identifier: .stepCount,
            unit: .count(),
            start: dayStart,
            end: dayEnd
        )

        async let sleep = safeSleepHours(anchoredTo: dayStart)

        async let weight = safeLatestQuantity(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            upTo: dayEnd
        )

        async let bodyFatRaw = safeLatestQuantity(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            upTo: dayEnd
        )

        async let workouts = safeWorkouts(start: dayStart, end: dayEnd)

        let snapshot = HealthSnapshot(
            startDate: dayStart,
            endDate: dayEnd,
            activeEnergyKcal: await energy,
            restingEnergyKcal: await restingEnergy,
            exerciseMinutes: await exercise,
            stepCount: await steps,
            sleepHours: await sleep,
            bodyMassKg: await weight,
            bodyFatPercentage: (await bodyFatRaw).map { $0 * 100 },
            workouts: await workouts
        )

        if snapshotHasAnyData(snapshot) {
            permissionState = .authorized
        } else if permissionState == .unknown {
            // Keep unknown when no datapoints are returned. This can mean either
            // no recorded data yet or incomplete permissions.
            permissionState = .unknown
        }

#if DEBUG
        print(
            "[HealthKit] Snapshot loaded for \(dayStart): " +
            "active=\(snapshot.activeEnergyKcal?.description ?? "nil"), " +
            "resting=\(snapshot.restingEnergyKcal?.description ?? "nil"), " +
            "exercise=\(snapshot.exerciseMinutes?.description ?? "nil"), " +
            "steps=\(snapshot.stepCount?.description ?? "nil"), " +
            "sleep=\(snapshot.sleepHours?.description ?? "nil"), " +
            "weight=\(snapshot.bodyMassKg?.description ?? "nil"), " +
            "fat=\(snapshot.bodyFatPercentage?.description ?? "nil"), " +
            "workouts=\(snapshot.workouts.count)"
        )
#endif

        return snapshot
    }

    private func safeCumulativeQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        do {
            return try await cumulativeQuantity(identifier: identifier, unit: unit, start: start, end: end)
        } catch {
#if DEBUG
            print("[HealthKit] cumulative query failed (\(identifier.rawValue)): \(error)")
#endif
            return nil
        }
    }

    private func safeLatestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        upTo endDate: Date
    ) async -> Double? {
        do {
            return try await latestQuantity(identifier: identifier, unit: unit, upTo: endDate)
        } catch {
#if DEBUG
            print("[HealthKit] latest query failed (\(identifier.rawValue)): \(error)")
#endif
            return nil
        }
    }

    private func safeSleepHours(anchoredTo dayStart: Date) async -> Double? {
        do {
            return try await sleepHours(anchoredTo: dayStart)
        } catch {
#if DEBUG
            print("[HealthKit] sleep query failed: \(error)")
#endif
            return nil
        }
    }

    private func safeWorkouts(start: Date, end: Date) async -> [WorkoutSummary] {
        do {
            return try await workoutSummaries(start: start, end: end)
        } catch {
#if DEBUG
            print("[HealthKit] workout query failed: \(error)")
#endif
            return []
        }
    }

    private func snapshotHasAnyData(_ snapshot: HealthSnapshot) -> Bool {
        snapshot.activeEnergyKcal != nil ||
        snapshot.restingEnergyKcal != nil ||
        snapshot.exerciseMinutes != nil ||
        snapshot.stepCount != nil ||
        snapshot.sleepHours != nil ||
        snapshot.bodyMassKg != nil ||
        snapshot.bodyFatPercentage != nil ||
        !snapshot.workouts.isEmpty
    }

    private func cumulativeQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func latestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        upTo endDate: Date
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: nil,
            end: endDate,
            options: .strictEndDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }

            healthStore.execute(query)
        }
    }

    private func sleepHours(anchoredTo dayStart: Date) async throws -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let windowStart = Calendar.current.date(byAdding: .hour, value: -6, to: dayStart) ?? dayStart
        let windowEnd = Calendar.current.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let categorySamples = (samples as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }

            healthStore.execute(query)
        }

        let totalSeconds = samples.reduce(0.0) { partial, sample in
            guard isAsleep(sample.value) else { return partial }
            return partial + sample.endDate.timeIntervalSince(sample.startDate)
        }

        guard totalSeconds > 0 else { return nil }
        return totalSeconds / 3600
    }

    private func isAsleep(_ value: Int) -> Bool {
        if #available(iOS 16.0, *) {
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]
            return asleepValues.contains(value)
        } else {
            return value == HKCategoryValueSleepAnalysis.asleep.rawValue
        }
    }

    private func workoutSummaries(start: Date, end: Date) async throws -> [WorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let items = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: items)
            }
            healthStore.execute(query)
        }

        return workouts.map { workout in
            WorkoutSummary(
                activityType: workoutActivityName(for: workout.workoutActivityType),
                caloriesKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                durationMinutes: max(0, workout.duration / 60),
                startDate: workout.startDate,
                endDate: workout.endDate
            )
        }
    }

    private func workoutActivityName(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .other: return "Other"
        default:
            return "Workout(\(activityType.rawValue))"
        }
    }
}
