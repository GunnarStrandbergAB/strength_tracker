import Foundation
@testable import StrengthTrackerShared

/// Test data factory for Progression domain model tests.
/// Provides deterministic builders with sensible defaults.
enum ProgressionTestHelpers {

    // MARK: - Exercise Builder

    static func makeTestExercise(
        id: UUID = UUID(),
        name: String = "Bench Press"
    ) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    // MARK: - PlanExercise Builder

    static func makeTestPlanExercise(
        id: UUID = UUID(),
        exerciseId: UUID = UUID(),
        name: String = "Bench Press",
        current1RM: Double = 100.0,
        estimated1RM: Double? = nil,
        isCompound: Bool = true,
        primaryMuscleGroup: MuscleGroup = .chest,
        category: ExerciseCategory = .barbell,
        order: Int = 0
    ) -> PlanExercise {
        PlanExercise(
            id: id,
            exerciseId: exerciseId,
            exerciseName: name,
            primaryMuscleGroup: primaryMuscleGroup,
            category: category,
            estimated1RM: estimated1RM ?? current1RM,
            oneRMSource: .estimated,
            current1RM: current1RM,
            isCompound: isCompound,
            order: order
        )
    }

    // MARK: - PlannedExerciseSet Builder

    static func makeTestPlannedExerciseSet(
        id: UUID = UUID(),
        planExerciseId: UUID = UUID(),
        exerciseId: UUID = UUID(),
        exerciseName: String = "Bench Press",
        sets: Int = 3,
        targetReps: Int = 6,
        targetWeight: Double = 80.0,
        percentageOf1RM: Double = 0.80,
        restSeconds: Int = 120,
        isWarmup: Bool = false
    ) -> PlannedExerciseSet {
        PlannedExerciseSet(
            id: id,
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            sets: sets,
            targetReps: targetReps,
            targetWeight: targetWeight,
            percentageOf1RM: percentageOf1RM,
            restSeconds: restSeconds,
            isWarmup: isWarmup
        )
    }

    // MARK: - PlannedSession Builder

    static func makeTestPlannedSession(
        id: UUID = UUID(),
        label: String = "Session A",
        exercises: [PlannedExerciseSet] = [],
        completedWorkoutId: UUID? = nil,
        completedAt: Date? = nil,
        scheduledDate: Date? = nil
    ) -> PlannedSession {
        PlannedSession(
            id: id,
            scheduledDate: scheduledDate,
            sessionLabel: label,
            plannedExercises: exercises,
            completedWorkoutId: completedWorkoutId,
            completedAt: completedAt
        )
    }

    // MARK: - TrainingWeek Builder

    static func makeTestTrainingWeek(
        id: UUID = UUID(),
        weekNumber: Int = 1,
        absoluteWeekNumber: Int? = nil,
        sessions: [PlannedSession] = []
    ) -> TrainingWeek {
        TrainingWeek(
            id: id,
            weekNumber: weekNumber,
            absoluteWeekNumber: absoluteWeekNumber ?? weekNumber,
            sessions: sessions
        )
    }

    // MARK: - TrainingBlock Builder

    static func makeTestTrainingBlock(
        id: UUID = UUID(),
        name: String = "Block 1",
        order: Int = 0,
        durationWeeks: Int = 4,
        weeks: [TrainingWeek] = [],
        blockPhase: BlockPhase? = nil,
        isDeload: Bool = false
    ) -> TrainingBlock {
        TrainingBlock(
            id: id,
            name: name,
            blockPhase: blockPhase,
            order: order,
            durationWeeks: durationWeeks,
            weeks: weeks,
            isDeload: isDeload
        )
    }

    // MARK: - ProgressionPlan Builder

    static func makeTestPlan(
        id: UUID = UUID(),
        name: String = "Test Plan",
        blocks: [TrainingBlock] = [],
        exercises: [PlanExercise] = [],
        status: PlanStatus = .active,
        trainingStatus: TrainingStatus = .intermediate,
        programType: ProgramType = .linear,
        primaryGoal: TrainingGoal = .strength,
        weeklyFrequency: Int = 4,
        startDate: Date = Date(),
        adjustments: [PlanAdjustment] = []
    ) -> ProgressionPlan {
        ProgressionPlan(
            id: id,
            name: name,
            status: status,
            trainingStatus: trainingStatus,
            programType: programType,
            primaryGoal: primaryGoal,
            weeklyFrequency: weeklyFrequency,
            startDate: startDate,
            exercises: exercises,
            blocks: blocks,
            adjustments: adjustments
        )
    }

    // MARK: - Convenience: completed session

    static func makeCompletedSession(
        id: UUID = UUID(),
        label: String = "Session A",
        exercises: [PlannedExerciseSet] = [],
        completedAt: Date = Date()
    ) -> PlannedSession {
        makeTestPlannedSession(
            id: id,
            label: label,
            exercises: exercises,
            completedWorkoutId: UUID(),
            completedAt: completedAt
        )
    }

    // MARK: - Convenience: incomplete session

    static func makeIncompleteSession(
        id: UUID = UUID(),
        label: String = "Session B",
        exercises: [PlannedExerciseSet] = []
    ) -> PlannedSession {
        makeTestPlannedSession(
            id: id,
            label: label,
            exercises: exercises,
            completedWorkoutId: nil,
            completedAt: nil
        )
    }

    // MARK: - Standard Exercise Set (for ProgramDesignService tests)

    static func standardExercises() -> [PlanExercise] {
        [
            makeTestPlanExercise(name: "Barbell Squat", current1RM: 120.0, primaryMuscleGroup: .quadriceps, order: 0),
            makeTestPlanExercise(name: "Bench Press", current1RM: 100.0, primaryMuscleGroup: .chest, order: 1),
            makeTestPlanExercise(name: "Barbell Row", current1RM: 80.0, primaryMuscleGroup: .back, order: 2),
        ]
    }

    // MARK: - Convenience Plan Factories for Program Design

    static func beginnerLinearPlan() -> ProgressionPlan {
        makeTestPlan(
            name: "Beginner LP",
            exercises: standardExercises(),
            trainingStatus: .beginner,
            programType: .linear,
            primaryGoal: .hypertrophy,
            weeklyFrequency: 3
        )
    }

    static func intermediateDUPPlan() -> ProgressionPlan {
        makeTestPlan(
            name: "Intermediate DUP",
            exercises: standardExercises(),
            trainingStatus: .intermediate,
            programType: .dailyUndulating,
            primaryGoal: .strength,
            weeklyFrequency: 3
        )
    }

    static func intermediateWUPPlan() -> ProgressionPlan {
        makeTestPlan(
            name: "Intermediate WUP",
            exercises: standardExercises(),
            trainingStatus: .intermediate,
            programType: .weeklyUndulating,
            primaryGoal: .strength,
            weeklyFrequency: 3
        )
    }

    static func advancedBlockPlan() -> ProgressionPlan {
        makeTestPlan(
            name: "Advanced Block",
            exercises: standardExercises(),
            trainingStatus: .advanced,
            programType: .block,
            primaryGoal: .strength,
            weeklyFrequency: 4
        )
    }
}
