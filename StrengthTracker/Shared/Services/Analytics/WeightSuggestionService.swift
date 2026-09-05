import Foundation

/// Suggests weights for upcoming sets based on recent performance, recovery, overload
/// trends and the shared training verdict.
@MainActor
public final class WeightSuggestionService: Sendable {

    /// Stacked reductions (recovery, ACWR, verdict) never take more than this off the e1RM.
    public static let maximumReduction = 0.20

    public init() {}

    /// Suggest a weight for an exercise at the given target rep count.
    /// - `verdict`: the shared coach verdict. `.hold` skips trend extrapolation,
    ///   `.deload` skips it and takes 10% off; `.progress` (or nil) extrapolates.
    public func suggest(
        exerciseId: UUID,
        exerciseName: String,
        targetReps: Int,
        recentWorkouts: [Workout],
        overloadTrend: OverloadTrend?,
        recoveryStatus: RecoveryStatus?,
        trainingLoad: TrainingLoad?,
        isDeload: Bool,
        bodyWeightKg: Double,
        verdict: TrainingVerdict? = nil
    ) -> WeightSuggestion? {
        guard targetReps > 0 else { return nil }

        // No coaching suggestions during a deload session — weights are intentionally reduced
        if isDeload { return nil }

        // Best recent e1RM (effective load) for this exercise, deload sessions excluded
        let history = recentWorkouts.filter { !$0.isDeload }
        guard let e1rm = bestRecentE1RM(exerciseId: exerciseId, workouts: history, bodyWeightKg: bodyWeightKg), e1rm > 0 else {
            return nil
        }

        var modifiers: [String] = []
        var adjustedE1RM = e1rm

        // Trend extrapolation only while the verdict allows progressing
        let allowsExtrapolation = (verdict?.kind ?? .progress) == .progress
        if allowsExtrapolation, let trend = overloadTrend, trend.trendStatus == .progressing {
            let weeksSinceLast = weeksSinceLastSession(exerciseId: exerciseId, workouts: history)
            let extrapolation = trend.slopePerWeek * weeksSinceLast
            if extrapolation > 0 {
                adjustedE1RM += extrapolation
                modifiers.append(String(format: "Trend: +%.1f kg/wk", trend.slopePerWeek))
            }
        }
        let baseline = adjustedE1RM
        var reduction = 1.0

        if let verdict, verdict.kind == .deload {
            reduction *= 0.90
            modifiers.append("Coach: deload -10%")
        }

        if let recovery = recoveryStatus {
            switch recovery {
            case .fatigued:
                reduction *= 0.90
                modifiers.append("Recovery: -10%")
            case .recovering:
                reduction *= 0.95
                modifiers.append("Recovery: -5%")
            case .ready:
                break
            }
        }

        if let load = trainingLoad {
            switch load.loadZone {
            case .danger:
                reduction *= 0.85
                modifiers.append("Very high load: -15%")
            case .caution:
                reduction *= 0.90
                modifiers.append("High load: -10%")
            case .optimal, .underTraining:
                break
            }
        }

        // Cap the stacked reductions so three mild signals never halve the weight.
        if reduction < 1 - Self.maximumReduction {
            reduction = 1 - Self.maximumReduction
            modifiers.append(String(format: "Capped at -%.0f%%", Self.maximumReduction * 100))
        }
        adjustedE1RM = baseline * reduction

        // Convert e1RM to weight at target reps via inverse Brzycki. For bodyweight
        // exercises the e1RM is EFFECTIVE load, but the suggestion is shown in the
        // set's weight field, which means EXTRA kg — subtract the bodyweight base
        // and suppress the hint when bodyweight alone covers the target.
        var targetWeight = e1rmToWeight(e1rm: adjustedE1RM, reps: targetReps)
        let exercise = recentWorkouts
            .flatMap(\.exercises)
            .first { $0.exercise.id == exerciseId }?.exercise
        if let base = exercise?.baseLoadPerRep(bodyWeightKg: bodyWeightKg) {
            targetWeight -= base
        }
        let rounded = roundToNearest2_5(targetWeight)
        guard rounded > 0 else { return nil }

        let explanation: String
        if abs(adjustedE1RM - e1rm) >= 0.5 {
            explanation = String(format: "Based on %.0f kg e1RM (adjusted from %.0f kg)", adjustedE1RM, e1rm)
        } else {
            explanation = String(format: "Based on %.0f kg e1RM", e1rm)
        }

        return WeightSuggestion(
            weight: rounded,
            targetReps: targetReps,
            explanation: explanation,
            modifiers: modifiers
        )
    }

