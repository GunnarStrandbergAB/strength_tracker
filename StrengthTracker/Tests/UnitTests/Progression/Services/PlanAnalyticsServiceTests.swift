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

        // startDate 3 weeks ago so both weeks are in the elapsed window
        let threeWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())!
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], startDate: threeWeeksAgo)
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        XCTAssertEqual(progress.overallAdherence, 0.5, accuracy: 0.001)
    }

    func testGenerateProgress_adherenceScopedToElapsedWeeks() async throws {
        // Bug scenario: 3/3 sessions completed in week 1, 9 weeks of future sessions incomplete.
        // Adherence should be 100% (3/3 elapsed), not 3/30 = 10%.
        let completedSessions = (0..<3).map { i in
            ProgressionTestHelpers.makeCompletedSession(label: "W1S\(i + 1)")
        }
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 1, absoluteWeekNumber: 1, sessions: completedSessions
        )

        var futureWeeks: [TrainingWeek] = []
        for w in 2...10 {
            let sessions = (0..<3).map { i in
                ProgressionTestHelpers.makeIncompleteSession(label: "W\(w)S\(i + 1)")
            }
            futureWeeks.append(ProgressionTestHelpers.makeTestTrainingWeek(
                weekNumber: w, absoluteWeekNumber: w, sessions: sessions
            ))
        }

        let block = ProgressionTestHelpers.makeTestTrainingBlock(
            weeks: [week1] + futureWeeks
        )

        // startDate = 5 days ago → elapsedCalendarWeeks = 0 → currentWeekNumber = 1
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], startDate: fiveDaysAgo)
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        // 3 completed / 3 elapsed = 1.0
        XCTAssertEqual(progress.overallAdherence, 1.0, accuracy: 0.001)
        XCTAssertTrue(progress.isOnTrack)
    }

    func testGenerateProgress_currentWeekFutureSessionsExcluded() async throws {
        // 5x/week plan starting Monday of this week. Only Monday's session completed.
        // Adherence should be 1.0 (1/1 elapsed), not 0.2 (1/5).
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Monday session (today or earlier) — completed
        let mondaySession = ProgressionTestHelpers.makeCompletedSession(
            label: "Monday",
            completedAt: today
        )
        var mondayWithDate = mondaySession
        mondayWithDate.scheduledDate = today

        // Future sessions (tomorrow through +4 days) — not completed
        let futureSessions: [PlannedSession] = (1...4).map { offset in
            let futureDate = calendar.date(byAdding: .day, value: offset, to: today)!
            var session = ProgressionTestHelpers.makeIncompleteSession(label: "Day+\(offset)")
            session.scheduledDate = futureDate
            return session
        }

        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 1,
            absoluteWeekNumber: 1,
            sessions: [mondayWithDate] + futureSessions
        )

        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], startDate: today)
        let sut = makeSUT()

        let progress = try await sut.generateProgress(for: plan)

        // Only Monday's session is elapsed; it's completed → 1/1 = 1.0
        XCTAssertEqual(progress.overallAdherence, 1.0, accuracy: 0.001)
        XCTAssertTrue(progress.isOnTrack)
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

    // MARK: - M20: Session-Linkage 3-Tier Resolution Tests

    func testResolveWorkout_tier1_completedWorkoutId() async throws {
        // Session has completedWorkoutId pointing directly to a workout.
        // Tier 1 should resolve it and exercise progress should reflect that workout's data.
        let exerciseId = UUID()
        let workoutId = UUID()

        let workout = makeWorkout(
            id: workoutId,
            completedAt: Date(),
            exercises: [
                makeWorkoutExercise(
                    exerciseId: exerciseId,
                    sets: [makeSet(weight: 100, reps: 5)]
                )
            ]
        )

        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: workoutId,
            completedAt: Date()
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [planExercise])

        let sut = makeSUT(workouts: [workout])
        let progress = try await sut.generateProgress(for: plan)

        let ep = try XCTUnwrap(progress.exerciseProgress.first)
        // 100kg * 5 reps = 500 total volume from the resolved workout
        XCTAssertEqual(ep.totalVolumeLifted, 500, accuracy: 0.01)
        XCTAssertEqual(ep.totalSetsCompleted, 1)
    }

    func testResolveWorkout_tier2_templateId() async throws {
        // Session has no completedWorkoutId but shares a templateId with a workout.
        // Tier 2 should resolve by matching templateId.
        let exerciseId = UUID()
        let sharedTemplateId = UUID()

        let workout = makeWorkout(
            completedAt: Date(),
            templateId: sharedTemplateId,
            exercises: [
                makeWorkoutExercise(
                    exerciseId: exerciseId,
                    sets: [makeSet(weight: 80, reps: 8)]
                )
            ]
        )

        var session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: nil,
            completedAt: nil
        )
        session.templateId = sharedTemplateId

        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [planExercise])

        let sut = makeSUT(workouts: [workout])
        let progress = try await sut.generateProgress(for: plan)

        let ep = try XCTUnwrap(progress.exerciseProgress.first)
        // 80kg * 8 reps = 640 total volume from the tier-2 resolved workout
        XCTAssertEqual(ep.totalVolumeLifted, 640, accuracy: 0.01)
        XCTAssertEqual(ep.totalSetsCompleted, 1)
    }

    func testResolveWorkout_tier3_dateProximity() async throws {
        // Session has scheduledDate and no other linkage. Workout completed within 2 days.
        // Tier 3 should resolve by date proximity.
        let exerciseId = UUID()
        let scheduledDate = Date(timeIntervalSinceReferenceDate: 0)
        // Workout completed 1 day after the scheduled date (within 2-day window)
        let completedAt = scheduledDate.addingTimeInterval(86400)

        let workout = makeWorkout(
            completedAt: completedAt,
            exercises: [
                makeWorkoutExercise(
                    exerciseId: exerciseId,
                    sets: [makeSet(weight: 60, reps: 10)]
                )
            ]
        )

        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: nil,
            completedAt: nil,
            scheduledDate: scheduledDate
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [planExercise])

        let sut = makeSUT(workouts: [workout])
        let progress = try await sut.generateProgress(for: plan)

        let ep = try XCTUnwrap(progress.exerciseProgress.first)
        // 60kg * 10 reps = 600 total volume from the tier-3 proximity-resolved workout
        XCTAssertEqual(ep.totalVolumeLifted, 600, accuracy: 0.01)
    }

    func testResolveWorkout_tier3_picksClosestMatch() async throws {
        // Two workouts both within 2 days of scheduledDate. The closer one should be picked.
        let exerciseId = UUID()
        let scheduledDate = Date(timeIntervalSinceReferenceDate: 0)

        // Workout A: 6 hours away (closer)
        let workoutA = makeWorkout(
            completedAt: scheduledDate.addingTimeInterval(6 * 3600),
            exercises: [
                makeWorkoutExercise(
                    exerciseId: exerciseId,
                    sets: [makeSet(weight: 100, reps: 5)] // volume = 500
                )
            ]
        )

        // Workout B: 36 hours away (further, but still within 2 days)
        let workoutB = makeWorkout(
            completedAt: scheduledDate.addingTimeInterval(36 * 3600),
            exercises: [
                makeWorkoutExercise(
                    exerciseId: exerciseId,
                    sets: [makeSet(weight: 50, reps: 5)] // volume = 250, distinguishable
                )
            ]
        )

        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: nil,
            completedAt: nil,
            scheduledDate: scheduledDate
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [planExercise])

        let sut = makeSUT(workouts: [workoutA, workoutB])
        let progress = try await sut.generateProgress(for: plan)

        let ep = try XCTUnwrap(progress.exerciseProgress.first)
        // Should have picked workoutA (closer) with volume = 500
        XCTAssertEqual(ep.totalVolumeLifted, 500, accuracy: 0.01)
    }

    func testResolveWorkout_noMatch_returnsNoData() async throws {
        // Session has no completedWorkoutId, no templateId, and scheduledDate is
        // far outside the 2-day proximity window. No workout should be resolved.
        let exerciseId = UUID()
        let scheduledDate = Date(timeIntervalSinceReferenceDate: 0)
        // Workout completed 5 days away - outside the 2-day window
        let completedAt = scheduledDate.addingTimeInterval(5 * 86400)

        let workout = makeWorkout(
            completedAt: completedAt,
            exercises: [
                makeWorkoutExercise(
                    exerciseId: exerciseId,
                    sets: [makeSet(weight: 80, reps: 5)]
                )
            ]
        )

        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: nil,
            completedAt: nil,
            scheduledDate: scheduledDate
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [planExercise])

        let sut = makeSUT(workouts: [workout])
        let progress = try await sut.generateProgress(for: plan)

        let ep = try XCTUnwrap(progress.exerciseProgress.first)
        // No workout resolved; no volume or sets attributed
        XCTAssertEqual(ep.totalVolumeLifted, 0, accuracy: 0.01)
        XCTAssertEqual(ep.totalSetsCompleted, 0)
    }

    // MARK: - M21: Block Progress volumeTrend and averageRPE Tests

    func testBlockProgress_volumeTrend_positive() async throws {
        // Block with 2 weeks: first week lower volume, last week higher.
        // volumeTrend = (lastVolume - firstVolume) / firstVolume, expected positive.
        let workoutId1 = UUID()
        let workoutId2 = UUID()

        // Week 1: 1 set of 80kg x 5 = 400 volume
        let workout1 = makeWorkout(
            id: workoutId1,
            completedAt: Date(),
            exercises: [makeWorkoutExercise(exerciseId: UUID(), sets: [makeSet(weight: 80, reps: 5)])]
        )
        // Week 2: 1 set of 100kg x 5 = 500 volume
        let workout2 = makeWorkout(
            id: workoutId2,
            completedAt: Date(),
            exercises: [makeWorkoutExercise(exerciseId: UUID(), sets: [makeSet(weight: 100, reps: 5)])]
        )

        let session1 = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: workoutId1,
            completedAt: Date()
        )
        let session2 = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: workoutId2,
            completedAt: Date()
        )

        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session1])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [session2])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        let sut = makeSUT(workouts: [workout1, workout2])
        let progress = try await sut.generateProgress(for: plan)

        let bp = try XCTUnwrap(progress.blockProgress.first)
        // (500 - 400) / 400 = 0.25 -> positive trend
        XCTAssertGreaterThan(bp.volumeTrend, 0)
        XCTAssertEqual(bp.volumeTrend, 0.25, accuracy: 0.001)
    }

    func testBlockProgress_averageRPE_calculated() async throws {
        // Block where resolved workout sets carry RPE values.
        // averageRPE should be computed from those values.
        let workoutId = UUID()

        let setWithRPE1 = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 80, reps: 5,
            durationSeconds: nil, distanceMeters: nil,
            rpe: 7.0, isCompleted: true, isPersonalRecord: false, completedAt: nil
        )
        let setWithRPE2 = ExerciseSet(
            id: UUID(), order: 1, setType: .normal,
            weight: 80, reps: 5,
            durationSeconds: nil, distanceMeters: nil,
            rpe: 9.0, isCompleted: true, isPersonalRecord: false, completedAt: nil
        )

        let workout = makeWorkout(
            id: workoutId,
            completedAt: Date(),
            exercises: [makeWorkoutExercise(exerciseId: UUID(), sets: [setWithRPE1, setWithRPE2])]
        )

        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: workoutId,
            completedAt: Date()
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        let sut = makeSUT(workouts: [workout])
        let progress = try await sut.generateProgress(for: plan)

        let bp = try XCTUnwrap(progress.blockProgress.first)
        let averageRPE = try XCTUnwrap(bp.averageRPE)
        // (7.0 + 9.0) / 2 = 8.0
        XCTAssertEqual(averageRPE, 8.0, accuracy: 0.001)
    }

    // MARK: - M21: Weekly Volume History Tests

    func testWeeklyVolumeHistory_completedWeeksOnly() async throws {
        // Week 1 is fully completed (all sessions done), week 2 is not.
        // Only week 1 should appear in weeklyVolumeHistory.
        let workoutId = UUID()

        let workout = makeWorkout(
            id: workoutId,
            completedAt: Date(),
            exercises: [makeWorkoutExercise(exerciseId: UUID(), sets: [makeSet(weight: 100, reps: 5)])]
        )

        let completedSession = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: workoutId,
            completedAt: Date()
        )
        let incompleteSession = ProgressionTestHelpers.makeIncompleteSession(label: "S2")

        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 1,
            absoluteWeekNumber: 1,
            sessions: [completedSession]
        )
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(
            weekNumber: 2,
            absoluteWeekNumber: 2,
            sessions: [incompleteSession]
        )
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        let sut = makeSUT(workouts: [workout])
        let progress = try await sut.generateProgress(for: plan)

        // Only week 1 (all sessions completed) appears in history
        XCTAssertEqual(progress.weeklyVolumeHistory.count, 1)
        let wv = try XCTUnwrap(progress.weeklyVolumeHistory.first)
        XCTAssertEqual(wv.weekNumber, 1)
        // 100kg * 5 reps = 500 volume
        XCTAssertEqual(wv.totalVolume, 500, accuracy: 0.01)
    }

    // MARK: - Exercise Progress: Personal Records Tests

    func testExerciseProgress_personalRecordsHit_counted() async throws {
        // Workouts with PR-flagged sets should increment personalRecordsHit.
        let exerciseId = UUID()
        let workoutId = UUID()

        let prSet = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 120, reps: 3,
            durationSeconds: nil, distanceMeters: nil,
            rpe: nil, isCompleted: true, isPersonalRecord: true, completedAt: nil
        )
        let normalSet = ExerciseSet(
            id: UUID(), order: 1, setType: .normal,
            weight: 100, reps: 5,
            durationSeconds: nil, distanceMeters: nil,
            rpe: nil, isCompleted: true, isPersonalRecord: false, completedAt: nil
        )

        let workout = makeWorkout(
            id: workoutId,
            completedAt: Date(),
            exercises: [makeWorkoutExercise(exerciseId: exerciseId, sets: [prSet, normalSet])]
        )

        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: workoutId,
            completedAt: Date()
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let planExercise = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: exerciseId)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [planExercise])

        let sut = makeSUT(workouts: [workout])
        let progress = try await sut.generateProgress(for: plan)

        let ep = try XCTUnwrap(progress.exerciseProgress.first)
        XCTAssertEqual(ep.personalRecordsHit, 1)
    }
}
