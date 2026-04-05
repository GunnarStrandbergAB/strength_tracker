import Foundation

/// Suggests weights for upcoming sets based on recent performance, recovery, and overload trends.
@MainActor
public final class WeightSuggestionService: Sendable {

    public init() {}

    /// Suggest a weight for an exercise at the given target rep count.
    public func suggest(
        exerciseId: UUID,
        exerciseName: String,
        targetReps: Int,
        recentWorkouts: [Workout],
        overloadTrend: OverloadTrend?,
        recoveryStatus: RecoveryStatus?,
        trainingLoad: TrainingLoad?,
        isDeload: Bool
    ) -> WeightSuggestion? {
        guard targetReps > 0 else { return nil }

        // Find best recent e1RM for this exercise
        let bestE1RM = bestRecentE1RM(exerciseId: exerciseId, workouts: recentWorkouts)
        guard let e1rm = bestE1RM, e1rm > 0 else { return nil }

        var modifiers: [String] = []
        var adjustedE1RM = e1rm

        // Apply overload trend extrapolation
        if let trend = overloadTrend, trend.trendStatus == .progressing {
            let weeksSinceLast = weeksSinceLastSession(exerciseId: exerciseId, workouts: recentWorkouts)
            let extrapolation = trend.slopePerWeek * weeksSinceLast
            if extrapolation > 0 {
                adjustedE1RM += extrapolation
                modifiers.append(String(format: "Trend: +%.1f kg/wk", trend.slopePerWeek))
            }
        }

        // No coaching suggestions during deload — weights are intentionally reduced
        if isDeload {
            return nil
        }

        // Recovery modifier
        if let recovery = recoveryStatus {
            switch recovery {
            case .fatigued:
                adjustedE1RM *= 0.90
                modifiers.append("Recovery: -10%")
            case .recovering:
                adjustedE1RM *= 0.95
                modifiers.append("Recovery: -5%")
            case .ready:
                break
            }
        }

        // ACWR modifier
        if let load = trainingLoad {
            switch load.loadZone {
            case .danger:
                adjustedE1RM *= 0.85
                modifiers.append("High ACWR: -15%")
            case .caution:
                adjustedE1RM *= 0.90
                modifiers.append("ACWR caution: -10%")
            case .optimal, .underTraining:
                break
            }
        }

        // Convert e1RM to weight at target reps via inverse Brzycki
        let targetWeight = e1rmToWeight(e1rm: adjustedE1RM, reps: targetReps)
        let rounded = roundToNearest2_5(targetWeight)
        guard rounded > 0 else { return nil }

        let explanation = String(format: "Based on %.0f kg e1RM", e1rm)

        return WeightSuggestion(
            weight: rounded,
            targetReps: targetReps,
            explanation: explanation,
            modifiers: modifiers
        )
    }

    // MARK: - Effort Creep Detection

    /// Check if RPE is monotonically increasing while e1RM is flat or declining.
    public func checkEffortCreep(
        exerciseId: UUID,
        exerciseName: String,
        recentWorkouts: [Workout]
    ) -> EffortCreepWarning? {
        // Collect RPE and e1RM per session for this exercise (last 5 sessions max)
        let sessions = recentWorkouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .compactMap { workout -> (rpe: Double, e1rm: Double)? in
                guard let we = workout.exercises.first(where: { $0.exercise.id == exerciseId }) else { return nil }
                let completedSets = we.sets.filter { $0.isCompleted && $0.setType != .warmup }
                let rpes = completedSets.compactMap(\.rpe).filter { $0 > 0 }
                guard !rpes.isEmpty else { return nil }
                let avgRPE = rpes.reduce(0, +) / Double(rpes.count)

                let e1rms = completedSets.compactMap { set -> Double? in
                    guard let w = set.weight, w > 0, let r = set.reps, r > 0 else { return nil }
                    return AnalyticsCalculations.calculateOneRM(weight: w, reps: min(r, 15))
                }
                guard let best = e1rms.max() else { return nil }
                return (avgRPE, best)
            }
            .suffix(5)

        guard sessions.count >= 3 else { return nil }

        // Check RPE trend: monotonically increasing or slope > 0.3/session
        let rpeValues = sessions.map(\.rpe)
        let xs = rpeValues.indices.map { Double($0) }
        guard let regression = AnalyticsCalculations.linearRegression(xs: xs, ys: rpeValues) else { return nil }
        guard regression.slope > 0.3 else { return nil }

        // Check e1RM trend: flat or declining (slope ≤ 0)
        let e1rmValues = sessions.map(\.e1rm)
        guard let e1rmReg = AnalyticsCalculations.linearRegression(xs: xs, ys: e1rmValues) else { return nil }
        guard e1rmReg.slope <= 0 else { return nil }

        let rpeIncrease = (rpeValues.last ?? 0) - (rpeValues.first ?? 0)
        return EffortCreepWarning(
            exerciseName: exerciseName,
            rpeIncrease: rpeIncrease,
            sessionsTracked: sessions.count,
            message: String(format: "RPE climbing (+%.1f over %d sessions) without strength gains", rpeIncrease, sessions.count)
        )
    }

    // MARK: - Private Helpers

    private func bestRecentE1RM(exerciseId: UUID, workouts: [Workout]) -> Double? {
        let e1rmMap = AnalyticsCalculations.buildBestE1RMMap(from: workouts, windowMonths: 3)
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
