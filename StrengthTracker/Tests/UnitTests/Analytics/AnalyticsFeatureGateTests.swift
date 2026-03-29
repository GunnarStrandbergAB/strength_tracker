import XCTest
import Foundation
@testable import StrengthTrackerShared

/// Tests for AnalyticsFeatureGate.
/// Verifies progressive feature unlocking based on completed workout count,
/// matching the UX phased disclosure model.
final class AnalyticsFeatureGateTests: XCTestCase {

    // MARK: - unlockedFeatures

    @MainActor
    func test_unlockedFeatures_zeroWorkouts_returnsEmpty() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(0))
        let features = try await gate.unlockedFeatures()
        XCTAssertTrue(features.isEmpty, "No features should be unlocked with zero workouts")
    }

    @MainActor
    func test_unlockedFeatures_threeWorkouts_onlyDebriefUnlocked() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(3))
        let features = try await gate.unlockedFeatures()
        XCTAssertTrue(features.contains(.postWorkoutDebrief),
                       "Post-workout debrief should be unlocked at 1+ workouts")
        XCTAssertFalse(features.contains(.similarWorkouts),
                        "Similar workouts requires 5 workouts")
    }

    @MainActor
    func test_unlockedFeatures_fiveWorkouts_unlocksPhase2() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(5))
        let features = try await gate.unlockedFeatures()

        XCTAssertTrue(features.contains(.similarWorkouts))
        XCTAssertTrue(features.contains(.qualityScore))
        XCTAssertTrue(features.contains(.strengthTrends))
        XCTAssertTrue(features.contains(.exerciseRecommendations))
        XCTAssertFalse(features.contains(.plateauDetection))
        XCTAssertFalse(features.contains(.muscleBalance))
    }

    @MainActor
    func test_unlockedFeatures_tenWorkouts_unlocksPlateauDetection() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(10))
        let features = try await gate.unlockedFeatures()

        XCTAssertTrue(features.contains(.plateauDetection),
                       "Plateau detection should unlock at 10 workouts")
        XCTAssertTrue(features.contains(.similarWorkouts))
        XCTAssertFalse(features.contains(.muscleBalance))
        XCTAssertFalse(features.contains(.recoveryTimeline))
    }

    @MainActor
    func test_unlockedFeatures_twentyWorkouts_unlocksMuscleBalance() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(20))
        let features = try await gate.unlockedFeatures()

        XCTAssertTrue(features.contains(.muscleBalance),
                       "Muscle balance should unlock at 19 workouts")
        XCTAssertTrue(features.contains(.recoveryTimeline),
                       "Recovery timeline should unlock at 20 workouts")
        XCTAssertTrue(features.contains(.advancedInsights),
                       "Advanced insights should unlock at 19 workouts")
    }

    @MainActor
    func test_unlockedFeatures_fiftyWorkouts_unlocksAll() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(50))
        let features = try await gate.unlockedFeatures()

        for feature in AnalyticsFeatureGate.Feature.allCases {
            XCTAssertTrue(features.contains(feature),
                           "\(feature.rawValue) should be unlocked at 50 workouts")
        }
    }

    // MARK: - nextUnlock

    @MainActor
    func test_nextUnlock_returnsClosestThreshold() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(3))
        let next = try await gate.nextUnlock()

        XCTAssertNotNil(next, "Should have a next unlock with 3 workouts")
        if let next = next {
            XCTAssertEqual(next.workoutsNeeded, 2,
                           "Need 2 more workouts to unlock next feature (threshold 5)")
        }
    }

    @MainActor
    func test_nextUnlock_atThreshold_returnsNextPhase() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(5))
        let next = try await gate.nextUnlock()

        XCTAssertNotNil(next, "Should have a next unlock at 5 workouts")
        if let next = next {
            XCTAssertEqual(next.feature, .effortCreepWarning)
            XCTAssertEqual(next.workoutsNeeded, 5)
        }
    }

    @MainActor
    func test_nextUnlock_allUnlocked_returnsNil() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(50))
        let next = try await gate.nextUnlock()
        XCTAssertNil(next, "Should return nil when all features are unlocked")
    }

    @MainActor
    func test_nextUnlock_zeroWorkouts_returnsPostWorkoutDebrief() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(0))
        let next = try await gate.nextUnlock()

        XCTAssertNotNil(next)
        if let next = next {
            XCTAssertEqual(next.feature, .postWorkoutDebrief)
            XCTAssertEqual(next.workoutsNeeded, 1,
                           "With 0 workouts, need 1 to unlock post-workout debrief")
        }
    }

    // MARK: - isUnlocked

    @MainActor
    func test_isUnlocked_specificFeature_true() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(10))
        let unlocked = try await gate.isUnlocked(.plateauDetection)
        XCTAssertTrue(unlocked, "Plateau detection should be unlocked at 10 workouts")
    }

    @MainActor
    func test_isUnlocked_specificFeature_false() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(3))
        let unlocked = try await gate.isUnlocked(.similarWorkouts)
        XCTAssertFalse(unlocked, "Similar workouts requires 5 workouts, but only 3 are completed")
    }

    @MainActor
    func test_isUnlocked_advancedInsights_requiresNineteen() async throws {
        let gate = AnalyticsFeatureGate(workoutRepository: makeSeededRepo(18))
        let unlocked = try await gate.isUnlocked(.advancedInsights)
        XCTAssertFalse(unlocked, "Advanced insights requires 19 workouts, but only 18 are completed")
    }

    // MARK: - Incomplete Workouts Excluded

    @MainActor
    func test_unlockedFeatures_incompleteWorkoutsNotCounted() async throws {
        let repo = MockWorkoutRepository()
        let completed = (0..<5).map { i in
            AnalyticsTestHelpers.makeWorkout(
                name: "Completed \(i)",
                exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
                startedAt: Date().addingTimeInterval(Double(-i) * 86400),
                completedAt: Date().addingTimeInterval(Double(-i) * 86400 + 3600)
            )
        }
        let incomplete = (0..<10).map { i in
            AnalyticsTestHelpers.makeWorkout(
                name: "Incomplete \(i)",
                exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
                startedAt: Date().addingTimeInterval(Double(-(i + 5)) * 86400),
                completedAt: nil
            )
        }
        repo.seed(completed + incomplete)

        let gate = AnalyticsFeatureGate(workoutRepository: repo)
        let features = try await gate.unlockedFeatures()

        XCTAssertTrue(features.contains(.similarWorkouts))
        XCTAssertFalse(features.contains(.plateauDetection))
    }

    // MARK: - Helpers

    @MainActor
    private func makeSeededRepo(_ count: Int) -> MockWorkoutRepository {
        let repo = MockWorkoutRepository()
        let workouts = (0..<count).map { i in
            AnalyticsTestHelpers.makeWorkout(
                name: "Workout \(i + 1)",
                exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
                startedAt: Date().addingTimeInterval(Double(-i) * 86400),
                completedAt: Date().addingTimeInterval(Double(-i) * 86400 + 3600)
            )
        }
        repo.seed(workouts)
        return repo
    }
}
