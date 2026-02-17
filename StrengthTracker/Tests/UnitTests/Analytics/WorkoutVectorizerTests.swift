import XCTest
import Foundation
@testable import StrengthTrackerShared

/// London School tests for WorkoutVectorizer.
/// Verifies the vectorizer's contract: it must produce L2-normalized 18-dimensional
/// vectors from workout data, and different workouts must produce different vectors.
/// The vectorizer is stateless -- historical context is passed as a parameter.
final class WorkoutVectorizerTests: XCTestCase {

    // MARK: - Dimension Contract

    @MainActor
    func test_vectorize_producesExactly18Dimensions() async {
        let vectorizer = WorkoutVectorizer()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        let vector = vectorizer.vectorize(workout)
        XCTAssertEqual(vector.dimensions.count, 18)
    }

    @MainActor
    func test_vectorize_outputIsL2Normalized() async {
        let vectorizer = WorkoutVectorizer()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        let vector = vectorizer.vectorize(workout)

        let magnitude = sqrt(vector.dimensions.reduce(0) { $0 + $1 * $1 })

        XCTAssertTrue(
            magnitude > 0.99 && magnitude < 1.01,
            "Expected magnitude ~1.0, got \(magnitude)"
        )
    }

    @MainActor
    func test_vectorize_emptyWorkoutProducesZeroVector() async {
        let vectorizer = WorkoutVectorizer()
        let workout = AnalyticsTestHelpers.makeWorkout(
            exercises: [],
            startedAt: Date(),
            completedAt: Date()
        )
        let vector = vectorizer.vectorize(workout)

        XCTAssertEqual(vector.dimensions.count, 18)
    }

    @MainActor
    func test_vectorize_isStateless_noSideEffects() async {
        let vectorizer = WorkoutVectorizer()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()

        let vector1 = vectorizer.vectorize(workout)
        let vector2 = vectorizer.vectorize(workout)

        for (a, b) in zip(vector1.dimensions, vector2.dimensions) {
            XCTAssertEqual(
                a, b, accuracy: 1e-10,
                "Stateless vectorizer should produce identical outputs for identical inputs"
            )
        }
    }

    @MainActor
    func test_vectorize_withHistoricalContext_affectsScaling() async {
        let vectorizer = WorkoutVectorizer()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()

        let vectorNoHistory = vectorizer.vectorize(workout, historicalWorkouts: [])

        let lowerVolumeWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest,
            sets: 2,
            reps: 5,
            weight: 40.0,
            startedAt: Date().addingTimeInterval(-86400),
            completedAt: Date().addingTimeInterval(-82800)
        )
        let vectorWithHistory = vectorizer.vectorize(
            workout,
            historicalWorkouts: [lowerVolumeWorkout]
        )

        let allSame = zip(vectorNoHistory.dimensions, vectorWithHistory.dimensions)
            .allSatisfy { abs($0 - $1) < 1e-10 }
        XCTAssertFalse(
            allSame,
            "Historical context should affect at least the relative volume features"
        )
    }

    @MainActor
    func test_vectorize_differentWorkouts_produceDifferentVectors() async {
        let vectorizer = WorkoutVectorizer()
        let pushDay = AnalyticsTestHelpers.makePushDayWorkout()
        let pullDay = AnalyticsTestHelpers.makePullDayWorkout()

        let pushVector = vectorizer.vectorize(pushDay)
        let pullVector = vectorizer.vectorize(pullDay)

        let allSame = zip(pushVector.dimensions, pullVector.dimensions)
            .allSatisfy { abs($0 - $1) < 1e-10 }
        XCTAssertFalse(
            allSame,
            "Push day and pull day should produce different vectors"
        )
    }

    @MainActor
    func test_vectorize_assignsCorrectWorkoutId() async {
        let vectorizer = WorkoutVectorizer()
        let workoutId = UUID()
        let workout = AnalyticsTestHelpers.makeWorkout(
            id: workoutId,
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
            completedAt: Date()
        )

        let vector = vectorizer.vectorize(workout)

        XCTAssertEqual(vector.workoutId, workoutId)
    }

    @MainActor
    func test_vectorize_workoutWithPRs_producesNonZeroPRFeature() async {
        let vectorizer = WorkoutVectorizer()
        let exercise = AnalyticsTestHelpers.makeExercise()
        let prSet = AnalyticsTestHelpers.makeCompletedSet(
            order: 1,
            weight: 100,
            reps: 10,
            isPersonalRecord: true
        )
        let workoutExercise = AnalyticsTestHelpers.makeWorkoutExercise(
            exercise: exercise,
            sets: [prSet]
        )
        let workout = AnalyticsTestHelpers.makeWorkout(
            exercises: [workoutExercise],
            completedAt: Date()
        )

        let vector = vectorizer.vectorize(workout)

        XCTAssertEqual(vector.dimensions.count, 18)
        let magnitude = sqrt(vector.dimensions.reduce(0) { $0 + $1 * $1 })
        XCTAssertTrue(magnitude > 0.99 && magnitude < 1.01)
    }

    @MainActor
    func test_vectorize_warmupOnlySets_zeroVolume() async {
        let vectorizer = WorkoutVectorizer()
        let exercise = AnalyticsTestHelpers.makeExercise()
        let warmupSet = ExerciseSet(
            id: UUID(),
            order: 1,
            setType: .warmup,
            weight: 40.0,
            reps: 10,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )
        let workoutExercise = AnalyticsTestHelpers.makeWorkoutExercise(
            exercise: exercise,
            sets: [warmupSet]
        )
        let workout = AnalyticsTestHelpers.makeWorkout(
            exercises: [workoutExercise],
            completedAt: Date()
        )

        let vector = vectorizer.vectorize(workout)

        XCTAssertEqual(vector.dimensions.count, 18)
    }

    @MainActor
    func test_vectorize_multipleExerciseTypes() async {
        let vectorizer = WorkoutVectorizer()
        let chestExercise = AnalyticsTestHelpers.makeWorkoutExercise(
            exercise: AnalyticsTestHelpers.makeExercise(
                name: "Bench", primaryMuscleGroup: .chest, category: .barbell
            ),
            order: 1,
            sets: [AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 100, reps: 8)]
        )
        let legExercise = AnalyticsTestHelpers.makeWorkoutExercise(
            exercise: AnalyticsTestHelpers.makeExercise(
                name: "Squat", primaryMuscleGroup: .quadriceps, secondaryMuscleGroups: [.glutes, .hamstrings], category: .barbell
            ),
            order: 2,
            sets: [AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 120, reps: 5)]
        )
        let coreExercise = AnalyticsTestHelpers.makeWorkoutExercise(
            exercise: AnalyticsTestHelpers.makeExercise(
                name: "Plank", primaryMuscleGroup: .core, secondaryMuscleGroups: [], category: .bodyweight
            ),
            order: 3,
            sets: [AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 0, reps: 1)]
        )
        let workout = AnalyticsTestHelpers.makeWorkout(
            exercises: [chestExercise, legExercise, coreExercise],
            completedAt: Date()
        )

        let vector = vectorizer.vectorize(workout)

        XCTAssertEqual(vector.dimensions.count, 18)
        let magnitude = sqrt(vector.dimensions.reduce(0) { $0 + $1 * $1 })
        XCTAssertTrue(magnitude > 0.99 && magnitude < 1.01)
    }
}
