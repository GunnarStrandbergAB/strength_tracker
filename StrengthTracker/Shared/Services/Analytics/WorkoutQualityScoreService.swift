import Foundation

/// Computes a post-workout quality score (0-100) shown on the completion sheet.
/// Score breakdown (25 points each): Volume, Intensity, Rest times, Balance.
@MainActor
public final class WorkoutQualityScoreService: Sendable {

    private let workoutRepository: any WorkoutRepository
    private let muscleBalanceService: MuscleBalanceService
    private let healthKitService: any HealthKitServiceProtocol
    private let userPreferencesService: UserPreferencesService

    /// Cache keyed by workout ID to avoid recomputing scores
    private var cache: [UUID: WorkoutQualityScore] = [:]

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

    /// Compute quality score for a completed workout (fetches history internally)
    public func computeScore(for workout: Workout) async throws -> WorkoutQualityScore {
        if let cached = cache[workout.id] { return cached }

        let recentWorkouts = try await workoutRepository.fetchAll()
        return computeScoreInternal(for: workout, history: recentWorkouts)
    }

    /// Compute quality score with pre-fetched history (avoids N+1 fetchAll calls)
    public func computeScore(for workout: Workout, history: [Workout]) -> WorkoutQualityScore {
        if let cached = cache[workout.id] { return cached }
        return computeScoreInternal(for: workout, history: history)
    }

    private func computeScoreInternal(for workout: Workout, history: [Workout]) -> WorkoutQualityScore {
        let bodyWeightKg = userPreferencesService.bodyWeightKg
            ?? UserPreferencesService.defaultBodyWeightKg

        let volumeScore: Double
        let intensityScore: Double
        let consistencyScore = computeConsistencyScore(workout)
        let balanceScore = computeBalanceScore(workout, history: history)

        if workout.isDeload {
            // Deload scoring: reward ~50% volume and ~70% intensity
            volumeScore = computeDeloadVolumeScore(workout, history: history, bodyWeightKg: bodyWeightKg)
            intensityScore = computeDeloadIntensityScore(workout, history: history)
        } else {
            volumeScore = computeVolumeScore(workout, history: history, bodyWeightKg: bodyWeightKg)
            intensityScore = computeIntensityScore(workout, history: history)
        }

        let overall = (volumeScore + intensityScore + consistencyScore + balanceScore) / 4.0

        let score = WorkoutQualityScore(
            id: UUID(),
            workoutId: workout.id,
            overallScore: overall,
            volumeScore: volumeScore,
            intensityScore: intensityScore,
            balanceScore: balanceScore,
            consistencyScore: consistencyScore
        )
        cache[workout.id] = score
        return score
    }

    // MARK: - Aggregate Quality

    /// Compute EWMA-smoothed aggregate quality across all completed workouts.
    public func computeAggregateScore(workouts: [Workout]) -> AggregateQualityScore {
        let completed = workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }

        let now = Date()

        guard !completed.isEmpty else {
            return AggregateQualityScore(
                ewmaOverall: 0, ewmaVolume: 0, ewmaIntensity: 0,
                ewmaBalance: 0, ewmaConsistency: 0,
                trendVsPrior: 0, percentileRank: 0,
                workoutsIncluded: 0, computedAt: now
            )
        }

        // Compute per-workout scores (using pre-fetched history via cache-aware overload)
        let scores = completed.map { computeScore(for: $0, history: workouts) }

        let overallValues = scores.map(\.overallScore)
        let volumeValues = scores.map(\.volumeScore)
        let intensityValues = scores.map(\.intensityScore)
        let balanceValues = scores.map(\.balanceScore)
        let consistencyValues = scores.map(\.consistencyScore)

        // Cold start: < 3 workouts → simple average (EWMA with 1-2 points is meaningless)
        let useColdStart = completed.count < 3

        let lambda = 0.3
        let ewmaOverall: [Double]
        let ewmaVolume: [Double]
        let ewmaIntensity: [Double]
        let ewmaBalance: [Double]
        let ewmaConsistency: [Double]

