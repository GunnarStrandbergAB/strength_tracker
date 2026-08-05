import Foundation

// MARK: - Calorie Estimation Result

/// Breakdown of estimated calories for a strength training workout.
///
/// Based on research from:
/// - 2024 Compendium of Physical Activities (Herrmann et al.)
/// - Lytle et al. (2019) — regression model for resistance exercise EE (R²=0.75)
/// - João et al. (2021) — ~6 kcal/min average across intensities
/// - EPOC literature: 6–15% additional expenditure post-session
public struct CalorieEstimationResult: Sendable, Codable, Equatable {
    /// Calories from active exercise time (MET-based)
    public let sessionCalories: Double
    /// Bonus from total volume moved (Lytle coefficient: ~2.5 kcal per 1000 kg)
    public let volumeBonus: Double
    /// Excess Post-Exercise Oxygen Consumption (6–15% of session)
    public let epocCalories: Double
    /// Grand total
    public var totalCalories: Double { sessionCalories + volumeBonus + epocCalories }
    /// Per-exercise breakdown (exercise order -> kcal)
    public let perExerciseCalories: [Int: Double]
}

// MARK: - Service

public struct CalorieEstimationService: Sendable {

    public init() {}

    /// Estimate calories burned during a completed strength training workout.
    ///
    /// - Parameters:
    ///   - workout: A completed workout with exercises and sets.
    ///   - bodyWeightKg: The user's body weight in kilograms.
    /// - Returns: A full calorie breakdown.
    public func estimateCalories(workout: Workout, bodyWeightKg: Double) -> CalorieEstimationResult {
        guard let completedAt = workout.completedAt else {
            return CalorieEstimationResult(sessionCalories: 0, volumeBonus: 0, epocCalories: 0, perExerciseCalories: [:])
        }

        let totalDuration = completedAt.timeIntervalSince(workout.startedAt)
        guard totalDuration > 0, bodyWeightKg > 0 else {
            return CalorieEstimationResult(sessionCalories: 0, volumeBonus: 0, epocCalories: 0, perExerciseCalories: [:])
        }

        var totalSessionCal = 0.0
        var perExercise: [Int: Double] = [:]
        var totalVolumeKg = 0.0
        var compoundSetCount = 0
        var totalCompletedSets = 0
        var totalRPESum = 0.0
        var rpeCount = 0

        // Estimate per-exercise time proportionally from set timestamps or evenly
        let exerciseDurations = estimateExerciseDurations(workout: workout, totalDuration: totalDuration)

        for exercise in workout.exercises {
            let completedSets = exercise.sets.filter { $0.isCompleted && $0.setType != .warmup }
            guard !completedSets.isEmpty else { continue }

            let met = metForExercise(exercise.exercise, sets: completedSets, hasSupersetGroup: exercise.supersetGroup != nil)
            let duration = exerciseDurations[exercise.order] ?? 0

            let exerciseIsCompound = isCompoundExercise(exercise.exercise)
            let (activeTime, restTime) = estimateActiveRestSplit(sets: completedSets, totalDuration: duration, isCompound: exerciseIsCompound)

            // MET formula: kcal = MET × bodyWeight(kg) × time(hours)
            let activeCal = met * bodyWeightKg * (activeTime / 3600.0)
            let restCal = 1.5 * bodyWeightKg * (restTime / 3600.0) // standing rest ≈ 1.5 MET

            let exerciseCal = activeCal + restCal
            totalSessionCal += exerciseCal
            perExercise[exercise.order] = exerciseCal

            // Accumulate volume (kg) — drop-set segments included
            let exerciseVolumeKg = completedSets.reduce(0.0) { sum, set in
                sum + set.setVolume(weightSubstitute: exercise.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : nil)
            }
            totalVolumeKg += exerciseVolumeKg

            // Track compound vs isolation ratio
            if isCompoundExercise(exercise.exercise) {
                compoundSetCount += completedSets.count
            }
            totalCompletedSets += completedSets.count

            // Track RPE for EPOC estimation
            for s in completedSets {
                if let rpe = s.rpe {
                    totalRPESum += rpe
                    rpeCount += 1
                }
            }
        }

        // Volume bonus: dynamic Lytle coefficient scaled by compound ratio
        let compoundRatio = totalCompletedSets > 0 ? Double(compoundSetCount) / Double(totalCompletedSets) : 0.5
        let dynamicCoefficient = (1.0 + compoundRatio * 2.5) / 1000.0
        let volumeBonus = totalVolumeKg * dynamicCoefficient

        // EPOC factor: 6–15% of session calories
        let epocFactor = calculateEpocFactor(
            averageRPE: rpeCount > 0 ? totalRPESum / Double(rpeCount) : nil,
            compoundRatio: totalCompletedSets > 0 ? Double(compoundSetCount) / Double(totalCompletedSets) : 0
        )
        let epocCal = totalSessionCal * epocFactor

        return CalorieEstimationResult(
            sessionCalories: totalSessionCal,
            volumeBonus: volumeBonus,
            epocCalories: epocCal,
            perExerciseCalories: perExercise
        )
    }

