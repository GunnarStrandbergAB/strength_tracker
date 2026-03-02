import Foundation

/// Computes a post-workout quality score (0-100) shown on the completion sheet.
/// Score breakdown (25 points each): Volume, Intensity, Rest times, Balance.
@MainActor
public final class WorkoutQualityScoreService: Sendable {

    private let workoutRepository: any WorkoutRepository
    private let muscleBalanceService: MuscleBalanceService
    private let healthKitService: any HealthKitServiceProtocol
    private let userPreferencesService: UserPreferencesService

    public init(
        workoutRepository: any WorkoutRepository,
        muscleBalanceService: MuscleBalanceService,
        healthKitService: any HealthKitServiceProtocol,
        userPreferencesService: UserPreferencesService
    ) {
        self.workoutRepository = workoutRepository
        self.muscleBalanceService = muscleBalanceService
        self.healthKitService = healthKitService
        self.userPreferencesService = userPreferencesService
    }

    /// Compute quality score for a completed workout
    public func computeScore(for workout: Workout) async throws -> WorkoutQualityScore {
        let recentWorkouts = try await workoutRepository.fetchAll()

        let bodyWeightKg = await healthKitService.fetchBodyWeightKg()
            ?? userPreferencesService.bodyWeightKg
            ?? UserPreferencesService.defaultBodyWeightKg
        let volumeScore = computeVolumeScore(workout, history: recentWorkouts, bodyWeightKg: bodyWeightKg)
        let intensityScore = computeIntensityScore(workout, history: recentWorkouts)
        let consistencyScore = computeConsistencyScore(workout)
        let balanceScore = computeBalanceScore(workout, history: recentWorkouts)

        let overall = (volumeScore + intensityScore + consistencyScore + balanceScore) / 4.0

        return WorkoutQualityScore(
            id: UUID(),
            workoutId: workout.id,
            overallScore: overall,
            volumeScore: volumeScore,
            intensityScore: intensityScore,
            balanceScore: balanceScore,
            consistencyScore: consistencyScore
        )
    }

    /// Alias matching architecture doc naming
    public func scoreWorkout(_ workout: Workout) async throws -> WorkoutQualityScore {
        try await computeScore(for: workout)
    }

    // MARK: - Shared Helpers

    /// Build per-exercise best e1RM map from history, excluding a specific workout.
    private func buildBestE1RMMap(excluding workoutId: UUID, from history: [Workout]) -> [UUID: Double] {
        AnalyticsCalculations.buildBestE1RMMap(excluding: workoutId, from: history)
    }

    /// Compute Intensity-Weighted Volume per muscle group for a set of workouts.
    private func computeMuscleGroupIWV(
        workouts: [Workout],
        bestE1RM: [UUID: Double]
    ) -> [MuscleGroup: Double] {
        var iwv: [MuscleGroup: Double] = [:]
        for workout in workouts {
            for we in workout.exercises {
                for set in we.sets {
                    guard set.isCompleted,
                          set.setType != .warmup,
                          let weight = set.weight, weight > 0,
                          let reps = set.reps, reps > 0 else { continue }

                    let pct1RM: Double
                    if let best = bestE1RM[we.exercise.id], best > 0 {
                        pct1RM = min(weight / best, 1.5)
                    } else {
                        pct1RM = 0.75
                    }
                    let setIWV = Double(reps) * pct1RM

                    iwv[we.exercise.primaryMuscleGroup, default: 0] += 0.7 * setIWV
                    let secondaries = we.exercise.secondaryMuscleGroups
                    if !secondaries.isEmpty {
                        let share = 0.3 * setIWV / Double(secondaries.count)
                        for muscle in secondaries {
                            iwv[muscle, default: 0] += share
                        }
                    }
                }
            }
        }
        return iwv
    }

    // MARK: - Scoring Components (0-100 scale each)

    /// Per-muscle-group volume comparison against 12-week per-session averages.
    private func computeVolumeScore(_ workout: Workout, history: [Workout], bodyWeightKg: Double) -> Double {
        let twelveWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date())!

        let historyWorkouts = history.filter {
            $0.id != workout.id &&
            $0.completedAt != nil &&
            ($0.completedAt ?? $0.startedAt) >= twelveWeeksAgo
        }

        // Per-muscle-group raw volume for current workout (70/30 split)
        var currentMuscleVol: [MuscleGroup: Double] = [:]
        for we in workout.exercises {
            for set in we.sets {
                guard set.isCompleted, set.setType != .warmup else { continue }
                let w = set.weight ?? (we.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0)
                let vol = w * Double(set.reps ?? 0)

                currentMuscleVol[we.exercise.primaryMuscleGroup, default: 0] += vol * 0.7
                let secondaries = we.exercise.secondaryMuscleGroups
                if !secondaries.isEmpty {
                    let share = vol * 0.3 / Double(secondaries.count)
                    for muscle in secondaries {
                        currentMuscleVol[muscle, default: 0] += share
                    }
                }
            }
        }

        guard !currentMuscleVol.isEmpty, !historyWorkouts.isEmpty else { return 80.0 }

