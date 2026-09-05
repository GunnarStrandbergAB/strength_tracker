import Foundation

/// Bridges planned sessions with actual workout execution.
/// Handles session completion with APRE adjustments and 1RM estimation with EWMA smoothing.
/// (Session preparation lives in ProgressionPlanViewModel.prepareSessionTemplate, which
/// also handles linked-template merging.)
///
/// Design notes (i8):
/// - This service computes *ongoing* 1RM with EWMA smoothing for progressive updates.
/// - TrainingStatusDetector computes *baseline* 1RM without EWMA for plan creation.
/// - These are intentionally separate estimation paths with different purposes.
///
/// EWMA behavior (M16):
/// - Outlier rejection compares against stored (rounded) 1RM, not a running accumulator.
/// - This is a deliberate simplification for v1 — acceptable because the 15% threshold
///   is wide enough to absorb rounding artifacts.
public struct SessionExecutionService: Sendable {

    /// EWMA smoothing factor for 1RM updates
    private let alpha: Double = 0.3

    /// Outlier rejection threshold (15% deviation)
    private let outlierThreshold: Double = 0.15

    /// Regression guard threshold (5% drop required before applying downward adjustment)
    private let regressionThreshold: Double = 0.95

    public init() {}

    // MARK: - Complete Session

    /// Links a completed workout back to the planned session, computes APRE adjustments
    /// and 1RM updates with EWMA smoothing.
    ///
    /// Returns an updated session, adjustment records, and updated plan exercises.
    public func completeSession(
        _ session: PlannedSession,
        workout: Workout,
        planExercises: [PlanExercise],
        bodyWeightKg: Double
    ) -> (updatedSession: PlannedSession, adjustments: [PlanAdjustment], updatedExercises: [PlanExercise]) {
        var updatedSession = session
        updatedSession.completedWorkoutId = workout.id
        updatedSession.completedAt = workout.completedAt ?? Date()
        updatedSession.userWorkoutNotes = workout.notes

        var adjustments: [PlanAdjustment] = []
        var updatedExercises = planExercises

        // Build lookup: exerciseId -> PlanExercise index
        let planExerciseLookup = Dictionary(
            planExercises.enumerated().map { ($1.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for workoutExercise in workout.exercises {
            let exerciseId = workoutExercise.exercise.id

            guard let planIndex = planExerciseLookup[exerciseId] else { continue }
            let planExercise = updatedExercises[planIndex]

            // Skip 1RM updates for deload sessions — intentionally lighter weights
            // should not drag down stored estimates
            guard !session.isDeload && !workout.isDeload else { continue }

            // Estimate 1RM from completed sets
            if let estimated1RM = estimateCurrent1RM(from: workoutExercise.sets, baseLoadPerRep: workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)) {
                let current = planExercise.current1RM

                // M17: When current1RM is 0 (first use), direct assign without EWMA
                if current == 0 {
                    let rounded1RM = estimated1RM.rounded(toNearest: 2.5)
                    if rounded1RM > 0 {
                        updatedExercises[planIndex].current1RM = rounded1RM
                        let adjustment = PlanAdjustment(
                            adjustmentType: .loadIncrease,
                            trigger: .oneRMUpdate,
                            description: "\(planExercise.exerciseName) 1RM initial estimate: \(rounded1RM)",
                            affectedExerciseIds: [planExercise.id],
                            previousValues: ["current1RM": "0.0"],
                            newValues: ["current1RM": String(rounded1RM)]
                        )
                        adjustments.append(adjustment)
                    }
                } else {
                    let deviation = abs(estimated1RM - current) / current

                    // Outlier rejection: skip if deviation > 15%
                    if deviation <= outlierThreshold {
                        // Asymmetric EWMA: accept PRs immediately, smooth downward only
                        let smoothed1RM: Double
                        if estimated1RM >= current {
                            smoothed1RM = estimated1RM
                        } else {
                            smoothed1RM = alpha * estimated1RM + (1.0 - alpha) * current
                        }
                        let rounded1RM = smoothed1RM.rounded(toNearest: 2.5)

                        // Regression guard: only apply downward if estimated < 95% of current
                        // (strict >5% drop, documented behavior per m18)
                        let shouldUpdate: Bool
                        if rounded1RM < current {
                            shouldUpdate = estimated1RM < regressionThreshold * current
                        } else {
                            shouldUpdate = true
                        }

                        if shouldUpdate && rounded1RM != current {
                            let previousValue = current
                            updatedExercises[planIndex].current1RM = rounded1RM

                            let adjustment = PlanAdjustment(
                                adjustmentType: rounded1RM > previousValue ? .loadIncrease : .loadDecrease,
                                trigger: .oneRMUpdate,
                                description: "\(planExercise.exerciseName) 1RM updated: \(previousValue) -> \(rounded1RM)",
                                affectedExerciseIds: [planExercise.id],
                                previousValues: ["current1RM": String(previousValue)],
                                newValues: ["current1RM": String(rounded1RM)]
                            )
                            adjustments.append(adjustment)
                        }
                    }
                }
            }

            // Generate APRE adjustments for next session weights
            if let matchingPlanned = session.plannedExercises.first(where: { $0.exerciseId == exerciseId }) {
                let completedSets = workoutExercise.sets.filter { $0.isCompleted && $0.setType != .warmup }
                if let lastSet = completedSets.last, let actualReps = lastSet.reps {
                    let workingWeight = lastSet.weight ?? matchingPlanned.targetWeight
                    let isLowerBody = [MuscleGroup.quadriceps, .hamstrings, .glutes, .calves]
                        .contains(updatedExercises[planIndex].primaryMuscleGroup)

                    let adjustedWeight = matchingPlanned.apreAdjustedWeight(
                        actualReps: actualReps,
                        workingWeight: workingWeight,
                        isCompound: updatedExercises[planIndex].isCompound,
                        isLowerBody: isLowerBody
                    )

                    if adjustedWeight != workingWeight {
                        let adjustment = PlanAdjustment(
                            adjustmentType: adjustedWeight > workingWeight ? .loadIncrease : .loadDecrease,
                            trigger: .apre,
                            description: "APRE adjustment for \(matchingPlanned.exerciseName): \(workingWeight) -> \(adjustedWeight)",
                            affectedExerciseIds: [updatedExercises[planIndex].id],
                            previousValues: ["targetWeight": String(workingWeight)],
                            newValues: ["targetWeight": String(adjustedWeight)]
                        )
                        adjustments.append(adjustment)
                    }
                }
            }
        }

        return (updatedSession, adjustments, updatedExercises)
    }

    // MARK: - Replay

    /// Recomputes every completed session's contribution from scratch: resets each
    /// PlanExercise.current1RM to its creation baseline (`estimated1RM`), strips the
    /// engine's `.oneRMUpdate`/`.apre` adjustments, and replays `completeSession` over
    /// the completed sessions in completion order. Deterministic, so editing or
    /// unlinking any past session is "fix the link, replay" with no double-applied
    /// EWMA steps. Explanations of adjustments that recur unchanged are carried over.
    ///
    /// Returns the replayed plan and the adjustments produced by the most recently
    /// completed session (for propagation to future sessions).
    public func replayCompletedSessions(
        plan: ProgressionPlan,
        workoutsById: [UUID: Workout],
        bodyWeightKg: Double
    ) -> (plan: ProgressionPlan, lastSessionAdjustments: [PlanAdjustment]) {
        var replayed = plan
        for i in replayed.exercises.indices {
            replayed.exercises[i].current1RM = replayed.exercises[i].estimated1RM
        }
        let engineTriggers: Set<AdjustmentTrigger> = [.oneRMUpdate, .apre]
        let previousEngineAdjustments = replayed.adjustments.filter { engineTriggers.contains($0.trigger) }
        replayed.adjustments.removeAll { engineTriggers.contains($0.trigger) }

        // Completed sessions in completion order.
        var completed: [(bi: Int, wi: Int, si: Int, workout: Workout)] = []
        for bi in replayed.blocks.indices {
            for wi in replayed.blocks[bi].weeks.indices {
                for si in replayed.blocks[bi].weeks[wi].sessions.indices {
                    let session = replayed.blocks[bi].weeks[wi].sessions[si]
                    guard let workoutId = session.completedWorkoutId, let workout = workoutsById[workoutId] else { continue }
                    completed.append((bi, wi, si, workout))
                }
            }
        }
        completed.sort { ($0.workout.completedAt ?? $0.workout.startedAt) < ($1.workout.completedAt ?? $1.workout.startedAt) }

        var lastAdjustments: [PlanAdjustment] = []
        for entry in completed {
            let session = replayed.blocks[entry.bi].weeks[entry.wi].sessions[entry.si]
            let result = completeSession(session, workout: entry.workout, planExercises: replayed.exercises, bodyWeightKg: bodyWeightKg)
            replayed.blocks[entry.bi].weeks[entry.wi].sessions[entry.si] = result.updatedSession
            replayed.exercises = result.updatedExercises
            let stamped = result.adjustments.map { adjustment -> PlanAdjustment in
                var adjustment = adjustment
                adjustment.wasAccepted = true
                adjustment.appliedAt = entry.workout.completedAt ?? adjustment.appliedAt
                if let previous = previousEngineAdjustments.first(where: {
                    $0.trigger == adjustment.trigger
                        && $0.adjustmentType == adjustment.adjustmentType
                        && $0.description == adjustment.description
                }) {
                    adjustment.coachingExplanation = previous.coachingExplanation
                }
                return adjustment
            }
            replayed.adjustments.append(contentsOf: stamped)
            lastAdjustments = stamped
        }
        return (replayed, lastAdjustments)
    }

    // MARK: - Estimate 1RM

    /// Estimates the current 1RM from a set of completed exercise sets using the
    /// app-wide formula (`AnalyticsCalculations.bestE1RM`: hybrid Epley/Brzycki,
    /// warm-ups and incomplete sets ignored, every drop segment considered, reps
    /// clamped to 15). Returns the highest estimate rounded to nearest 2.5.
    public func estimateCurrent1RM(from sets: [ExerciseSet], baseLoadPerRep: Double? = nil) -> Double? {
        guard let best = AnalyticsCalculations.bestE1RM(in: sets, baseLoadPerRep: baseLoadPerRep), best > 0 else { return nil }
        return best.rounded(toNearest: 2.5)
    }
}
