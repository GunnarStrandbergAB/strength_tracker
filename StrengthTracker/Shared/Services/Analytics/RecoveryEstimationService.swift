import Foundation

/// Estimates muscle group recovery status based on time since last training,
/// volume, and intensity.
@MainActor
public final class RecoveryEstimationService: Sendable {

    private let workoutRepository: any WorkoutRepository

    public init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    /// Compute recovery patterns for all recently trained muscle groups.
    /// Pass pre-fetched `workouts` to include deload data; omit to self-fetch.
    public func computeRecoveryPatterns(workouts: [Workout]? = nil, bodyWeightKg: Double) async throws -> [RecoveryPattern] {
        let allWorkouts: [Workout]
        if let workouts {
            allWorkouts = workouts
        } else {
            allWorkouts = try await workoutRepository.fetchAll()
        }
        let completedWorkouts = allWorkouts.filter { $0.completedAt != nil }

        guard !completedWorkouts.isEmpty else { return [] }

        let muscleLastTrained = findLastTrainedDates(workouts: completedWorkouts, bodyWeightKg: bodyWeightKg)

        return muscleLastTrained.compactMap { entry in
            let muscleGroup = entry.key
            let (lastDate, sets, effortRatios, avgRPE) = entry.value
            let baseHours = Self.baseRecoveryHours[muscleGroup] ?? 48.0
            let volumeModifier = 1.0 + max(0, Double(sets - 4)) * 0.08
            let meanEffort = effortRatios.isEmpty ? 0.75 : effortRatios.reduce(0, +) / Double(effortRatios.count)

            // Blend RPE into intensity when available
            let blendedEffort: Double
            if let rpe = avgRPE {
                let rpeEffort = rpe / 10.0
                blendedEffort = (meanEffort + rpeEffort) / 2.0
            } else {
                blendedEffort = meanEffort
            }
            let intensityModifier = 0.8 + blendedEffort * 0.4

            let adjustedHours = baseHours * volumeModifier * intensityModifier
            let hoursSinceTrained = Date().timeIntervalSince(lastDate) / 3600.0
            let recoveryPct = min(hoursSinceTrained / adjustedHours, 1.0)

            let status: RecoveryStatus
            if recoveryPct >= 1.0 {
                status = .ready
            } else if recoveryPct >= 0.7 {
                status = .recovering
            } else {
                status = .fatigued
            }

            let readyDate = lastDate.addingTimeInterval(adjustedHours * 3600)

            return RecoveryPattern(
                muscleGroup: muscleGroup,
                averageRecoveryHours: adjustedHours,
                optimalRestDays: Int((adjustedHours / 24.0).rounded(.up)),
                lastTrainedDate: lastDate,
                readyToTrainDate: readyDate,
                recoveryStatus: status
            )
        }
        .sorted { $0.muscleGroup < $1.muscleGroup }
    }

    // MARK: - Private

    /// Find last trained date, set count, effort ratios, and average RPE for each muscle group.
    private func findLastTrainedDates(
        workouts: [Workout],
        bodyWeightKg: Double
    ) -> [String: (lastDate: Date, sets: Int, effortRatios: [Double], avgRPE: Double?)] {
        let bestE1RM = AnalyticsCalculations.buildBestE1RMMap(from: workouts, bodyWeightKg: bodyWeightKg)
        let twoWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -AnalyticsCalculations.Windows.recoveryLookbackWeeks, to: Date())!

        var result: [String: (lastDate: Date, sets: Int, effortRatios: [Double], avgRPE: Double?)] = [:]

        // Only look at recent workouts for current recovery state
        let recentWorkouts = workouts
            .filter { ($0.completedAt ?? $0.startedAt) >= twoWeeksAgo }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }

        for workout in recentWorkouts {
            let workoutDate = workout.completedAt ?? workout.startedAt
            for we in workout.exercises {
                let hardSets = we.sets.filter { $0.isCompleted && $0.setType != .warmup }
                guard !hardSets.isEmpty else { continue }

                let primary = we.exercise.primaryMuscleGroup.rawValue

                // Calculate effort ratios for this exercise (effective loads)
                let baseLoad = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                var effortRatios: [Double] = []
                if let best = bestE1RM[we.exercise.id], best > 0 {
                    for set in hardSets {
                        for part in set.effectiveLoadParts(baseLoadPerRep: baseLoad) {
                            let e1rm = AnalyticsCalculations.calculateOneRM(weight: part.load, reps: min(part.reps, 15))
                            effortRatios.append(e1rm / best)
                        }
                    }
                }

                // Calculate average RPE for this exercise
                let rpeValues = hardSets.compactMap(\.rpe)
                let avgRPE: Double? = rpeValues.isEmpty ? nil : rpeValues.reduce(0, +) / Double(rpeValues.count)

                // Update primary muscle group
                if result[primary] == nil || workoutDate > result[primary]!.lastDate {
                    result[primary] = (workoutDate, hardSets.count, effortRatios, avgRPE)
                }

                // Update secondary muscle groups — same set-credit policy as
                // volume landmarks: 0.5 per set split across all secondaries.
                let credits = AnalyticsCalculations.attributeHardSetCredits(
                    hardSets: hardSets.count,
                    primaryMuscle: we.exercise.primaryMuscleGroup,
                    secondaryMuscles: we.exercise.secondaryMuscleGroups
                )
                for secondary in we.exercise.secondaryMuscleGroups {
                    let key = secondary.rawValue
                    if result[key] == nil || workoutDate > result[key]!.lastDate {
                        let credit = credits[secondary] ?? 0
                        result[key] = (workoutDate, Int(credit.rounded()), effortRatios, avgRPE)
                    }
                }
            }
        }

        return result
    }

    // MARK: - Base Recovery Hours

    private static let baseRecoveryHours: [String: Double] = [
        "chest": 64,
        "back": 56,
        "shoulders": 48,
        "quadriceps": 48,
        "hamstrings": 56,
        "glutes": 48,
        "biceps": 40,
        "triceps": 40,
        "calves": 36,
        "core": 36,
        "lats": 56,
        "traps": 48,
        "forearms": 36,
        "lowerBack": 56,
    ]
}