    // MARK: - Effort Creep Detection

    /// RPE rising across recent sessions while e1RM is flat or declining. Deload
    /// sessions are excluded (a deload followed by normal sessions is not creep).
    public func checkEffortCreep(
        exerciseId: UUID,
        exerciseName: String,
        recentWorkouts: [Workout],
        bodyWeightKg: Double
    ) -> EffortCreepWarning? {
        // Collect RPE and e1RM per session for this exercise (last 5 sessions max)
        let sessions = recentWorkouts
            .filter { $0.completedAt != nil && !$0.isDeload }
            .sorted { $0.trainingDate < $1.trainingDate }
            .compactMap { workout -> (rpe: Double, e1rm: Double)? in
                guard let we = workout.exercises.first(where: { $0.exercise.id == exerciseId }) else { return nil }
                let completedSets = we.sets.filter { $0.isCompleted && $0.setType != .warmup }
                let rpes = completedSets.compactMap(\.rpe).filter { $0 > 0 }
                guard !rpes.isEmpty else { return nil }
                let avgRPE = rpes.reduce(0, +) / Double(rpes.count)

                let base = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                guard let best = AnalyticsCalculations.bestE1RM(in: completedSets, baseLoadPerRep: base) else { return nil }
                return (avgRPE, best)
            }
            .suffix(5)

        guard sessions.count >= 3 else { return nil }

        // RPE trend: slope > 0.3/session
        let rpeValues = sessions.map(\.rpe)
        let xs = rpeValues.indices.map { Double($0) }
        guard let regression = AnalyticsCalculations.linearRegression(xs: xs, ys: rpeValues) else { return nil }
        guard regression.slope > 0.3 else { return nil }

        // e1RM trend: flat or declining (slope ≤ 0)
        let e1rmValues = sessions.map(\.e1rm)
        guard let e1rmReg = AnalyticsCalculations.linearRegression(xs: xs, ys: e1rmValues) else { return nil }
        guard e1rmReg.slope <= 0 else { return nil }

        let rpeIncrease = (rpeValues.last ?? 0) - (rpeValues.first ?? 0)
        return EffortCreepWarning(
            exerciseName: exerciseName,
            rpeIncrease: rpeIncrease,
            sessionsTracked: sessions.count,
            message: String(format: "RPE up %+.1f over %d sessions while e1RM stayed flat", rpeIncrease, sessions.count)
        )
    }

    // MARK: - Private Helpers

    private func bestRecentE1RM(exerciseId: UUID, workouts: [Workout], bodyWeightKg: Double) -> Double? {
        let e1rmMap = AnalyticsCalculations.buildBestE1RMMap(from: workouts, windowMonths: 3, bodyWeightKg: bodyWeightKg)
        return e1rmMap[exerciseId]
    }

    /// Inverse Brzycki: weight = e1RM × (37 - reps) / 36
    private func e1rmToWeight(e1rm: Double, reps: Int) -> Double {
        if reps == 1 { return e1rm }
        if reps <= 5 {
            // Inverse of Epley: e1RM = weight * (1 + reps/30) → weight = e1RM / (1 + reps/30)
            return e1rm / (1.0 + Double(reps) / 30.0)
        }
        // Inverse of Brzycki: e1RM = weight * 36 / (37 - reps) → weight = e1RM * (37 - reps) / 36
        return e1rm * (37.0 - Double(reps)) / 36.0
    }

    private func roundToNearest2_5(_ value: Double) -> Double {
        (value / 2.5).rounded() * 2.5
    }

    private func weeksSinceLastSession(exerciseId: UUID, workouts: [Workout]) -> Double {
        let lastDate = workouts
            .filter { $0.completedAt != nil }
            .filter { $0.exercises.contains { $0.exercise.id == exerciseId } }
            .compactMap(\.completedAt)
            .max()

        guard let last = lastDate else { return 0 }
        return Date().timeIntervalSince(last) / (7 * 24 * 3600)
    }
}
