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
        verdict: TrainingVerdict? = nil, recordingReference: Exercise? = nil, now: Date = Date()
    ) -> WeightSuggestion? {
        let eligible = recentWorkouts.filter {
            $0.completedAt != nil && !$0.isDeload && $0.trainingDate <= now
                && $0.trainingDate >= now.addingTimeInterval(-90 * 86400)
        }
        guard !isDeload,
              let exercise = recordingReference ?? WeightRecordingHistory.latestExercises(eligible)[exerciseId],
              exercise.id == exerciseId,
              exercise.exerciseType == .weightedReps || exercise.exerciseType == .bodyweightReps,
              !exercise.isDumbbell || exercise.weightRecording != nil,
              let strengthReps = exercise.strengthReps(targetReps),
              (1...AnalyticsCalculations.maxRepsForE1RM).contains(strengthReps) else { return nil }

        // Three distinct sessions for THIS exercise, in the active recording convention.
        // Keep the original observation alongside the converted estimate for explanation.
        let evidence = sessionEvidence(workouts: eligible, exercise: exercise, bodyWeightKg: bodyWeightKg)
        guard evidence.count == 3 else { return nil }
        let e1rm = evidence.map(\.estimatedStrength).sorted()[1]
        guard e1rm.isFinite, e1rm > 0 else { return nil }

        var modifiers: [String] = []
        var adjustedE1RM = e1rm

        // Trend extrapolation only while the verdict allows progressing
        let allowsExtrapolation = (verdict?.kind ?? .progress) == .progress
        let latestBasis = WeightRecordingHistory.latestExercises(eligible)[exerciseId]?.performanceConvention
        let usesLatestBasis = exercise.performanceConvention == latestBasis
        if allowsExtrapolation, usesLatestBasis, let trend = overloadTrend, trend.trendStatus == .progressing {
            let weeksSinceLast = min(1, max(0, now.timeIntervalSince(evidence[0].date) / (7 * 86400)))
            let extrapolation = trend.slopePerWeek * weeksSinceLast
            if extrapolation.isFinite, extrapolation > 0 {
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

        guard var targetWeight = AnalyticsCalculations.weightAtReps(e1rm: adjustedE1RM, reps: strengthReps) else { return nil }
        targetWeight -= exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg) ?? 0
        guard targetWeight.isFinite, targetWeight > 0 else { return nil }

        // This is an estimate, not a claim about available equipment. Round only
        // display precision, in per-dumbbell units so each and total stay equivalent.
        let count = exercise.strengthRecording.map { $0.weightEntry == .combined ? $0.equipment.count : 1 } ?? 1
        let rounded = (targetWeight / count * 100).rounded() / 100 * count
        guard rounded > 0 else { return nil }

        return WeightSuggestion(
            weight: rounded, targetReps: targetReps,
            explanation: "Median strength estimate from the latest three comparable sessions within 90 days. Equipment increments are unknown; choose an available weight near this estimate.",
            modifiers: modifiers, exercise: exercise, evidence: evidence
        )
    }

    private func sessionEvidence(workouts: [Workout], exercise: Exercise, bodyWeightKg: Double) -> [WeightSuggestion.Evidence] {
        var result: [WeightSuggestion.Evidence] = []
        var seen: Set<UUID> = []
        for workout in workouts.sorted(by: { $0.trainingDate == $1.trainingDate ? $0.id.uuidString < $1.id.uuidString : $0.trainingDate > $1.trainingDate }) {
            guard seen.insert(workout.id).inserted else { continue }
            var candidates: [WeightSuggestion.Evidence] = []
            for entry in workout.exercises where entry.exercise.id == exercise.id {
                guard entry.exercise.performanceConvention == exercise.performanceConvention
                        || WeightRecordingHistory.convertible(entry.exercise, to: exercise) else { continue }
                let converted = WeightRecordingHistory.converted(entry, to: exercise)
                for (source, set) in zip(entry.sets, converted.sets) {
                    guard set.isCompleted, set.dropSets.isEmpty,
                          set.setType == .normal || set.setType == .failure,
                          let reps = set.reps, let count = exercise.strengthReps(reps),
                          (1...AnalyticsCalculations.maxRepsForE1RM).contains(count),
                          let part = set.strengthParts(baseLoadPerRep: exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg), recording: exercise.strengthRecording).first else { continue }
                    let estimate = AnalyticsCalculations.calculateOneRM(weight: part.load, reps: part.reps)
                    guard estimate.isFinite, estimate > 0 else { continue }
                    candidates.append(.init(workoutId: workout.id, date: workout.trainingDate,
                        originalExercise: entry.exercise, originalWeight: source.weight ?? 0, reps: reps,
                        convertedWeight: set.weight ?? 0, estimatedStrength: estimate))
                }
            }
            // Separate-side rows have no left/right identity: never assume the
            // stronger row represents both sides. Use the lower estimate.
            let sorted = candidates.sorted { $0.estimatedStrength < $1.estimatedStrength }
            let hasSeparateSides = exercise.strengthRecording?.repetitions == .oneSide || candidates.contains { $0.originalExercise.strengthRecording?.repetitions == .oneSide }
            let observation = hasSeparateSides ? sorted.first : sorted.last
            if let observation { result.append(observation) }
            if result.count == 3 { break }
        }
        return result
    }

    // MARK: - Effort Creep Detection

    /// RPE rising across recent sessions while e1RM is flat or declining. Deload
    /// sessions are excluded (a deload followed by normal sessions is not creep).
    public func checkEffortCreep(
        exerciseId: UUID,
        exerciseName: String,
        recentWorkouts: [Workout],
        bodyWeightKg: Double, recordingReference: Exercise? = nil
    ) -> EffortCreepWarning? {
        // Collect RPE and e1RM per session for this exercise (last 5 sessions max)
        let sessions = WeightRecordingHistory.matching(recentWorkouts, references: recordingReference.map { [$0.id: $0] })
            .filter { $0.completedAt != nil && !$0.isDeload }
            .sorted { $0.trainingDate < $1.trainingDate }
            .compactMap { workout -> (rpe: Double, e1rm: Double)? in
                guard let we = workout.exercises.first(where: { $0.exercise.id == exerciseId }) else { return nil }
                let completedSets = we.sets.filter { $0.isCompleted && $0.setType != .warmup }
                let rpes = completedSets.compactMap(\.rpe).filter { $0 > 0 }
                guard !rpes.isEmpty else { return nil }
                let avgRPE = rpes.reduce(0, +) / Double(rpes.count)

                let base = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                guard let best = AnalyticsCalculations.bestE1RM(in: completedSets, baseLoadPerRep: base, recording: we.exercise.strengthRecording) else { return nil }
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

}
