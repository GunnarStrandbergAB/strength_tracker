import Foundation
@testable import StrengthTrackerShared

/// Test data factory for analytics tests.
/// Provides deterministic builders for Workout, WorkoutExercise, ExerciseSet,
/// Exercise, and WorkoutVector to keep test code concise and consistent.
enum AnalyticsTestHelpers {

    // MARK: - Exercise Builders

    static func makeExercise(
        id: UUID = UUID(),
        name: String = "Bench Press",
        primaryMuscleGroup: MuscleGroup = .chest,
        secondaryMuscleGroups: [MuscleGroup] = [.triceps, .shoulders],
        category: ExerciseCategory = .barbell,
        exerciseType: ExerciseType = .weightedReps,
        bodyweightFactor: Double? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: secondaryMuscleGroups,
            category: category,
            exerciseType: exerciseType,
            instructions: nil,
            isCustom: false,
            isArchived: false,
            bodyweightFactor: bodyweightFactor
        )
    }

    // MARK: - Set Builders

    static func makeCompletedSet(
        id: UUID = UUID(),
        order: Int = 1,
        weight: Double = 80.0,
        reps: Int = 10,
        rpe: Double? = nil,
        rir: Double? = nil,
        isPersonalRecord: Bool = false,
        setType: SetType = .normal,
        isFailure: Bool = false,
        dropSets: [DropSetEntry] = [],
        completedAt: Date = Date()
    ) -> ExerciseSet {
        ExerciseSet(
            id: id,
            order: order,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: rpe,
            rir: rir,
            isCompleted: true,
            isPersonalRecord: isPersonalRecord,
            isFailure: isFailure,
            completedAt: completedAt,
            dropSets: dropSets
        )
    }

    /// A completed grouped drop set built from (weight, reps) parts. Goes through
    /// `applyDropSets` so the parent mirrors the first part per the model invariant.
    static func makeDropSet(
        id: UUID = UUID(),
        order: Int = 1,
        parts: [(weight: Double?, reps: Int?)],
        rpes: [Double?]? = nil
    ) -> ExerciseSet {
        var set = makeCompletedSet(id: id, order: order, weight: 0, reps: 0)
        let entries = parts.enumerated().map { index, part in
            DropSetEntry(weight: part.weight, reps: part.reps, rpe: rpes?[index] ?? nil)
        }
        set.applyDropSets(entries)
        return set
    }

    static func makeIncompleteSet(
        id: UUID = UUID(),
        order: Int = 1
    ) -> ExerciseSet {
        ExerciseSet(
            id: id,
            order: order,
            setType: .normal,
            weight: nil,
            reps: nil,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: false,
            isPersonalRecord: false,
            completedAt: nil
        )
    }

    // MARK: - WorkoutExercise Builders

    static func makeWorkoutExercise(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        order: Int = 1,
        sets: [ExerciseSet]? = nil
    ) -> WorkoutExercise {
        let ex = exercise ?? makeExercise()
        let s = sets ?? [
            makeCompletedSet(order: 1, weight: 80.0, reps: 10),
            makeCompletedSet(order: 2, weight: 80.0, reps: 10),
            makeCompletedSet(order: 3, weight: 80.0, reps: 8),
        ]
        return WorkoutExercise(
            id: id,
            exercise: ex,
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            sets: s
        )
    }

    // MARK: - Workout Builders

    static func makeWorkout(
        id: UUID = UUID(),
        name: String = "Test Workout",
        exercises: [WorkoutExercise] = [],
        startedAt: Date = Date(),
        completedAt: Date? = Date()
    ) -> Workout {
        Workout(
            id: id,
            name: name,
            startedAt: startedAt,
            completedAt: completedAt,
            notes: nil,
            templateId: nil,
            exercises: exercises
        )
    }

    /// Creates a workout with volume distributed to a specific muscle group.
    static func makeWorkoutWithVolume(
        id: UUID = UUID(),
        name: String = "Volume Workout",
        primaryMuscleGroup: MuscleGroup,
        category: ExerciseCategory = .barbell,
        sets: Int = 4,
        reps: Int = 10,
        weight: Double = 80.0,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) -> Workout {
        let exercise = makeExercise(
            name: "\(primaryMuscleGroup.rawValue) exercise",
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: [],
            category: category
        )
        let exerciseSets = (1...sets).map { order in
            makeCompletedSet(order: order, weight: weight, reps: reps)
        }
        let workoutExercise = makeWorkoutExercise(
            exercise: exercise,
            order: 1,
            sets: exerciseSets
        )
        return makeWorkout(
            id: id,
            name: name,
            exercises: [workoutExercise],
            startedAt: startedAt,
            completedAt: completedAt ?? startedAt.addingTimeInterval(3600)
        )
    }

    /// Creates a push-day style workout with chest, shoulders, triceps exercises.
    static func makePushDayWorkout(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) -> Workout {
        let benchPress = makeWorkoutExercise(
            exercise: makeExercise(name: "Bench Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps, .shoulders]),
            order: 1,
            sets: [
                makeCompletedSet(order: 1, weight: 100, reps: 8),
                makeCompletedSet(order: 2, weight: 100, reps: 8),
                makeCompletedSet(order: 3, weight: 100, reps: 6),
            ]
        )
        let ohp = makeWorkoutExercise(
            exercise: makeExercise(name: "Overhead Press", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [.triceps]),
            order: 2,
            sets: [
                makeCompletedSet(order: 1, weight: 60, reps: 10),
                makeCompletedSet(order: 2, weight: 60, reps: 8),
            ]
        )
        let tricepsPushdown = makeWorkoutExercise(
            exercise: makeExercise(name: "Triceps Pushdown", primaryMuscleGroup: .triceps, secondaryMuscleGroups: [], category: .cable),
            order: 3,
            sets: [
                makeCompletedSet(order: 1, weight: 30, reps: 12),
                makeCompletedSet(order: 2, weight: 30, reps: 12),
            ]
        )
        return makeWorkout(
            id: id,
            name: "Push Day",
            exercises: [benchPress, ohp, tricepsPushdown],
            startedAt: startedAt,
            completedAt: completedAt ?? startedAt.addingTimeInterval(3600)
        )
    }

    /// Creates a pull-day style workout with back and biceps exercises.
    static func makePullDayWorkout(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) -> Workout {
        let deadlift = makeWorkoutExercise(
            exercise: makeExercise(name: "Deadlift", primaryMuscleGroup: .back, secondaryMuscleGroups: [.hamstrings, .glutes]),
            order: 1,
            sets: [
                makeCompletedSet(order: 1, weight: 140, reps: 5),
                makeCompletedSet(order: 2, weight: 140, reps: 5),
                makeCompletedSet(order: 3, weight: 140, reps: 5),
            ]
        )
        let curls = makeWorkoutExercise(
            exercise: makeExercise(name: "Barbell Curls", primaryMuscleGroup: .biceps, secondaryMuscleGroups: [.forearms], category: .barbell),
            order: 2,
            sets: [
                makeCompletedSet(order: 1, weight: 30, reps: 12),
                makeCompletedSet(order: 2, weight: 30, reps: 10),
            ]
        )
        return makeWorkout(
            id: id,
            name: "Pull Day",
            exercises: [deadlift, curls],
            startedAt: startedAt,
            completedAt: completedAt ?? startedAt.addingTimeInterval(3600)
        )
    }

    // MARK: - WorkoutVector Builders

    /// Creates a WorkoutVector with deterministic or custom dimensions.
    static func makeVector(
        id: UUID = UUID(),
        workoutId: UUID = UUID(),
        createdAt: Date = Date(),
        dimensions: [Double]? = nil
    ) -> WorkoutVector {
        let dims = dimensions ?? makeNormalizedDimensions()
        return WorkoutVector(
            id: id,
            workoutId: workoutId,
            dimensions: dims,
            createdAt: createdAt
        )
    }

    /// Creates a normalized 18-dimensional vector with default values.
    static func makeNormalizedDimensions() -> [Double] {
        let raw: [Double] = [
            0.65, 0.45, 0.33, 0.20, 0.40, 0.50,
            0.30, 0.25, 0.15, 0.10, 0.12, 0.08,
            0.60, 0.70, 0.05, 0.10, 0.20, 0.75,
        ]
        return l2Normalize(raw)
    }

    /// L2 normalizes a vector so its magnitude equals 1.0.
    static func l2Normalize(_ vector: [Double]) -> [Double] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    /// Creates an 18-dimension zero vector.
    static func makeZeroVector(workoutId: UUID = UUID()) -> WorkoutVector {
        WorkoutVector(
            id: UUID(),
            workoutId: workoutId,
            dimensions: [Double](repeating: 0.0, count: 18),
            createdAt: Date()
        )
    }

    // MARK: - Batch Builders

    /// Creates N workouts spread across weeks for plateau detection testing.
    static func makeWeeklyWorkouts(
        exerciseId: UUID,
        exerciseName: String = "Bench Press",
        primaryMuscle: MuscleGroup = .chest,
        weekCount: Int,
        volumePerWeek: [Double]
    ) -> [Workout] {
        let calendar = Calendar.current
        let now = Date()

        return (0..<weekCount).map { weekIndex in
            let startDate = calendar.date(byAdding: .weekOfYear, value: -weekIndex, to: now)!
            let volume = weekIndex < volumePerWeek.count ? volumePerWeek[weekIndex] : 1000.0

            let weight = volume / 30.0 // 3 sets * 10 reps = 30 total reps
            let exercise = makeExercise(
                id: exerciseId,
                name: exerciseName,
                primaryMuscleGroup: primaryMuscle,
                secondaryMuscleGroups: []
            )
            let sets = (1...3).map { order in
                makeCompletedSet(order: order, weight: weight, reps: 10)
            }
            let workoutExercise = makeWorkoutExercise(
                exercise: exercise,
                order: 1,
                sets: sets
            )
            return makeWorkout(
                name: "\(exerciseName) Week \(weekIndex + 1)",
                exercises: [workoutExercise],
                startedAt: startDate,
                completedAt: startDate.addingTimeInterval(3600)
            )
        }
    }
}