    // MARK: - MET Lookup

    /// Maps exercise category + muscle group to a MET value.
    ///
    /// Values from the 2024 Compendium of Physical Activities:
    /// - 6.0: Vigorous weight lifting (powerlifting, bodybuilding)
    /// - 5.0: Squats/deadlifts, slow or explosive effort
    /// - 5.8: Circuit training, supersets
    /// - 3.5: Multiple exercises, 8–15 reps, varied resistance
    /// - 6.5: Bodyweight exercises, high intensity
    /// - 3.0: Bodyweight exercises, general
    /// - 9.8: Kettlebell swings
    func metForExercise(_ exercise: Exercise, sets: [ExerciseSet], hasSupersetGroup: Bool) -> Double {
        // Supersets get circuit training MET
        if hasSupersetGroup {
            return 5.8
        }

        let isCompound = isCompoundExercise(exercise)

        switch exercise.category {
        case .kettlebell:
            // Kettlebells are uniquely high-MET
            return isCompound ? 9.0 : 6.0

        case .barbell, .trapBar, .ezBar:
            return isCompound ? 5.5 : 4.0

        case .dumbbell:
            return isCompound ? 5.0 : 3.5

        case .bodyweight:
            // Check average RPE of sets to determine intensity
            let avgRPE = averageRPE(sets)
            if let rpe = avgRPE, rpe >= 8.0 {
                return 6.5 // High intensity bodyweight
            }
            return isCompound ? 4.5 : 3.0

        case .machine, .cable, .smithMachine:
            return isCompound ? 4.0 : 3.5

        case .resistanceBand, .trx:
            return isCompound ? 4.0 : 3.0

        case .plate, .medicineBall, .exerciseBall:
            return 4.0

        case .landmine:
            return 5.0

        case .other:
            return 3.5
        }
    }

    // MARK: - Compound Detection

    /// An exercise is "compound" if it targets a large muscle group
    /// (chest, back, legs, glutes, full body) with a free-weight or bodyweight category.
    func isCompoundExercise(_ exercise: Exercise) -> Bool {
        let largeMuscleGroups: Set<MuscleGroup> = [
            .chest, .back, .quadriceps, .hamstrings, .glutes, .lats, .fullBody
        ]
        return largeMuscleGroups.contains(exercise.primaryMuscleGroup)
    }

    // MARK: - Active/Rest Time Split

    /// Estimate how much of the exercise duration was actual lifting vs rest.
    ///
    /// If set completedAt timestamps are available, use them to compute time under load.
    /// Otherwise, use a heuristic: ~30s active per set, remainder is rest.
    func estimateActiveRestSplit(sets: [ExerciseSet], totalDuration: TimeInterval, isCompound: Bool = true) -> (active: TimeInterval, rest: TimeInterval) {
        guard totalDuration > 0 else { return (0, 0) }

        // Compound exercises (squat, bench, etc.) take longer per set than isolation
        let estimatedActivePerSet: TimeInterval = isCompound ? 40.0 : 25.0
        let activeTime = min(Double(sets.count) * estimatedActivePerSet, totalDuration * 0.5)
        let restTime = totalDuration - activeTime

        return (activeTime, restTime)
    }

    // MARK: - EPOC Factor

    /// Calculate the EPOC multiplier (0.06–0.15) based on workout intensity.
    ///
    /// Higher intensity (higher RPE, more compound movements) → higher EPOC.
    func calculateEpocFactor(averageRPE: Double?, compoundRatio: Double) -> Double {
        let minEpoc = 0.06
        let maxEpoc = 0.15

        let maxEpocCapped = 0.10 // Cap EPOC at 10% (literature upper bound for resistance training)

        // If RPE is available, use it as primary signal (scale 1-10 → 0-1)
        if let rpe = averageRPE {
            let normalizedRPE = max(0, min(1, (rpe - 4.0) / 6.0)) // RPE 4→0, RPE 10→1
            return minEpoc + normalizedRPE * (maxEpocCapped - minEpoc)
        }

        // Fallback: use compound ratio as proxy for intensity
        return minEpoc + compoundRatio * (maxEpocCapped - minEpoc)
    }

    // MARK: - Exercise Duration Estimation

    /// Distributes total workout duration across exercises proportionally by completed set count.
    func estimateExerciseDurations(workout: Workout, totalDuration: TimeInterval) -> [Int: TimeInterval] {
        let totalSets = workout.exercises.reduce(0) { total, ex in
            total + ex.sets.filter { $0.isCompleted }.count
        }
        guard totalSets > 0 else { return [:] }

        var result: [Int: TimeInterval] = [:]
        for exercise in workout.exercises {
            let completedCount = exercise.sets.filter { $0.isCompleted }.count
            let proportion = Double(completedCount) / Double(totalSets)
            result[exercise.order] = totalDuration * proportion
        }
        return result
    }

    // MARK: - Helpers

    private func averageRPE(_ sets: [ExerciseSet]) -> Double? {
        let rpes = sets.compactMap(\.rpe)
        guard !rpes.isEmpty else { return nil }
        return rpes.reduce(0, +) / Double(rpes.count)
    }
}