        if useColdStart {
            let avgOverall = overallValues.reduce(0, +) / Double(overallValues.count)
            let avgVolume = volumeValues.reduce(0, +) / Double(volumeValues.count)
            let avgIntensity = intensityValues.reduce(0, +) / Double(intensityValues.count)
            let avgBalance = balanceValues.reduce(0, +) / Double(balanceValues.count)
            let avgConsistency = consistencyValues.reduce(0, +) / Double(consistencyValues.count)

            return AggregateQualityScore(
                ewmaOverall: avgOverall, ewmaVolume: avgVolume,
                ewmaIntensity: avgIntensity, ewmaBalance: avgBalance,
                ewmaConsistency: avgConsistency,
                trendVsPrior: 0, percentileRank: 0.5,
                workoutsIncluded: completed.count, computedAt: now
            )
        } else {
            ewmaOverall = AnalyticsCalculations.ewma(values: overallValues, lambda: lambda)
            ewmaVolume = AnalyticsCalculations.ewma(values: volumeValues, lambda: lambda)
            ewmaIntensity = AnalyticsCalculations.ewma(values: intensityValues, lambda: lambda)
            ewmaBalance = AnalyticsCalculations.ewma(values: balanceValues, lambda: lambda)
            ewmaConsistency = AnalyticsCalculations.ewma(values: consistencyValues, lambda: lambda)
        }

        let currentOverall = ewmaOverall.last!

