import Foundation

struct WorkoutSummary: Codable, Hashable {
    let activityType: String
    let caloriesKcal: Double?
    let durationMinutes: Double
    let startDate: Date
    let endDate: Date

    enum CodingKeys: String, CodingKey {
        case activityType = "activity_type"
        case caloriesKcal = "calories_kcal"
        case durationMinutes = "duration_minutes"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct HealthSnapshot: Codable, Hashable {
    let startDate: Date
    let endDate: Date

    let activeEnergyKcal: Double?
    let restingEnergyKcal: Double?
    let exerciseMinutes: Double?
    let stepCount: Double?
    let sleepHours: Double?
    let bodyMassKg: Double?
    let bodyFatPercentage: Double?
    let workouts: [WorkoutSummary]

    enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case activeEnergyKcal
        case restingEnergyKcal
        case exerciseMinutes
        case stepCount
        case sleepHours
        case bodyMassKg
        case bodyFatPercentage
        case workouts
    }

    init(
        startDate: Date,
        endDate: Date,
        activeEnergyKcal: Double?,
        restingEnergyKcal: Double?,
        exerciseMinutes: Double?,
        stepCount: Double?,
        sleepHours: Double?,
        bodyMassKg: Double?,
        bodyFatPercentage: Double?,
        workouts: [WorkoutSummary]
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.stepCount = stepCount
        self.sleepHours = sleepHours
        self.bodyMassKg = bodyMassKg
        self.bodyFatPercentage = bodyFatPercentage
        self.workouts = workouts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        activeEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKcal)
        restingEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .restingEnergyKcal)
        exerciseMinutes = try container.decodeIfPresent(Double.self, forKey: .exerciseMinutes)
        stepCount = try container.decodeIfPresent(Double.self, forKey: .stepCount)
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours)
        bodyMassKg = try container.decodeIfPresent(Double.self, forKey: .bodyMassKg)
        bodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage)
        workouts = try container.decodeIfPresent([WorkoutSummary].self, forKey: .workouts) ?? []
    }

    var totalEnergyKcal: Double? {
        guard let activeEnergyKcal, let restingEnergyKcal else { return nil }
        return activeEnergyKcal + restingEnergyKcal
    }
}
