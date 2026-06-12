import XCTest
import Foundation
@testable import StrengthTrackerShared

/// Tests for MuscleBalanceService.
/// Verifies muscle group volume analysis, imbalance detection across
/// antagonist pairs, and overall balance scoring.
final class MuscleBalanceServiceTests: XCTestCase {

    // MARK: - Empty / No Data

    @MainActor
    func test_analyzeBalance_emptyWorkouts_returnsZeroScore() async {
        // With zero training volume the service deliberately returns a 0.0 score
        // rather than a misleading "perfect balance" 1.0 (see analyzeBalance guard).
        let service = MuscleBalanceService()
        let result = service.analyzeBalance(workouts: [])
        XCTAssertEqual(result.overallBalanceScore, 0.0, accuracy: 1e-10)
        XCTAssertTrue(result.imbalances.isEmpty)
        XCTAssertTrue(result.muscleGroupVolumes.isEmpty)
    }

    @MainActor
    func test_analyzeBalance_noCompletedWorkouts_returnsZeroScore() async {
        // No completed workouts means zero volume -> deliberate 0.0 score
        // rather than a misleading "perfect balance" 1.0.
        let service = MuscleBalanceService()
        let workout = AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
            startedAt: Date(),
            completedAt: nil
        )
        let result = service.analyzeBalance(workouts: [workout])
        XCTAssertEqual(result.overallBalanceScore, 0.0, accuracy: 1e-10)
        XCTAssertTrue(result.imbalances.isEmpty)
    }

    // MARK: - Balanced Workouts

    @MainActor
    func test_analyzeBalance_balancedWorkouts_noChestBackImbalance() async {
        let service = MuscleBalanceService()
        let chestWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest, sets: 4, reps: 10, weight: 80.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let backWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .back, sets: 4, reps: 10, weight: 80.0,
            startedAt: Date().addingTimeInterval(-1800)
        )
        let result = service.analyzeBalance(workouts: [chestWorkout, backWorkout])

        let chestBackImbalances = result.imbalances.filter {
            ($0.primaryGroup == MuscleGroup.chest.rawValue && $0.comparisonGroup == MuscleGroup.back.rawValue) ||
            ($0.primaryGroup == MuscleGroup.back.rawValue && $0.comparisonGroup == MuscleGroup.chest.rawValue)
        }
        XCTAssertTrue(chestBackImbalances.isEmpty,
                       "Equal chest and back volume should not produce an imbalance")
    }

    // MARK: - Imbalance Detection

    @MainActor
    func test_analyzeBalance_pushDominant_detectsImbalance() async {
        let service = MuscleBalanceService()
        let chestWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest, sets: 6, reps: 10, weight: 100.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let backWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .back, sets: 2, reps: 10, weight: 30.0,
            startedAt: Date().addingTimeInterval(-1800)
        )
        let result = service.analyzeBalance(workouts: [chestWorkout, backWorkout])

        let chestDominant = result.imbalances.filter {
            $0.primaryGroup == MuscleGroup.chest.rawValue &&
            $0.comparisonGroup == MuscleGroup.back.rawValue
        }
        XCTAssertFalse(chestDominant.isEmpty,
                        "Chest volume much higher than back should produce a chest/back imbalance")
    }

    @MainActor
    func test_analyzeBalance_quadDominant_detectsImbalance() async {
        let service = MuscleBalanceService()
        let quadWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .quadriceps, sets: 6, reps: 10, weight: 120.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let hamWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .hamstrings, sets: 2, reps: 10, weight: 30.0,
            startedAt: Date().addingTimeInterval(-1800)
        )
        let result = service.analyzeBalance(workouts: [quadWorkout, hamWorkout])

        let quadDominant = result.imbalances.filter {
            $0.primaryGroup == MuscleGroup.quadriceps.rawValue &&
            $0.comparisonGroup == MuscleGroup.hamstrings.rawValue
        }
        XCTAssertFalse(quadDominant.isEmpty,
                        "Quad-dominant training should produce a quads/hamstrings imbalance")
    }

    // MARK: - Severity Detection

    @MainActor
    func test_analyzeBalance_severeImbalance_hasSevereSeverity() async {
        let service = MuscleBalanceService()
        let dominant = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest, sets: 8, reps: 10, weight: 100.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let weak = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .back, sets: 1, reps: 5, weight: 20.0,
            startedAt: Date().addingTimeInterval(-1800)
        )
        let result = service.analyzeBalance(workouts: [dominant, weak])

        let severe = result.imbalances.filter { $0.severity == .severe }
        XCTAssertFalse(severe.isEmpty,
                        "A very large volume disparity should produce a severe imbalance")
    }

    // MARK: - Overall Score

    @MainActor
    func test_analyzeBalance_overallScoreDecreases_withMoreImbalances() async {
        let service = MuscleBalanceService()

        let balanced1 = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest, sets: 4, reps: 10, weight: 80.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let balanced2 = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .back, sets: 4, reps: 10, weight: 80.0,
            startedAt: Date().addingTimeInterval(-1800)
        )
        let balancedResult = service.analyzeBalance(workouts: [balanced1, balanced2])

        let heavy = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest, sets: 8, reps: 10, weight: 100.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let light = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .back, sets: 1, reps: 5, weight: 20.0,
            startedAt: Date().addingTimeInterval(-1800)
        )
        let imbalancedResult = service.analyzeBalance(workouts: [heavy, light])

        XCTAssertGreaterThanOrEqual(balancedResult.overallBalanceScore,
                                     imbalancedResult.overallBalanceScore,
                                     "More imbalances should lower the overall balance score")
    }

    @MainActor
    func test_analyzeBalance_perfectBalance_returnsScoreOne() async {
        // Perfect balance requires actual training volume: empty workouts now
        // deliberately score 0.0, so use equal antagonist volume to get 1.0.
        let service = MuscleBalanceService()
        let chestWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest, sets: 4, reps: 10, weight: 80.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let backWorkout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .back, sets: 4, reps: 10, weight: 80.0,
            startedAt: Date().addingTimeInterval(-1800)
        )
        let result = service.analyzeBalance(workouts: [chestWorkout, backWorkout])
        XCTAssertEqual(result.overallBalanceScore, 1.0, accuracy: 1e-10)
    }

    // MARK: - Volume Distribution

    @MainActor
    func test_analyzeBalance_primaryMuscleGets70PercentVolume() async {
        let service = MuscleBalanceService()
        let exercise = AnalyticsTestHelpers.makeExercise(
            name: "Bench Press", primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders]
        )
        let sets = [AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 100.0, reps: 10)]
        let we = AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: sets)
        let workout = AnalyticsTestHelpers.makeWorkout(
            exercises: [we], startedAt: Date(), completedAt: Date()
        )
        let result = service.analyzeBalance(workouts: [workout])

        let chestVolume = result.muscleGroupVolumes.first {
            $0.muscleGroup == MuscleGroup.chest.rawValue
        }
        XCTAssertNotNil(chestVolume, "Should have a chest volume entry")
        if let cv = chestVolume {
            XCTAssertEqual(cv.weeklyVolume, 700.0, accuracy: 1e-10,
                           "Primary muscle should receive 70% of exercise volume")
        }
    }

    // MARK: - analyze(workouts:timeWindow:) Overload

    @MainActor
    func test_analyze_timeWindowOverload_convertsToWeeks() async {
        let service = MuscleBalanceService()
        let workout = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest, sets: 4, reps: 10, weight: 80.0,
            startedAt: Date().addingTimeInterval(-3600)
        )
        let result = service.analyze(workouts: [workout], timeWindow: 2_419_200)
        XCTAssertNotNil(result.analyzedAt)
    }
}