        // Per-muscle-group total volume and session count from history
        var historyMuscleVol: [MuscleGroup: Double] = [:]
        var muscleSessionCount: [MuscleGroup: Int] = [:]

        for past in historyWorkouts {
            var musclesInWorkout: Set<MuscleGroup> = []
            for we in past.exercises {
                for set in we.sets {
                    guard set.isCompleted, set.setType != .warmup else { continue }
                    let w = set.weight ?? (we.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0)
                    let vol = w * Double(set.reps ?? 0)

                    historyMuscleVol[we.exercise.primaryMuscleGroup, default: 0] += vol * 0.7
                    musclesInWorkout.insert(we.exercise.primaryMuscleGroup)

                    let secondaries = we.exercise.secondaryMuscleGroups
                    if !secondaries.isEmpty {
                        let share = vol * 0.3 / Double(secondaries.count)
                        for muscle in secondaries {
                            historyMuscleVol[muscle, default: 0] += share
                            musclesInWorkout.insert(muscle)
                        }
                    }
                }
            }
            for muscle in musclesInWorkout {
                muscleSessionCount[muscle, default: 0] += 1
            }
        }

        // Per-muscle-group score
        var groupScores: [Double] = []
        for (muscle, currentVol) in currentMuscleVol {
            guard let histVol = historyMuscleVol[muscle], histVol > 0,
                  let sessions = muscleSessionCount[muscle], sessions > 0 else {
                groupScores.append(80.0)
                continue
            }

            let perSessionAvg = histVol / Double(sessions)
            let ratio = currentVol / perSessionAvg
            let deviation = abs(ratio - 1.0)
            let groupScore = max(0, 100.0 * (1.0 - max(0, deviation - 0.2) / 0.8))
            groupScores.append(groupScore)
        }

        guard !groupScores.isEmpty else { return 80.0 }
        return groupScores.reduce(0, +) / Double(groupScores.count)
    }

    /// Effort-ratio intensity: compares each set's e1RM to the historical best
    /// for that exercise (last 6 months, excluding current workout). Returns 0-100.
    private func computeIntensityScore(_ workout: Workout, history: [Workout]) -> Double {
        let bestE1RM = buildBestE1RMMap(excluding: workout.id, from: history)

        var ratios: [Double] = []
        for we in workout.exercises {
            for set in we.sets {
                guard set.isCompleted,
                      set.setType != .warmup,
                      let weight = set.weight, weight > 0,
                      let reps = set.reps, reps > 0 else { continue }
                guard let historicalBest = bestE1RM[we.exercise.id], historicalBest > 0 else { continue }
                let setE1RM = TrainingStatusDetector.calculateOneRM(weight: weight, reps: min(reps, 15))
                ratios.append(setE1RM / historicalBest)
            }
        }

        guard !ratios.isEmpty else { return 75.0 }
        let mean = ratios.reduce(0, +) / Double(ratios.count)
        return min(max(mean * 100.0, 0), 100)
    }

    private func computeConsistencyScore(_ workout: Workout) -> Double {
        let duration = workout.duration ?? 0
        let setCount = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }.count

        guard setCount > 0, duration > 0 else { return 72.0 }

        let avgTimePerSet = duration / Double(setCount)
        switch avgTimePerSet {
        case 60...180: return 100.0
        case 45...240: return 80.0
        case 30...300: return 50.0
        default:       return 20.0
        }
    }

    /// IWV-based balance score over 12-week window with 6 antagonist pairs.
    private func computeBalanceScore(_ workout: Workout, history: [Workout]) -> Double {
        let twelveWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date())!

        // All completed workouts from last 12 weeks (including current)
        var recentWorkouts = history.filter {
            $0.completedAt != nil && ($0.completedAt ?? $0.startedAt) >= twelveWeeksAgo
        }
        if !recentWorkouts.contains(where: { $0.id == workout.id }) {
            recentWorkouts.append(workout)
        }

        let bestE1RM = buildBestE1RMMap(excluding: workout.id, from: history)
        let iwv = computeMuscleGroupIWV(workouts: recentWorkouts, bestE1RM: bestE1RM)

        let antagonistPairs: [(MuscleGroup, MuscleGroup)] = [
            (.chest, .back),
            (.quadriceps, .hamstrings),
            (.biceps, .triceps),
            (.shoulders, .lats),
            (.core, .lowerBack),
            (.glutes, .hipFlexors)
        ]

        var pairScores: [Double] = []
        for (groupA, groupB) in antagonistPairs {
            let iwvA = iwv[groupA] ?? 0
            let iwvB = iwv[groupB] ?? 0

            if iwvA <= 0 && iwvB <= 0 { continue }

            if iwvA <= 0 || iwvB <= 0 {
                pairScores.append(0)
                continue
            }

            let ratio = max(iwvA, iwvB) / min(iwvA, iwvB)
            let pairScore = max(0, 100.0 * (1.0 - (ratio - 1.0) / 2.0))
            pairScores.append(pairScore)
        }

        guard pairScores.count >= 2 else { return 80.0 }
        return pairScores.reduce(0, +) / Double(pairScores.count)
    }
}
