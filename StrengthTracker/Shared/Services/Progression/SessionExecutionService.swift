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

    // MARK: - Estimate 1RM

    /// Estimates the current 1RM from a set of completed exercise sets.
    ///
    /// Uses Epley formula for low reps (2-5), Brzycki for moderate reps (6-15),
    /// and direct weight for singles. Ignores sets with reps > 15, warmups,
    /// and incomplete sets. Returns the highest estimate rounded to nearest 2.5.
    public func estimateCurrent1RM(from sets: [ExerciseSet], baseLoadPerRep: Double? = nil) -> Double? {
        var bestEstimate: Double = 0

        for set in sets where set.isCompleted && set.setType != .warmup {
            for part in set.effectiveLoadParts(baseLoadPerRep: baseLoadPerRep) where part.reps <= 15 {
                let weight = part.load
                let reps = part.reps
                let estimate: Double

                if reps == 1 {
                    estimate = weight
                } else if reps <= 5 {
                    // Epley formula
                    estimate = weight * (1.0 + Double(reps) / 30.0)
                } else {
                    // Brzycki formula (6-15 reps)
                    estimate = weight * 36.0 / (37.0 - Double(reps))
                }

                bestEstimate = max(bestEstimate, estimate)
            }
        }

        return bestEstimate > 0 ? bestEstimate.rounded(toNearest: 2.5) : nil
    }
}
