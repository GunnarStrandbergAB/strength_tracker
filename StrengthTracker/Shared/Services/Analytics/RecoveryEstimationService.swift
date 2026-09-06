import Foundation

/// A conservative exposure estimate, not a measurement of muscle recovery.
@MainActor
public final class RecoveryEstimationService: Sendable {
    private let workoutRepository: any WorkoutRepository
    private let feedback: RecoveryFeedbackStore

    public init(workoutRepository: any WorkoutRepository, feedback: RecoveryFeedbackStore? = nil) {
        self.workoutRepository = workoutRepository
        self.feedback = feedback ?? RecoveryFeedbackStore()
    }

    public func computeRecoveryPatterns(workouts: [Workout]? = nil, bodyWeightKg: Double, now: Date = Date()) async throws -> [RecoveryPattern] {
        let all: [Workout]
        if let workouts { all = workouts } else { all = try await workoutRepository.fetchAll() }
        let completed = all.filter { $0.completedAt != nil && $0.trainingDate <= now }
            .sorted { $0.trainingDate < $1.trainingDate }
        struct Exposure { let date: Date; let dose: Double; let effort: Double; let direct: Double }
        var exposures: [String: [Exposure]] = [:]
        for workout in completed {
            var doses: [MuscleGroup: Double] = [:]
            var direct: [MuscleGroup: Double] = [:]
            var effortSum: [MuscleGroup: Double] = [:]
            for we in workout.exercises {
                let sets = we.sets.filter { $0.isCompleted && $0.setType != .warmup }
                let credits = AnalyticsCalculations.attributeHardSetCredits(hardSets: sets.count,
                    primaryMuscle: we.exercise.primaryMuscleGroup, secondaryMuscles: we.exercise.secondaryMuscleGroups)
                let effort = sets.compactMap(\.rpe)
                let mean = effort.isEmpty ? 0.8 : effort.reduce(0, +) / Double(effort.count) / 10
                direct[we.exercise.primaryMuscleGroup, default: 0] += Double(sets.count)
                for (muscle, dose) in credits {
                    doses[muscle, default: 0] += dose
                    effortSum[muscle, default: 0] += dose * mean
                }
            }
            for (muscle, dose) in doses where dose >= 0.5 {
                exposures[muscle.rawValue, default: []].append(Exposure(date: workout.trainingDate,
                    dose: dose, effort: effortSum[muscle, default: 0] / dose, direct: direct[muscle, default: 0]))
            }
        }
        return exposures.compactMap { muscle, history in
            guard let last = history.last, now.timeIntervalSince(last.date) <= 14 * 86400 else { return nil }
            let base = Self.baseRecoveryHours[muscle] ?? 48
            var remaining = 0.0
            var previousDate: Date?
            var latestDuration = base
            for (index, exposure) in history.enumerated() {
                if let previousDate { remaining = max(0, remaining - exposure.date.timeIntervalSince(previousDate) / 3600) }
                let pastDoses = history.prefix(index).suffix(12).map(\.dose).sorted()
                let usual = pastDoses.count >= 4 ? pastDoses[pastDoses.count / 2] : 4
                let relative = min(1.5, max(0.35, exposure.dose / max(usual, 1)))
                // Indirect-only exposures contribute a fraction, not a full timer reset.
                let indirectScale = exposure.direct == 0 ? min(0.5, exposure.dose / 4) : 1
                latestDuration = base * relative * (0.8 + 0.4 * exposure.effort) * indirectScale
                latestDuration *= feedback.multiplier(for: muscle, asOf: now)
                remaining = min(120, max(remaining, latestDuration) + min(remaining, latestDuration) * 0.25)
                previousDate = exposure.date
            }
            let hoursSince = max(0, now.timeIntervalSince(last.date) / 3600)
            let remainingNow = max(0, remaining - hoursSince)
            let status: RecoveryStatus = remainingNow == 0 ? .ready : (hoursSince / max(remaining, 1) >= 0.7 ? .recovering : .fatigued)
            return RecoveryPattern(muscleGroup: muscle, averageRecoveryHours: remaining,
                optimalRestDays: Int(ceil(remaining / 24)), lastTrainedDate: last.date,
                readyToTrainDate: now.addingTimeInterval(remainingNow * 3600), recoveryStatus: status,
                exposureCredits: last.dose, feedbackCount: feedback.count(for: muscle, asOf: now))
        }.sorted { $0.muscleGroup < $1.muscleGroup }
    }

    private static let baseRecoveryHours: [String: Double] = [
        "chest": 64, "back": 56, "shoulders": 48, "quadriceps": 48, "hamstrings": 56,
        "glutes": 48, "biceps": 40, "triceps": 40, "calves": 36, "core": 36,
        "lats": 56, "traps": 48, "forearms": 36, "lowerBack": 56
    ]
}

/// Optional check-ins gradually adjust the prior; never infer recovery from frequency alone.
@MainActor
public final class RecoveryFeedbackStore {
    private struct Entry: Codable { let muscle: String; let date: Date; let multiplier: Double }
    private let defaults: UserDefaults
    private let key = "analytics.recovery.checkins.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var entries: [Entry] {
        (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }
    public func record(muscle: String, feelsReady: Bool, hoursSince: Double, predictedHours: Double, now: Date = Date()) {
        guard predictedHours > 0, hoursSince >= 0 else { return }
        let ratio = feelsReady ? hoursSince / predictedHours : max(1.1, hoursSince / predictedHours)
        var values = entries.filter { now.timeIntervalSince($0.date) < 90 * 86400 && !($0.muscle == muscle && Calendar.current.isDate($0.date, inSameDayAs: now)) }
        values.append(Entry(muscle: muscle, date: now, multiplier: min(1.4, max(0.6, ratio))))
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: key) }
    }
    public func count(for muscle: String, asOf now: Date) -> Int { recent(muscle, now).count }
    private func recent(_ muscle: String, _ now: Date) -> [Entry] {
        entries.filter { $0.muscle == muscle && $0.date <= now && now.timeIntervalSince($0.date) < 90 * 86400 }
    }
    public func multiplier(for muscle: String, asOf now: Date) -> Double {
        let values = recent(muscle, now)
        let sum = values.reduce(0) { $0 + $1.multiplier }
        return (8 + sum) / Double(8 + values.count)
    }
}