        // Trend: compare current EWMA vs EWMA ~4 weeks ago
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: now)!
        let priorIndex = completed.firstIndex { ($0.completedAt ?? .distantPast) >= fourWeeksAgo } ?? 0
        let priorOverall = ewmaOverall[priorIndex]
        let trend: Double
        if priorOverall > 0 && priorIndex < ewmaOverall.count - 1 {
            trend = ((currentOverall - priorOverall) / priorOverall) * 100
        } else {
            trend = 0
        }

        // Percentile: where current sits in EWMA history
        let sorted = ewmaOverall.sorted()
        let rank = sorted.firstIndex { $0 >= currentOverall } ?? sorted.count
        let percentile = Double(rank) / Double(max(sorted.count, 1))

        return AggregateQualityScore(
            ewmaOverall: currentOverall,
            ewmaVolume: ewmaVolume.last!,
            ewmaIntensity: ewmaIntensity.last!,
            ewmaBalance: ewmaBalance.last!,
            ewmaConsistency: ewmaConsistency.last!,
            trendVsPrior: trend,
            percentileRank: percentile,
            workoutsIncluded: completed.count,
            computedAt: now
        )
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
                    let setIWV = AnalyticsCalculations.setIWV(for: set, bestE1RM: bestE1RM[we.exercise.id])
                    guard setIWV > 0 else { continue }

                    let attributed = AnalyticsCalculations.attributeVolume(
                        volume: setIWV,
                        primaryMuscle: we.exercise.primaryMuscleGroup,
                        secondaryMuscles: we.exercise.secondaryMuscleGroups
                    )
                    for (muscle, vol) in attributed {
                        iwv[muscle, default: 0] += vol
                    }
                }
            }
        }
        return iwv
    }

    // MARK: - Scoring Components (0-100 scale each)

    /// Per-muscle-group volume comparison against 12-week per-session averages.
    ///
    /// Deload workouts are intentionally ~50% volume and would otherwise drag the
    /// rolling baseline down, making every regular workout look like an overshoot.
    /// They're excluded from the baseline here, mirroring `computeDeloadVolumeScore`.
    private func computeVolumeScore(_ workout: Workout, history: [Workout], bodyWeightKg: Double) -> Double {
        let twelveWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date())!

        let historyWorkouts = history.filter {
            $0.id != workout.id &&
            !$0.isDeload &&
            $0.completedAt != nil &&
            ($0.completedAt ?? $0.startedAt) >= twelveWeeksAgo
        }

        // Per-muscle-group raw volume for current workout (70/30 split)
        var currentMuscleVol: [MuscleGroup: Double] = [:]
        for we in workout.exercises {
            for set in we.sets {
                guard set.isCompleted, set.setType != .warmup else { continue }
                let vol = set.setVolume(weightSubstitute: we.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : nil)

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
                    let vol = set.setVolume(weightSubstitute: we.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : nil)

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
            let groupScore: Double
            if ratio >= 0.8 {
                // Matching or exceeding the rolling average: progressive overload
                // is the goal; the Volume sub-score should not penalize doing more.
                // Over-training concerns are surfaced via Balance / Consistency.
                groupScore = 100.0
            } else {
                // Below 0.8x average: linear penalty toward 0.
                groupScore = max(0, ratio / 0.8 * 100.0)
            }
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
        let completedSets = workout.exercises
            .flatMap { $0.sets }
            .filter { $0.isCompleted && $0.setType != .warmup && $0.completedAt != nil }
            .sorted { $0.completedAt! < $1.completedAt! }

        guard completedSets.count >= 2 else { return 72.0 }

        var intervals: [TimeInterval] = []
        for i in 1..<completedSets.count {
            let interval = completedSets[i].completedAt!.timeIntervalSince(completedSets[i - 1].completedAt!)
            if interval <= 600 && interval > 15 { // Filter out superset/drop-set transitions
                intervals.append(interval)
            }
        }

        guard intervals.count >= 2 else { return 80.0 }

        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 0

        // Low CV = consistent rest periods = high score
        // CV < 0.25 = very consistent, CV > 0.8 = very erratic
        if cv <= 0.25 {
            return 100.0
        } else if cv <= 0.8 {
            return 100.0 - (cv - 0.25) * (70.0 / 0.55)
        } else {
            return 30.0
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

    // MARK: - Deload Scoring

    /// Deload volume: rewards ~50% of historical average. Too high (>70%) or too low (<30%) scores drop.
    private func computeDeloadVolumeScore(_ workout: Workout, history: [Workout], bodyWeightKg: Double) -> Double {
        let twelveWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date())!
        let historyWorkouts = history.filter {
            $0.id != workout.id && !$0.isDeload && $0.completedAt != nil
            && ($0.completedAt ?? $0.startedAt) >= twelveWeeksAgo
        }

        let currentVolume = workout.totalVolume(bodyWeightKg: bodyWeightKg)
        guard !historyWorkouts.isEmpty else { return 80.0 }

        let avgVolume = historyWorkouts.map { $0.totalVolume(bodyWeightKg: bodyWeightKg) }
            .reduce(0, +) / Double(historyWorkouts.count)
        guard avgVolume > 0 else { return 80.0 }

        let ratio = currentVolume / avgVolume
        // Sweet spot: 40-60% → 100. Taper to 0 outside 20-80%.
        if ratio >= 0.4 && ratio <= 0.6 {
            return 100.0
        } else if ratio < 0.4 {
            return max(0, 100.0 * (ratio - 0.2) / 0.2)
        } else {
            return max(0, 100.0 * (0.8 - ratio) / 0.2)
        }
    }

    /// Deload intensity: rewards ~60-80% of historical best e1RM. ~70% = 100.
    private func computeDeloadIntensityScore(_ workout: Workout, history: [Workout]) -> Double {
        let nonDeloadHistory = history.filter { !$0.isDeload }
        let bestE1RM = buildBestE1RMMap(excluding: workout.id, from: nonDeloadHistory)

        var ratios: [Double] = []
        for we in workout.exercises {
            for set in we.sets {
                guard set.isCompleted, set.setType != .warmup,
                      let weight = set.weight, weight > 0,
                      let reps = set.reps, reps > 0 else { continue }
                guard let historicalBest = bestE1RM[we.exercise.id], historicalBest > 0 else { continue }
                let setE1RM = TrainingStatusDetector.calculateOneRM(weight: weight, reps: min(reps, 15))
                ratios.append(setE1RM / historicalBest)
            }
        }

        guard !ratios.isEmpty else { return 75.0 }
        let mean = ratios.reduce(0, +) / Double(ratios.count)
        // Sweet spot: 0.6-0.8 → 100. Taper outside.
        if mean >= 0.6 && mean <= 0.8 {
            return 100.0
        } else if mean < 0.6 {
            return max(0, 100.0 * (mean - 0.3) / 0.3)
        } else {
            return max(0, 100.0 * (1.0 - mean) / 0.2)
        }
    }
}
