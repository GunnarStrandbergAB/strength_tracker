import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("SessionExecutionService Tests")
struct SessionExecutionServiceTests {

    let sut = SessionExecutionService()

    // MARK: - Shared IDs for deterministic tests

    let benchId = UUID()
    let squatId = UUID()
    let benchPlanExId = UUID()
    let squatPlanExId = UUID()

    // MARK: - completeSession: linking

    @Test("completeSession links workout to session via completedWorkoutId and completedAt")
    func testCompleteSession_linksWorkoutToSession() {
        let session = ProgressionTestHelpers.makeTestPlannedSession(label: "Day A")
        let completionDate = Date()
        let workout = makeWorkout(completedAt: completionDate, exercises: [])

        let result = sut.completeSession(session, workout: workout, planExercises: [], bodyWeightKg: 70)

        #expect(result.updatedSession.completedWorkoutId == workout.id)
        #expect(result.updatedSession.completedAt == completionDate)
    }

    @Test("completeSession captures workout notes into userWorkoutNotes")
    func testCompleteSession_capturesWorkoutNotes() {
        let session = ProgressionTestHelpers.makeTestPlannedSession(label: "Day A")
        let workout = makeWorkout(notes: "Felt strong today", exercises: [])

        let result = sut.completeSession(session, workout: workout, planExercises: [], bodyWeightKg: 70)

        #expect(result.updatedSession.userWorkoutNotes == "Felt strong today")
    }

    // MARK: - completeSession: 1RM updates

    @Test("completeSession updates 1RM with EWMA smoothing (alpha=0.3)")
    func testCompleteSession_updates1RM_withEWMA() {
        // PlanExercise: current1RM = 100.0
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchId,
            exerciseName: "Bench Press",
            sets: 3,
            targetReps: 5,
            targetWeight: 85.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "Day A",
            exercises: [planned]
        )

