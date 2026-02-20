import XCTest
@testable import StrengthTrackerShared

@MainActor
final class PlanAnalyticsServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        workouts: [Workout] = []
    ) -> PlanAnalyticsService {
        let repo = MockWorkoutRepositoryProgression()
        repo.workouts = workouts
        return PlanAnalyticsService(workoutRepository: repo)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        templateId: UUID? = nil,
        exercises: [WorkoutExercise] = []
    ) -> Workout {
        Workout(
            id: id,
            name: "Workout",
            startedAt: completedAt.addingTimeInterval(-3600),
            completedAt: completedAt,
            notes: nil,
            templateId: templateId,
            exercises: exercises
        )
    }

    private func makeWorkoutExercise(
        exerciseId: UUID,
        name: String = "Bench Press",
        sets: [ExerciseSet]
    ) -> WorkoutExercise {
        let exercise = Exercise(
            id: exerciseId,
            name: name,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
        return WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: sets
        )
    }

    private func makeSet(
        weight: Double = 80,
        reps: Int = 5,
        isCompleted: Bool = true,
        setType: SetType = .normal
    ) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: 1,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: isCompleted,
            isPersonalRecord: false,
            completedAt: nil
        )
    }

    // MARK: - Adherence Tests

    func testGenerateProgress_calculatesAdherence() async throws {
        // 3 out of 6 sessions completed -> 0.5 adherence
        let workoutId1 = UUID()
        let workoutId2 = UUID()
        let workoutId3 = UUID()

        let sessions: [PlannedSession] = [
            ProgressionTestHelpers.makeCompletedSession(label: "S1"),
            ProgressionTestHelpers.makeCompletedSession(label: "S2"),
            ProgressionTestHelpers.makeCompletedSession(label: "S3"),
            ProgressionTestHelpers.makeIncompleteSession(label: "S4"),
            ProgressionTestHelpers.makeIncompleteSession(label: "S5"),
            ProgressionTestHelpers.makeIncompleteSession(label: "S6"),
        ]

        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 1,
            sessions: Array(sessions[0..<3])
        )
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 2,
            sessions: Array(sessions[3..<6])
        )

        let block = ProgressionTestHelpers.makeTestTrainingBlock(
            name: "Block 1",
            weeks: [week1, week2]
        )

        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        XCTAssertEqual(progress.overallAdherence, 0.5, accuracy: 0.001)
    }

    // MARK: - Exercise Progress Tests

    func testGenerateProgress_exerciseProgress1RM() async throws {
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Squat",
            current1RM: 120.0,
            estimated1RM: 100.0
        )

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        XCTAssertEqual(progress.exerciseProgress.count, 1)
        let ep = progress.exerciseProgress[0]
        XCTAssertEqual(ep.starting1RM, 100.0, accuracy: 0.01)
        XCTAssertEqual(ep.current1RM, 120.0, accuracy: 0.01)
        // progressPercentage = (120 - 100) / 100 * 100 = 20%
        XCTAssertEqual(ep.progressPercentage, 20.0, accuracy: 0.01)
    }

    // MARK: - On Track Tests

    func testGenerateProgress_isOnTrack_aboveThreshold() async throws {
        // 4 out of 5 sessions completed -> 0.80 adherence >= 0.75 -> on track
        let sessions: [PlannedSession] = [
            ProgressionTestHelpers.makeCompletedSession(label: "S1"),
            ProgressionTestHelpers.makeCompletedSession(label: "S2"),
            ProgressionTestHelpers.makeCompletedSession(label: "S3"),
            ProgressionTestHelpers.makeCompletedSession(label: "S4"),
            ProgressionTestHelpers.makeIncompleteSession(label: "S5"),
        ]

        let week = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 1,
            sessions: sessions
        )

        let block = ProgressionTestHelpers.makeTestTrainingBlock(
            name: "Block 1",
            weeks: [week]
        )

        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        XCTAssertTrue(progress.isOnTrack)
        XCTAssertEqual(progress.overallAdherence, 0.8, accuracy: 0.001)
    }

    func testGenerateProgress_isOnTrack_belowThreshold() async throws {
        // 2 out of 4 sessions completed -> 0.50 adherence < 0.75 -> not on track
        let sessions: [PlannedSession] = [
            ProgressionTestHelpers.makeCompletedSession(label: "S1"),
            ProgressionTestHelpers.makeCompletedSession(label: "S2"),
            ProgressionTestHelpers.makeIncompleteSession(label: "S3"),
            ProgressionTestHelpers.makeIncompleteSession(label: "S4"),
        ]

        let week = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 1,
            sessions: sessions
        )

        let block = ProgressionTestHelpers.makeTestTrainingBlock(
            name: "Block 1",
            weeks: [week]
        )

        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        XCTAssertFalse(progress.isOnTrack)
        XCTAssertEqual(progress.overallAdherence, 0.5, accuracy: 0.001)
    }

    // MARK: - Deload and Adjustment Count Tests

    func testGenerateProgress_countsDeloadsAndAdjustments() async throws {
        let adjustments: [PlanAdjustment] = [
            PlanAdjustment(adjustmentType: .deload, trigger: .scheduledDeload, description: "Week 4 deload"),
            PlanAdjustment(adjustmentType: .deload, trigger: .recoverySignal, description: "Fatigue deload"),
            PlanAdjustment(adjustmentType: .loadIncrease, trigger: .apre, description: "APRE increase"),
            PlanAdjustment(adjustmentType: .exerciseSwap, trigger: .plateauDetected, description: "Swap exercise"),
        ]

        let plan = ProgressionTestHelpers.makeTestPlan(adjustments: adjustments)
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        XCTAssertEqual(progress.deloadCount, 2)
        XCTAssertEqual(progress.adjustmentCount, 4)
    }

    // MARK: - Empty Plan Tests

    func testGenerateProgress_emptyPlan_returnsZeros() async throws {
        let plan = ProgressionTestHelpers.makeTestPlan()
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        XCTAssertEqual(progress.overallAdherence, 0)
        XCTAssertTrue(progress.exerciseProgress.isEmpty)
        XCTAssertTrue(progress.blockProgress.isEmpty)
        XCTAssertTrue(progress.weeklyVolumeHistory.isEmpty)
        XCTAssertEqual(progress.deloadCount, 0)
        XCTAssertEqual(progress.adjustmentCount, 0)
        // 0 adherence is NOT >= 0.75, so isOnTrack should be false
        XCTAssertFalse(progress.isOnTrack)
    }
}
