import XCTest
@testable import StrengthTrackerShared

@MainActor
final class AdaptiveAdjustmentServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        workouts: [Workout] = []
    ) -> AdaptiveAdjustmentService {
        let repo = MockWorkoutRepositoryProgression()
        repo.workouts = workouts
        return AdaptiveAdjustmentService(workoutRepository: repo)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        exercises: [WorkoutExercise] = []
    ) -> Workout {
        Workout(
            id: id,
            name: "Workout",
            startedAt: completedAt.addingTimeInterval(-3600),
            completedAt: completedAt,
            notes: nil,
            templateId: nil,
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

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    // MARK: - No Issues

    func testAnalyze_noIssues_returnsEmpty() async throws {
        // Recent workout (yesterday), no regression, no decline
        let workout = makeWorkout(completedAt: daysAgo(1))
        let plan = ProgressionTestHelpers.makeTestPlan()
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: [workout])

        XCTAssertTrue(proposals.isEmpty)
    }

    // MARK: - Detraining Gap Tests

    func testAnalyze_detrainingGap_proposesDeload() async throws {
        // Last workout was 30 days ago (within 21-42 range, severity 0.6)
        // Need 2 deload signals for multi-signal trigger.
        // Create a plan with an exercise where 1RM has declined >5% to get a second signal.
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Squat",
            current1RM: 100.0
        )

        // Two sessions (30 and 33 days ago) with lower 1RM performance: a decline
        // sustained over two sessions counts as a performance signal.
        let workouts = [30, 33].map { days -> Workout in
            let weakSets = [makeSet(weight: 80, reps: 5)] // 1RM estimate ~93.3, decline > 5% from 100
            let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: weakSets)
            return makeWorkout(completedAt: daysAgo(days), exercises: [we])
        }

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        // Should have at least 1 deload proposal (from multi-signal: detraining + performance decline)
        XCTAssertFalse(proposals.isEmpty, "Should propose deload for 30-day gap + performance decline")
        let deloadProposals = proposals.filter { $0.adjustment.adjustmentType == .deload }
        XCTAssertFalse(deloadProposals.isEmpty, "Should contain a deload proposal")
    }

    // MARK: - Beginner Regression Tests

    func testAnalyze_beginnerRegression_2misses_proposes5pctReduction() async throws {
        let exerciseId = UUID()
        let planExerciseId = UUID()

        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: planExerciseId,
            exerciseId: exerciseId,
            name: "Bench Press",
            current1RM: 60.0
        )

        // Create planned sessions with target reps
        let plannedSet = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            targetReps: 8
        )
        // Regression targets are resolved per completed session — link workouts to sessions
        let workout1Id = UUID()
        let workout2Id = UUID()
        let session1 = ProgressionTestHelpers.makeTestPlannedSession(
            label: "S1",
            exercises: [plannedSet],
            completedWorkoutId: workout1Id,
            completedAt: daysAgo(1)
        )
        let session2 = ProgressionTestHelpers.makeTestPlannedSession(
            label: "S2",
            exercises: [plannedSet],
            completedWorkoutId: workout2Id,
            completedAt: daysAgo(3)
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session1, session2])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])

        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [planExercise],
            trainingStatus: .beginner
        )

        // 2 consecutive workouts where reps < target (8)
        let workout1Exercise = makeWorkoutExercise(
            exerciseId: exerciseId,
            name: "Bench Press",
            sets: [makeSet(weight: 50, reps: 6)] // 6 < 8 target
        )
        let workout2Exercise = makeWorkoutExercise(
            exerciseId: exerciseId,
            name: "Bench Press",
            sets: [makeSet(weight: 50, reps: 5)] // 5 < 8 target
        )

        let workouts = [
            makeWorkout(id: workout1Id, completedAt: daysAgo(1), exercises: [workout1Exercise]),
            makeWorkout(id: workout2Id, completedAt: daysAgo(3), exercises: [workout2Exercise]),
        ]

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        let regressionProposals = proposals.filter { $0.adjustment.adjustmentType == .loadDecrease }
        XCTAssertFalse(regressionProposals.isEmpty, "Should propose load decrease for 2 misses")

        // Check 5% decrease
        if let first = regressionProposals.first {
            XCTAssertEqual(first.adjustment.newValues["decreasePercent"], "5")
        }
    }

    func testAnalyze_beginnerRegression_3misses_proposes10pctReduction() async throws {
        let exerciseId = UUID()
        let planExerciseId = UUID()

        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: planExerciseId,
            exerciseId: exerciseId,
            name: "Bench Press",
            current1RM: 60.0
        )

        let plannedSet = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            targetReps: 8
        )
        // Regression targets are resolved per completed session — link workouts to sessions
        let workoutIds = (0..<3).map { _ in UUID() }
        let sessions = (0..<3).map { i in
            ProgressionTestHelpers.makeTestPlannedSession(
                label: "S\(i + 1)",
                exercises: [plannedSet],
                completedWorkoutId: workoutIds[i],
                completedAt: daysAgo(i + 1)
            )
        }
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: sessions)
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])

        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [planExercise],
            trainingStatus: .beginner
        )

        // 3 consecutive workouts with reps below target
        let workouts = (0..<3).map { i in
            let sets = [makeSet(weight: 50, reps: 5)] // 5 < 8 target
            let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Bench Press", sets: sets)
            return makeWorkout(id: workoutIds[i], completedAt: daysAgo(i + 1), exercises: [we])
        }

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        let regressionProposals = proposals.filter { $0.adjustment.adjustmentType == .loadDecrease }
        XCTAssertFalse(regressionProposals.isEmpty, "Should propose load decrease for 3 misses")

        if let first = regressionProposals.first {
            XCTAssertEqual(first.adjustment.newValues["decreasePercent"], "10")
        }
    }

    // MARK: - Multi-Signal Deload Tests

    func testAnalyze_multiSignalDeload_2signals_triggersDeload() async throws {
        // Create conditions that produce 2 deload signals:
        // 1. Detraining gap (25 days)
        // 2. Performance decline (1RM dropped > 5%)
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Deadlift",
            current1RM: 150.0
        )

        // Two sessions 25 and 28 days ago with weak performance (1RM ~116.7, decline > 5% from 150)
        let workouts = [25, 28].map { days -> Workout in
            let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Deadlift", sets: [makeSet(weight: 100, reps: 5)])
            return makeWorkout(completedAt: daysAgo(days), exercises: [we])
        }

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        let deloadProposals = proposals.filter { $0.adjustment.adjustmentType == .deload }
        XCTAssertEqual(deloadProposals.count, 1, "Should have exactly 1 deload proposal from multi-signal")
        if let deload = deloadProposals.first {
            XCTAssertEqual(deload.priority, 1, "Deload should be highest priority")
        }
    }

    func testAnalyze_singleDeloadSignal_noDeload() async throws {
        // Only 1 deload signal (detraining gap but no performance decline)
        // Workout 15 days ago, 1RM still matches
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Squat",
            current1RM: 100.0
        )

        // Workout 15 days ago with matching 1RM performance
        let strongSets = [makeSet(weight: 100, reps: 1)] // 1RM = 100, no decline
        let workoutExercise = makeWorkoutExercise(
            exerciseId: exerciseId,
            name: "Squat",
            sets: strongSets
        )
        let workout = makeWorkout(completedAt: daysAgo(15), exercises: [workoutExercise])

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: [workout])

        let deloadProposals = proposals.filter { $0.adjustment.adjustmentType == .deload }
        XCTAssertTrue(deloadProposals.isEmpty, "Single deload signal should NOT trigger deload (needs >= 2)")
    }

    // MARK: - Arbiter Tests

    func testArbiter_capsAt3Proposals() async throws {
        // Create a beginner plan with 4+ exercises, all regressing
        let exerciseIds = (0..<5).map { _ in UUID() }
        let planExerciseIds = (0..<5).map { _ in UUID() }

        let planExercises = (0..<5).map { i in
            ProgressionTestHelpers.makeTestPlanExercise(
                id: planExerciseIds[i],
                exerciseId: exerciseIds[i],
                name: "Exercise \(i)",
                current1RM: 60.0,
                order: i
            )
        }

        let plannedSets = (0..<5).map { i in
            ProgressionTestHelpers.makeTestPlannedExerciseSet(
                planExerciseId: planExerciseIds[i],
                exerciseId: exerciseIds[i],
                exerciseName: "Exercise \(i)",
                targetReps: 8
            )
        }
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "S1",
            exercises: plannedSets
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])

        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: planExercises,
            trainingStatus: .beginner
        )

        // 2 workouts with all exercises missing target reps
        let workouts = (0..<2).map { dayOffset -> Workout in
            let exercises = exerciseIds.enumerated().map { i, eid in
                makeWorkoutExercise(
                    exerciseId: eid,
                    name: "Exercise \(i)",
                    sets: [makeSet(weight: 40, reps: 5)] // 5 < 8 target
                )
            }
            return makeWorkout(completedAt: daysAgo(dayOffset + 1), exercises: exercises)
        }

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        XCTAssertLessThanOrEqual(proposals.count, 3, "Arbiter should cap at max 3 proposals")
    }

    func testArbiter_removesContradictions() async throws {
        // The arbiter should not produce both loadIncrease and loadDecrease for the same exercise.
        // Since our current implementation only generates decreases, we verify that no contradictions
        // slip through by checking that all proposals for the same exercise have the same direction.
        let exerciseId = UUID()
        let planExerciseId = UUID()

        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: planExerciseId,
            exerciseId: exerciseId,
            name: "Bench Press",
            current1RM: 60.0
        )

        let plannedSet = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            targetReps: 8
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "S1",
            exercises: [plannedSet]
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])

        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [planExercise],
            trainingStatus: .beginner
        )

        let workouts = (0..<2).map { i in
            let we = makeWorkoutExercise(
                exerciseId: exerciseId,
                name: "Bench Press",
                sets: [makeSet(weight: 50, reps: 5)]
            )
            return makeWorkout(completedAt: daysAgo(i + 1), exercises: [we])
        }

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        // Check no contradictions: no increase+decrease on same exercise
        let exerciseProposals = proposals.filter {
            $0.adjustment.affectedExerciseIds.contains(exerciseId)
        }
        let types = Set(exerciseProposals.map { $0.adjustment.adjustmentType })
        let hasIncrease = types.contains(.loadIncrease)
        let hasDecrease = types.contains(.loadDecrease) || types.contains(.deload)
        XCTAssertFalse(hasIncrease && hasDecrease, "Should not have both increase and decrease for same exercise")
    }

    func testArbiter_deloadIsHighestPriority() async throws {
        // When deload + regression both trigger, deload should have priority 1
        let exerciseId = UUID()
        let planExerciseId = UUID()

        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: planExerciseId,
            exerciseId: exerciseId,
            name: "Squat",
            current1RM: 120.0
        )

        let plannedSet = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Squat",
            targetReps: 8
        )
        // Regression targets are resolved per completed session — link workouts to sessions
        let workoutIds = (0..<2).map { _ in UUID() }
        let sessions = (0..<2).map { i in
            ProgressionTestHelpers.makeTestPlannedSession(
                label: "S\(i + 1)",
                exercises: [plannedSet],
                completedWorkoutId: workoutIds[i],
                completedAt: daysAgo(25 + i)
            )
        }
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: sessions)
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])

        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [planExercise],
            trainingStatus: .beginner
        )

        // Workouts 25+ days ago with both regression (reps < target) and performance decline
        let workouts = (0..<2).map { i -> Workout in
            let sets = [makeSet(weight: 80, reps: 5)] // reps < 8 target, 1RM ~93 < 120 (decline)
            let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: sets)
            return makeWorkout(id: workoutIds[i], completedAt: daysAgo(25 + i), exercises: [we])
        }

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        guard let first = proposals.first else {
            XCTFail("Should have at least one proposal")
            return
        }

        XCTAssertEqual(first.adjustment.adjustmentType, .deload, "Deload should be first (highest priority)")
        XCTAssertEqual(first.priority, 1)
    }

    // MARK: - Deload Volume Reduction Test

    func testDeload_reducesVolumeBy50pct() async throws {
        // Verify the deload proposal description mentions 50% volume reduction
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Deadlift",
            current1RM: 180.0
        )

        // 2 signals: detraining (30 days) + performance decline sustained over two sessions
        let workouts = [30, 33].map { days -> Workout in
            let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Deadlift", sets: [makeSet(weight: 120, reps: 5)]) // 1RM ~140, decline from 180
            return makeWorkout(completedAt: daysAgo(days), exercises: [we])
        }

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        let deloadProposals = proposals.filter { $0.adjustment.adjustmentType == .deload }
        XCTAssertFalse(deloadProposals.isEmpty, "Should produce a deload proposal")

        if let deload = deloadProposals.first {
            XCTAssertTrue(
                deload.adjustment.description.contains("50%"),
                "Deload description should mention 50% volume reduction. Got: \(deload.adjustment.description)"
            )
            XCTAssertTrue(
                deload.reasoning.contains("50%"),
                "Deload reasoning should mention 50% volume reduction. Got: \(deload.reasoning)"
            )
        }
    }

    // MARK: - m25: Detraining Severity Tier Value Tests

    func testAnalyze_detraining_10days_proposesLoadDecrease5pct() async throws {
        // 10 days gap falls in the 10-21 day tier -> severity 0.3 -> reductionPercent 5%
        // Use a matching 1RM so no performance decline signal fires.
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Squat",
            current1RM: 100.0
        )

        // Single at 100kg -> estimate = 100.0, decline = 0% -> no performance decline signal
        let sets = [makeSet(weight: 100, reps: 1)]
        let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: sets)
        let workout = makeWorkout(completedAt: daysAgo(10), exercises: [we])

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: [workout])

        // Only 1 deload signal (detraining), so no multi-signal deload.
        // The detraining-specific loadDecrease proposal should be present with reductionPercent=5.
        let detrainProposals = proposals.filter { proposal in
            proposal.adjustment.adjustmentType == .loadDecrease
                && proposal.adjustment.newValues["reductionPercent"] == "5"
        }
        XCTAssertFalse(
            detrainProposals.isEmpty,
            "10-day gap should produce a loadDecrease with reductionPercent=5. Got: \(proposals.map { "\($0.adjustment.adjustmentType) \($0.adjustment.newValues)" })"
        )
    }

    func testAnalyze_detraining_30days_proposesLoadDecrease10pct() async throws {
        // 30 days gap falls in the 21-42 day tier -> severity 0.6 -> reductionPercent 10%
        // Use a matching 1RM so no performance decline signal fires.
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Squat",
            current1RM: 100.0
        )

        // Single at 100kg -> estimate = 100.0, decline = 0% -> no performance decline signal
        let sets = [makeSet(weight: 100, reps: 1)]
        let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: sets)
        let workout = makeWorkout(completedAt: daysAgo(30), exercises: [we])

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: [workout])

        // Only 1 deload signal (detraining), so no multi-signal deload.
        // The detraining-specific loadDecrease proposal should be present with reductionPercent=10.
        let detrainProposals = proposals.filter { proposal in
            proposal.adjustment.adjustmentType == .loadDecrease
                && proposal.adjustment.newValues["reductionPercent"] == "10"
        }
        XCTAssertFalse(
            detrainProposals.isEmpty,
            "30-day gap should produce a loadDecrease with reductionPercent=10. Got: \(proposals.map { "\($0.adjustment.adjustmentType) \($0.adjustment.newValues)" })"
        )
    }

    func testAnalyze_detraining_50days_proposesLoadDecrease15pct() async throws {
        // 50 days gap falls in the 42+ day tier -> severity 0.9 -> reductionPercent 15%
        // Use a matching 1RM so no performance decline signal fires.
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            exerciseId: exerciseId,
            name: "Squat",
            current1RM: 100.0
        )

        // Single at 100kg -> estimate = 100.0, decline = 0% -> no performance decline signal
        let sets = [makeSet(weight: 100, reps: 1)]
        let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: sets)
        let workout = makeWorkout(completedAt: daysAgo(50), exercises: [we])

        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let sut = makeSUT()

        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: [workout])

        // Only 1 deload signal (detraining), so no multi-signal deload.
        // The detraining-specific loadDecrease proposal should be present with reductionPercent=15.
        // Additionally, repeatBlock=true is set for 42+ days.
        let detrainProposals = proposals.filter { proposal in
            proposal.adjustment.adjustmentType == .loadDecrease
                && proposal.adjustment.newValues["reductionPercent"] == "15"
        }
        XCTAssertFalse(
            detrainProposals.isEmpty,
            "50-day gap should produce a loadDecrease with reductionPercent=15. Got: \(proposals.map { "\($0.adjustment.adjustmentType) \($0.adjustment.newValues)" })"
        )
        // Verify 42+ day tier also sets repeatBlock flag
        if let proposal = detrainProposals.first {
            XCTAssertEqual(
                proposal.adjustment.newValues["repeatBlock"],
                "true",
                "50-day gap (42+ tier) should include repeatBlock=true"
            )
        }
    }

    // MARK: - Periodized Rep Targets (session-specific)

    func testAnalyze_periodizedRepDecrease_doesNotTriggerFalseRegression() async throws {
        // Week 1 targets 8 reps, week 3 targets 5 reps (normal periodization).
        // Hitting 5 reps in the week-3 session is NOT a miss — targets must come
        // from the completed session, not the plan's first occurrence.
        let exerciseId = UUID()
        let planExerciseId = UUID()

        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: planExerciseId,
            exerciseId: exerciseId,
            name: "Bench Press",
            current1RM: 60.0
        )

        let week1Set = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            targetReps: 8
        )
        let week3Set = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            targetReps: 5
        )

        let workout1Id = UUID()
        let workout2Id = UUID()
        let session1 = ProgressionTestHelpers.makeTestPlannedSession(
            label: "W3 S1", exercises: [week3Set],
            completedWorkoutId: workout1Id, completedAt: daysAgo(1)
        )
        let session2 = ProgressionTestHelpers.makeTestPlannedSession(
            label: "W3 S2", exercises: [week3Set],
            completedWorkoutId: workout2Id, completedAt: daysAgo(3)
        )
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 1,
            sessions: [ProgressionTestHelpers.makeTestPlannedSession(label: "W1 S1", exercises: [week1Set])]
        )
        let week3 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 3, sessions: [session1, session2])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week3])

        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [planExercise],
            trainingStatus: .beginner
        )

        // User hits exactly the week-3 target (5 reps) twice — would be flagged as
        // 2 consecutive misses against the old plan-wide 8-rep target.
        let workouts = [workout1Id, workout2Id].enumerated().map { i, id -> Workout in
            let we = makeWorkoutExercise(
                exerciseId: exerciseId, name: "Bench Press",
                sets: [makeSet(weight: 50, reps: 5)]
            )
            return makeWorkout(id: id, completedAt: daysAgo(i * 2 + 1), exercises: [we])
        }

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        let regressionProposals = proposals.filter {
            $0.adjustment.adjustmentType == .loadDecrease && $0.adjustment.trigger != .oneRMUpdate
        }
        XCTAssertTrue(regressionProposals.isEmpty,
                      "Meeting the session-specific rep target must not count as regression")
    }

    // MARK: - m26: Non-Beginner Regression Behavior

    func testAnalyze_intermediateStatus_doesNotTriggerRegressionProposals() async throws {
        // Intermediate athletes should NOT get beginner regression proposals
        // even with multiple consecutive missed reps, because detectBeginnerRegression
        // is only invoked when plan.trainingStatus == .beginner.
        let exerciseId = UUID()
        let planExerciseId = UUID()

        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: planExerciseId,
            exerciseId: exerciseId,
            name: "Bench Press",
            current1RM: 100.0
        )

        let plannedSet = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            targetReps: 8
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "S1",
            exercises: [plannedSet]
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])

        // Intermediate plan - regression detection should be skipped entirely
        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [planExercise],
            trainingStatus: .intermediate
        )

        // 3 consecutive workouts with reps well below target (same pattern as beginner 3-miss test)
        // Performance also matches current1RM (100kg single) to avoid performance decline signal
        let workouts = (0..<3).map { i in
            let sets = [makeSet(weight: 50, reps: 5)] // 5 < 8 target, and 1RM ~58 < 100 (decline)
            let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Bench Press", sets: sets)
            return makeWorkout(completedAt: daysAgo(i + 1), exercises: [we])
        }

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        // Should have no beginner regression loadDecrease proposals with "decreasePercent" key
        let regressionProposals = proposals.filter { proposal in
            proposal.adjustment.adjustmentType == .loadDecrease
                && proposal.adjustment.newValues["decreasePercent"] != nil
        }
        XCTAssertTrue(
            regressionProposals.isEmpty,
            "Intermediate plan should not produce beginner regression proposals. Got: \(proposals.map { $0.adjustment.description })"
        )
    }

    func testAnalyze_advancedStatus_doesNotTriggerRegressionProposals() async throws {
        // Advanced athletes should NOT get beginner regression proposals,
        // regardless of how many consecutive missed-rep sessions they have.
        let exerciseId = UUID()
        let planExerciseId = UUID()

        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: planExerciseId,
            exerciseId: exerciseId,
            name: "Deadlift",
            current1RM: 200.0
        )

        let plannedSet = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: planExerciseId,
            exerciseId: exerciseId,
            exerciseName: "Deadlift",
            targetReps: 5
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "S1",
            exercises: [plannedSet]
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])

        // Advanced plan - regression detection should be skipped entirely
        let plan = ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [planExercise],
            trainingStatus: .advanced
        )

        // 3 consecutive workouts with reps below target
        let workouts = (0..<3).map { i in
            let sets = [makeSet(weight: 100, reps: 3)] // 3 < 5 target
            let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Deadlift", sets: sets)
            return makeWorkout(completedAt: daysAgo(i + 1), exercises: [we])
        }

        let sut = makeSUT()
        let proposals = try await sut.analyzeAndPropose(plan: plan, recentWorkouts: workouts)

        // Should have no beginner regression proposals (keyed by "decreasePercent")
        let regressionProposals = proposals.filter { proposal in
            proposal.adjustment.adjustmentType == .loadDecrease
                && proposal.adjustment.newValues["decreasePercent"] != nil
        }
        XCTAssertTrue(
            regressionProposals.isEmpty,
            "Advanced plan should not produce beginner regression proposals. Got: \(proposals.map { $0.adjustment.description })"
        )
    }

    // MARK: - Verdict gating and signal dedupe

    private func makeVerdict(_ kind: TrainingVerdict.Kind, active: Bool = false) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: 0.6, reasons: ["test"], signals: [], action: "Take a lighter week",
                        since: Date(), computedAt: Date(), isActiveDeload: active)
    }

    func testPerformanceDecline_singleSessionSingleExercise_isNotASignal() async throws {
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId, name: "Squat", current1RM: 100.0)
        let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: [makeSet(weight: 80, reps: 5)])
        let workout = makeWorkout(completedAt: daysAgo(30), exercises: [we])
        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])

        let report = makeSUT().collectInsights(plan: plan, recentWorkouts: [workout])
        XCTAssertEqual(report.deloadSignals.filter { $0.source == .reactivePerformance }.count, 0)
    }

    func testPerformanceDecline_twoExercisesInOneSession_isOneSignal() async throws {
        let squatId = UUID(), benchId = UUID()
        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [
            ProgressionTestHelpers.makeTestPlanExercise(exerciseId: squatId, name: "Squat", current1RM: 100.0),
            ProgressionTestHelpers.makeTestPlanExercise(exerciseId: benchId, name: "Bench", current1RM: 100.0),
        ])
        let workout = makeWorkout(completedAt: daysAgo(2), exercises: [
            makeWorkoutExercise(exerciseId: squatId, name: "Squat", sets: [makeSet(weight: 80, reps: 5)]),
            makeWorkoutExercise(exerciseId: benchId, name: "Bench", sets: [makeSet(weight: 80, reps: 5)]),
        ])

        let report = makeSUT().collectInsights(plan: plan, recentWorkouts: [workout])
        XCTAssertEqual(report.deloadSignals.filter { $0.source == .reactivePerformance }.count, 1,
                       "Two declining exercises produce exactly one performance signal")
    }

    func testPerformanceDecline_ignoresDeloadSessions() async throws {
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId, name: "Squat", current1RM: 100.0)
        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        let workouts = [2, 5].map { days -> Workout in
            var w = makeWorkout(completedAt: daysAgo(days), exercises: [
                makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: [makeSet(weight: 60, reps: 5)])
            ])
            w.isDeload = true
            return w
        }

        let report = makeSUT().collectInsights(plan: plan, recentWorkouts: workouts)
        XCTAssertTrue(report.deloadSignals.isEmpty)
    }

    func testDeloadVerdict_withOneSignal_proposesDeload() async throws {
        // Only the detraining signal, but the coach verdict says deload.
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId, name: "Squat", current1RM: 100.0)
        let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: [makeSet(weight: 100, reps: 1)])
        let workout = makeWorkout(completedAt: daysAgo(15), exercises: [we])
        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])

        let proposals = try await makeSUT().analyzeAndPropose(plan: plan, recentWorkouts: [workout], verdict: makeVerdict(.deload))
        XCTAssertEqual(proposals.filter { $0.adjustment.adjustmentType == .deload }.count, 1)
    }

    func testProgressVerdict_withOneSignal_noDeload() async throws {
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId, name: "Squat", current1RM: 100.0)
        let we = makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: [makeSet(weight: 100, reps: 1)])
        let workout = makeWorkout(completedAt: daysAgo(15), exercises: [we])
        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])

        let proposals = try await makeSUT().analyzeAndPropose(plan: plan, recentWorkouts: [workout], verdict: makeVerdict(.progress))
        XCTAssertTrue(proposals.filter { $0.adjustment.adjustmentType == .deload }.isEmpty)
    }

    func testDeloadSessionThisWeek_suppressesDeloadProposal() async throws {
        let exerciseId = UUID()
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId, name: "Squat", current1RM: 100.0)
        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [planExercise])
        // Sustained decline 30+ days ago (two signals), plus a deload logged today.
        var workouts = [30, 33].map { days -> Workout in
            makeWorkout(completedAt: daysAgo(days), exercises: [
                makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: [makeSet(weight: 80, reps: 5)])
            ])
        }
        var deload = makeWorkout(completedAt: Date(), exercises: [
            makeWorkoutExercise(exerciseId: exerciseId, name: "Squat", sets: [makeSet(weight: 60, reps: 5)])
        ])
        deload.isDeload = true
        workouts.append(deload)

        let proposals = try await makeSUT().analyzeAndPropose(plan: plan, recentWorkouts: workouts, verdict: makeVerdict(.deload))
        XCTAssertTrue(proposals.filter { $0.adjustment.adjustmentType == .deload }.isEmpty,
                      "No deload proposal while a deload session is already logged this week")
    }

    func testRemoveContradictions_blockWideDeloadSuppressesLoadIncrease() {
        let exerciseId = UUID()
        let deload = ProposedAdjustment(
            adjustment: PlanAdjustment(adjustmentType: .deload, trigger: .recoverySignal, description: "d", affectedBlockIds: [UUID()]),
            priority: 1, reasoning: "r"
        )
        let increase = ProposedAdjustment(
            adjustment: PlanAdjustment(adjustmentType: .loadIncrease, trigger: .apre, description: "i", affectedExerciseIds: [exerciseId]),
            priority: 3, reasoning: "r"
        )
        let result = makeSUT().removeContradictions([increase, deload])
        XCTAssertEqual(result.map { $0.adjustment.adjustmentType }, [.deload])
    }
}
