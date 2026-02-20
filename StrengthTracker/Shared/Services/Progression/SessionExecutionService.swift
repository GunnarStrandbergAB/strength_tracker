import Foundation

/// Bridges planned sessions with actual workout execution.
/// Handles session preparation (PlannedSession -> WorkoutTemplate),
/// session completion with APRE adjustments, and 1RM estimation with EWMA smoothing.
public struct SessionExecutionService: Sendable {

    /// EWMA smoothing factor for 1RM updates
    private let alpha: Double = 0.3

    /// Outlier rejection threshold (15% deviation)
    private let outlierThreshold: Double = 0.15

    /// Regression guard threshold (5% drop required before applying downward adjustment)
    private let regressionThreshold: Double = 0.95

    public init() {}

    // MARK: - Prepare Session

    /// Converts a PlannedSession into a WorkoutTemplate ready for execution.
    /// Each PlannedExerciseSet becomes a TemplateExercise with per-set weight targets.
    public func prepareSession(
        _ session: PlannedSession,
        exercises: [Exercise] = []
    ) -> WorkoutTemplate {
        let exerciseLookup = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let templateExercises: [TemplateExercise] = session.plannedExercises.enumerated().map { index, planned in
            let exercise = exerciseLookup[planned.exerciseId] ?? makeMinimalExercise(
                id: planned.exerciseId,
                name: planned.exerciseName
            )

            let setTargets = (0..<planned.sets).map { setIndex in
                TemplateSetTarget(
                    order: setIndex,
                    targetReps: planned.targetReps,
                    targetWeight: planned.targetWeight,
                    setType: planned.isWarmup ? .warmup : .normal
                )
            }

            return TemplateExercise(
                id: planned.id,
                exercise: exercise,
                order: index,
                supersetGroup: nil,
                notes: planned.notes,
                restTimerSeconds: planned.restSeconds,
                targetSets: planned.sets,
                targetReps: planned.targetReps,
                targetWeight: planned.targetWeight,
                targetDurationSeconds: nil,
                targetDistanceMeters: nil,
                setTargets: setTargets,
                isWarmUp: planned.isWarmup
            )
        }

        return WorkoutTemplate(
            id: UUID(),
            name: session.sessionLabel,
            notes: session.notes,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: templateExercises
        )
    }

    // MARK: - Complete Session

    /// Links a completed workout back to the planned session, computes APRE adjustments
    /// and 1RM updates with EWMA smoothing.
    ///
    /// Returns an updated session, adjustment records, and updated plan exercises.
    public func completeSession(
        _ session: PlannedSession,
        workout: Workout,
        planExercises: [PlanExercise]
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

            // Estimate 1RM from completed sets
            if let estimated1RM = estimateCurrent1RM(from: workoutExercise.sets) {
                let current = planExercise.current1RM
                let deviation = abs(estimated1RM - current) / max(current, 1.0)

                // Outlier rejection: skip if deviation > 15%
                if deviation <= outlierThreshold {
                    // EWMA smoothing
                    let smoothed1RM = alpha * estimated1RM + (1.0 - alpha) * current
                    let rounded1RM = smoothed1RM.rounded(toNearest: 2.5)

                    // Regression guard: only apply downward if estimated < 95% of current
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
    public func estimateCurrent1RM(from sets: [ExerciseSet]) -> Double? {
        let validSets = sets.filter { set in
            set.isCompleted
            && set.setType != .warmup
            && set.reps != nil && set.reps! > 0
            && set.weight != nil && set.weight! > 0
            && set.reps! <= 15
        }

        guard !validSets.isEmpty else { return nil }

        var bestEstimate: Double = 0

        for set in validSets {
            let weight = set.weight!
            let reps = set.reps!
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

        return bestEstimate > 0 ? bestEstimate.rounded(toNearest: 2.5) : nil
    }

    // MARK: - Helpers

    private func makeMinimalExercise(id: UUID, name: String) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: .other,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }
}