        // Completed 90kg x 5 -> Epley: 90*(1+5/30) = 105.0
        let sets = [
            makeCompletedSet(weight: 90.0, reps: 5, order: 0),
            makeCompletedSet(weight: 90.0, reps: 5, order: 1),
            makeCompletedSet(weight: 90.0, reps: 5, order: 2),
        ]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])

        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)

        // The estimated 1RM from best set: 90*(1+5/30)=105
        // Deviation: |105-100|/100 = 0.05 <= 0.15 (not outlier)
        // Asymmetric EWMA: estimates >= current are accepted immediately (PRs are real),
        // smoothing only applies on the way down. 105 >= 100 -> 105.
        #expect(result.updatedExercises[0].current1RM == 105.0)
        #expect(result.adjustments.contains(where: { $0.trigger == .oneRMUpdate }))
    }

    @Test("completeSession rejects 1RM outlier when deviation > 15%")
    func testCompleteSession_rejects1RMOutlier() {
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchId,
            exerciseName: "Bench Press",
            sets: 1,
            targetReps: 5,
            targetWeight: 85.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "Day A",
            exercises: [planned]
        )

        // 120kg x 5 -> Epley: 120*(1+5/30) = 140
        // Deviation: |140-100|/100 = 0.40 > 0.15 -> REJECT
        let sets = [makeCompletedSet(weight: 120.0, reps: 5, order: 0)]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])

        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)

        // 1RM should NOT be updated
        #expect(result.updatedExercises[0].current1RM == 100.0)
        #expect(!result.adjustments.contains(where: { $0.trigger == .oneRMUpdate }))
    }

    @Test("completeSession regression guard: small drop (3%) does NOT adjust downward")
    func testCompleteSession_regressionGuard() {
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchId,
            exerciseName: "Bench Press",
            sets: 1,
            targetReps: 1,
            targetWeight: 95.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "Day A",
            exercises: [planned]
        )

        // Single at 97kg -> estimate = 97.0
        // Deviation: |97-100|/100 = 0.03 <= 0.15 (not outlier)
        // EWMA: 0.3*97 + 0.7*100 = 99.1 -> rounded to 100.0
        // Since rounded == current (100.0), no adjustment created.
        // Even if different: estimated 97 >= 95 (0.95*100), so regression guard blocks.
        let sets = [makeCompletedSet(weight: 97.0, reps: 1, order: 0)]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])

        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)

        // Should remain at 100 due to regression guard or rounding
        #expect(result.updatedExercises[0].current1RM == 100.0)
    }

    @Test("completeSession large regression (>5%) applies downward adjustment")
    func testCompleteSession_largeRegression_appliesUpdate() {
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchId,
            exerciseName: "Bench Press",
            sets: 1,
            targetReps: 1,
            targetWeight: 85.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "Day A",
            exercises: [planned]
        )

        // Single at 90kg -> estimate = 90.0
        // Deviation: |90-100|/100 = 0.10 <= 0.15 (not outlier)
        // EWMA: 0.3*90 + 0.7*100 = 97.0 -> rounded to 97.5
        // estimated (90) < 0.95*100 (95) -> regression guard allows
        let sets = [makeCompletedSet(weight: 90.0, reps: 1, order: 0)]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])

        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)

        #expect(result.updatedExercises[0].current1RM == 97.5)
        let oneRMAdjustment = result.adjustments.first(where: { $0.trigger == .oneRMUpdate })
        #expect(oneRMAdjustment != nil)
        #expect(oneRMAdjustment?.adjustmentType == .loadDecrease)
    }

    @Test("completeSession generates PlanAdjustment with correct type and trigger")
    func testCompleteSession_generatesAdjustmentRecord() {
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchId,
            exerciseName: "Bench Press",
            sets: 3,
            targetReps: 5,
            targetWeight: 85.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "Day A",
            exercises: [planned]
        )

        // 92kg x 5 -> Epley: 92*(1+5/30)=107.33 -> estimate rounds to 107.5
        // Deviation: |107.5-100|/100=0.075 <= 0.15
        // Asymmetric EWMA: estimates >= current are accepted immediately -> 107.5
        let sets = [makeCompletedSet(weight: 92.0, reps: 5, order: 0)]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])

        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)

        let adj = result.adjustments.first(where: { $0.trigger == .oneRMUpdate })
        #expect(adj != nil)
        #expect(adj?.adjustmentType == .loadIncrease)
        #expect(adj?.affectedExerciseIds == [benchPlanExId])
        #expect(adj?.previousValues["current1RM"] == "100.0")
        #expect(adj?.newValues["current1RM"] == "107.5")
    }

    // MARK: - estimateCurrent1RM

    @Test("estimateCurrent1RM: single rep returns exact weight")
    func testEstimateCurrent1RM_singleRep() {
        let sets = [makeCompletedSet(weight: 100.0, reps: 1, order: 0)]
        let result = sut.estimateCurrent1RM(from: sets)
        #expect(result == 100.0)
    }

    @Test("estimateCurrent1RM: 5 reps uses Epley formula")
    func testEstimateCurrent1RM_fiveReps_epley() {
        // 100 * (1 + 5/30) = 100 * 1.1667 = 116.67 -> rounded to 117.5
        let sets = [makeCompletedSet(weight: 100.0, reps: 5, order: 0)]
        let result = sut.estimateCurrent1RM(from: sets)
        #expect(result == 117.5)
    }

    @Test("estimateCurrent1RM: 10 reps uses Brzycki formula")
    func testEstimateCurrent1RM_tenReps_brzycki() {
        // 80 * 36 / (37 - 10) = 80 * 36/27 = 80 * 1.3333 = 106.67 -> rounded to 107.5
        let sets = [makeCompletedSet(weight: 80.0, reps: 10, order: 0)]
        let result = sut.estimateCurrent1RM(from: sets)
        #expect(result == 107.5)
    }

    @Test("estimateCurrent1RM: high reps (>15) are ignored, returns nil")
    func testEstimateCurrent1RM_highReps_ignored() {
        let sets = [makeCompletedSet(weight: 50.0, reps: 20, order: 0)]
        let result = sut.estimateCurrent1RM(from: sets)
        #expect(result == nil)
    }

    @Test("estimateCurrent1RM: no completed sets returns nil")
    func testEstimateCurrent1RM_noCompletedSets_returnsNil() {
        let sets = [
            ExerciseSet(
                id: UUID(), order: 0, setType: .normal,
                weight: 100.0, reps: 5,
                durationSeconds: nil, distanceMeters: nil, rpe: nil,
                isCompleted: false, isPersonalRecord: false, completedAt: nil
            )
        ]
        let result = sut.estimateCurrent1RM(from: sets)
        #expect(result == nil)
    }

    @Test("estimateCurrent1RM: takes highest estimate from multiple sets")
    func testEstimateCurrent1RM_takesHighestEstimate() {
        let sets = [
            makeCompletedSet(weight: 80.0, reps: 5, order: 0),  // Epley: 80*(1+5/30)=93.33 -> 92.5
            makeCompletedSet(weight: 100.0, reps: 1, order: 1), // Single: 100.0
            makeCompletedSet(weight: 70.0, reps: 10, order: 2), // Brzycki: 70*36/27=93.33 -> 92.5
        ]
        let result = sut.estimateCurrent1RM(from: sets)
        // Best is 100.0 from the single
        #expect(result == 100.0)
    }

    // MARK: - m23: Warmup set exclusion in 1RM estimation

    @Test("estimateCurrent1RM excludes warmup sets")
    func testEstimateCurrent1RM_excludesWarmupSets() {
        let sets = [
            makeCompletedSet(weight: 40.0, reps: 10, order: 0, setType: .warmup),  // Warmup - should be ignored
            makeCompletedSet(weight: 60.0, reps: 5, order: 1, setType: .warmup),   // Warmup - should be ignored
            makeCompletedSet(weight: 80.0, reps: 5, order: 2),                      // Working: Epley 80*(1+5/30)=93.33 -> 92.5
        ]
        let result = sut.estimateCurrent1RM(from: sets)
        // Only the working set (80x5) should count: 80*(1+5/30) = 93.33 -> rounded to 92.5
        #expect(result == 92.5)
    }

    // MARK: - m24: EWMA 15% boundary tests

    @Test("completeSession accepts 1RM estimate at exactly 15% deviation boundary")
    func testCompleteSession_accepts1RM_atExactBoundary() {
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchId,
            exerciseName: "Bench Press",
            sets: 1,
            targetReps: 1,
            targetWeight: 100.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "Day A",
            exercises: [planned]
        )

        // Single at 115kg -> estimate = 115.0
        // Deviation: |115-100|/100 = 0.15 which is exactly at the threshold (<=0.15) -> ACCEPTED
        // Asymmetric EWMA: estimates >= current are accepted immediately -> 115.0
        let sets = [makeCompletedSet(weight: 115.0, reps: 1, order: 0)]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])

        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)

        // Should be updated (deviation exactly 0.15 is accepted)
        #expect(result.updatedExercises[0].current1RM == 115.0)
        #expect(result.adjustments.contains(where: { $0.trigger == .oneRMUpdate }))
    }

    @Test("completeSession rejects 1RM estimate just over 15% deviation boundary")
    func testCompleteSession_rejects1RM_justOverBoundary() {
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchId,
            exerciseName: "Bench Press",
            sets: 1,
            targetReps: 1,
            targetWeight: 100.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            label: "Day A",
            exercises: [planned]
        )

        // Single at 117.5kg -> estimate = 117.5 (already a 2.5 multiple; M16 rounds estimates
        // to 2.5 before the outlier check, so 116 would land back ON the boundary at 115)
        // Deviation: |117.5-100|/100 = 0.175 > 0.15 -> REJECTED
        let sets = [makeCompletedSet(weight: 117.5, reps: 1, order: 0)]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])

        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)

        // 1RM should NOT be updated (deviation just over threshold)
        #expect(result.updatedExercises[0].current1RM == 100.0)
        #expect(!result.adjustments.contains(where: { $0.trigger == .oneRMUpdate }))
    }

    // MARK: - m17: First-use direct assignment

    @Test("completeSession direct assigns 1RM when current1RM is 0")
    func testCompleteSession_directAssign_whenCurrent1RMIsZero() {
        let planEx = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId, exerciseId: benchId, name: "Bench Press", current1RM: 0.0
        )
        let planned = ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId, exerciseId: benchId, exerciseName: "Bench Press",
            sets: 1, targetReps: 5, targetWeight: 60.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession(label: "Day A", exercises: [planned])
        // 80kg x 5 -> Epley: 80*(1+5/30) = 93.33 -> rounded to 92.5
        let sets = [makeCompletedSet(weight: 80.0, reps: 5, order: 0)]
        let workout = makeWorkout(exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: sets)
        ])
        let result = sut.completeSession(session, workout: workout, planExercises: [planEx], bodyWeightKg: 70)
        // Direct assign (no EWMA): 92.5
        #expect(result.updatedExercises[0].current1RM == 92.5)
    }

    // MARK: - Test Helpers

    private func makeCompletedSet(
        weight: Double,
        reps: Int,
        order: Int,
        setType: SetType = .normal
    ) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: order,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )
    }

    private func makeWorkoutExercise(
        exerciseId: UUID,
        name: String,
        sets: [ExerciseSet]
    ) -> WorkoutExercise {
        let exercise = ProgressionTestHelpers.makeTestExercise(id: exerciseId, name: name)
        return WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: sets
        )
    }

    private func makeWorkout(
        completedAt: Date? = Date(),
        notes: String? = nil,
        exercises: [WorkoutExercise]
    ) -> Workout {
        Workout(
            id: UUID(),
            name: "Test Workout",
            startedAt: Date().addingTimeInterval(-3600),
            completedAt: completedAt,
            notes: notes,
            templateId: nil,
            exercises: exercises
        )
    }

    // MARK: - Replay

    private func replayFixture() -> (plan: ProgressionPlan, first: Workout, second: Workout, sessionIds: (UUID, UUID)) {
        // Baseline 115: 100×5 (e1RM 116.7), 105×5 (122.5) and the edited 115×5 (134.2)
        // all stay inside the 15% outlier guard of the running estimate.
        let benchPlan = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: benchId, name: "Bench Press", current1RM: 115, estimated1RM: 115)
        let day = 86_400.0
        var first = makeWorkout(completedAt: Date().addingTimeInterval(-7 * day), exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: [makeCompletedSet(weight: 100, reps: 5, order: 1)])
        ])
        first.startedAt = first.completedAt!.addingTimeInterval(-3600)
        var second = makeWorkout(completedAt: Date().addingTimeInterval(-2 * day), exercises: [
            makeWorkoutExercise(exerciseId: benchId, name: "Bench Press", sets: [makeCompletedSet(weight: 105, reps: 5, order: 1)])
        ])
        second.startedAt = second.completedAt!.addingTimeInterval(-3600)
        let s1 = ProgressionTestHelpers.makeTestPlannedSession(label: "Day 1", completedWorkoutId: first.id, completedAt: first.completedAt)
        let s2 = ProgressionTestHelpers.makeTestPlannedSession(label: "Day 2", completedWorkoutId: second.id, completedAt: second.completedAt)
        let week = TrainingWeek(weekNumber: 1, absoluteWeekNumber: 1, sessions: [s1, s2])
        let block = TrainingBlock(name: "Block 1", order: 1, durationWeeks: 4, weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [benchPlan])
        return (plan, first, second, (s1.id, s2.id))
    }

    @Test("replay reproduces the incremental completion result exactly")
    func testReplay_matchesIncremental() {
        let (plan, first, second, _) = replayFixture()
        // Incremental: session 1 then session 2.
        let r1 = sut.completeSession(plan.blocks[0].weeks[0].sessions[0], workout: first, planExercises: plan.exercises, bodyWeightKg: 70)
        let r2 = sut.completeSession(plan.blocks[0].weeks[0].sessions[1], workout: second, planExercises: r1.updatedExercises, bodyWeightKg: 70)

        let replay = sut.replayCompletedSessions(plan: plan, workoutsById: [first.id: first, second.id: second], bodyWeightKg: 70)

        #expect(replay.plan.exercises[0].current1RM == r2.updatedExercises[0].current1RM)
        #expect(replay.plan.adjustments.count == r1.adjustments.count + r2.adjustments.count)
        #expect(replay.plan.adjustments.allSatisfy { $0.wasAccepted == true })
        #expect(replay.lastSessionAdjustments.count == r2.adjustments.count)
    }

    @Test("replay after an edit is not double-applied and strips the stale engine adjustments")
    func testReplay_afterEdit() {
        var (plan, first, second, _) = replayFixture()
        _ = (first, second)
        // Simulate the incremental pipeline having already run and recorded adjustments.
        let r1 = sut.completeSession(plan.blocks[0].weeks[0].sessions[0], workout: first, planExercises: plan.exercises, bodyWeightKg: 70)
        let r2 = sut.completeSession(plan.blocks[0].weeks[0].sessions[1], workout: second, planExercises: r1.updatedExercises, bodyWeightKg: 70)
        plan.exercises = r2.updatedExercises
        plan.adjustments = (r1.adjustments + r2.adjustments).map { var a = $0; a.wasAccepted = true; a.coachingExplanation = "kept"; return a }
        plan.adjustments.append(PlanAdjustment(adjustmentType: .deload, trigger: .recoverySignal, description: "Adviser", wasAccepted: nil))

        // The user corrects workout 2: it was really 115 kg, not 105.
        var edited = second
        edited.exercises[0].sets[0].weight = 115
        let replay = sut.replayCompletedSessions(plan: plan, workoutsById: [first.id: first, second.id: edited], bodyWeightKg: 70)

        let fresh2 = sut.completeSession(plan.blocks[0].weeks[0].sessions[1], workout: edited, planExercises: r1.updatedExercises, bodyWeightKg: 70)
        #expect(replay.plan.exercises[0].current1RM == fresh2.updatedExercises[0].current1RM)
        #expect(replay.plan.exercises[0].current1RM > r2.updatedExercises[0].current1RM)
        #expect(replay.plan.adjustments.contains { $0.trigger == .recoverySignal }, "non-engine adjustments survive")
        #expect(replay.plan.adjustments.filter { $0.trigger == .oneRMUpdate }.count == 2, "engine rows rebuilt, not stacked")
        #expect(replay.plan.adjustments.first { $0.description == r1.adjustments[0].description }?.coachingExplanation == "kept",
                "unchanged adjustment keeps its explanation")
    }

    @Test("replay after an unlink drops the session's contribution")
    func testReplay_afterUnlink() {
        var (plan, first, second, _) = replayFixture()
        let r1 = sut.completeSession(plan.blocks[0].weeks[0].sessions[0], workout: first, planExercises: plan.exercises, bodyWeightKg: 70)
        plan.blocks[0].weeks[0].sessions[1].completedWorkoutId = nil
        plan.blocks[0].weeks[0].sessions[1].completedAt = nil

        let replay = sut.replayCompletedSessions(plan: plan, workoutsById: [first.id: first, second.id: second], bodyWeightKg: 70)
        #expect(replay.plan.exercises[0].current1RM == r1.updatedExercises[0].current1RM)
        #expect(replay.plan.blocks[0].weeks[0].sessions[1].completedWorkoutId == nil)
    }
}
