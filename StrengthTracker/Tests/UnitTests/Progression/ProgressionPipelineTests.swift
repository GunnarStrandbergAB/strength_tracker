#if canImport(SwiftData)
import Foundation
import Testing
@testable import StrengthTrackerShared

/// End-to-end tests for the adaptive session-completion pipeline
/// (ProgressionPlanViewModel.handleSessionCompleted + accept/dismissAdjustment).
@Suite("Adaptive progression pipeline")
@MainActor
struct ProgressionPipelineTests {

    // MARK: - Shared deterministic IDs

    private let benchLibId = UUID()
    private let benchPlanExId = UUID()
    private let sessionAId = UUID()
    private let sessionBId = UUID()

    // MARK: - Fixtures

    private struct Fixture {
        let vm: ProgressionPlanViewModel
        let planRepo: InMemoryProgressionPlanRepository
        let workoutRepo: MockWorkoutRepositoryProgression
    }

    private func makeFixture(
        plan: ProgressionPlan,
        workouts: [Workout] = [],
        withAdviser: Bool = false
    ) -> Fixture {
        let planRepo = InMemoryProgressionPlanRepository()
        planRepo.plans = [plan]
        let workoutRepo = MockWorkoutRepositoryProgression()
        workoutRepo.workouts = workouts

        let vm = ProgressionPlanViewModel(
            progressionPlanRepository: planRepo,
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: workoutRepo),
            programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: workoutRepo),
            exerciseRepository: PipelineStubExerciseRepository(),
            templateRepository: PipelineStubTemplateRepository(),
            workoutRepository: workoutRepo,
            sessionExecutionService: SessionExecutionService(),
            adaptiveAdjustmentService: withAdviser
                ? AdaptiveAdjustmentService(workoutRepository: workoutRepo)
                : nil,
            coachingCommunicationService: CoachingCommunicationService()
        )
        return Fixture(vm: vm, planRepo: planRepo, workoutRepo: workoutRepo)
    }

    /// Plan with one block / one week / two sessions, both prescribing bench at 80% of a
    /// 100 kg 1RM. Session A is the one being completed; session B is the future session
    /// used to verify propagation.
    private func makePlan(
        trainingStatus: TrainingStatus = .intermediate,
        adjustments: [PlanAdjustment] = []
    ) -> ProgressionPlan {
        let benchPE = ProgressionTestHelpers.makeTestPlanExercise(
            id: benchPlanExId,
            exerciseId: benchLibId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let sessionA = ProgressionTestHelpers.makeTestPlannedSession(
            id: sessionAId,
            label: "Session A",
            exercises: [makeBenchSet()]
        )
        let sessionB = ProgressionTestHelpers.makeTestPlannedSession(
            id: sessionBId,
            label: "Session B",
            exercises: [makeBenchSet()]
        )
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [sessionA, sessionB])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        return ProgressionTestHelpers.makeTestPlan(
            blocks: [block],
            exercises: [benchPE],
            trainingStatus: trainingStatus,
            adjustments: adjustments
        )
    }

    private func makeBenchSet() -> PlannedExerciseSet {
        ProgressionTestHelpers.makeTestPlannedExerciseSet(
            planExerciseId: benchPlanExId,
            exerciseId: benchLibId,
            exerciseName: "Bench Press",
            sets: 3,
            targetReps: 5,
            targetWeight: 80.0,
            percentageOf1RM: 0.80
        )
    }

    private func makeBenchWorkout(
        id: UUID = UUID(),
        weight: Double,
        reps: Int,
        setCount: Int = 3,
        completedAt: Date = Date()
    ) -> Workout {
        let sets = (0..<setCount).map { order in
            ExerciseSet(
                id: UUID(),
                order: order,
                setType: .normal,
                weight: weight,
                reps: reps,
                durationSeconds: nil,
                distanceMeters: nil,
                rpe: nil,
                isCompleted: true,
                isPersonalRecord: false,
                completedAt: completedAt
            )
        }
        let exercise = ProgressionTestHelpers.makeTestExercise(id: benchLibId, name: "Bench Press")
        return Workout(
            id: id,
            name: "Bench Day",
            startedAt: completedAt.addingTimeInterval(-3600),
            completedAt: completedAt,
            notes: nil,
            templateId: nil,
            exercises: [
                WorkoutExercise(
                    id: UUID(),
                    exercise: exercise,
                    order: 0,
                    supersetGroup: nil,
                    notes: nil,
                    restTimerSeconds: nil,
                    sets: sets
                )
            ]
        )
    }

    private func session(_ id: UUID, in plan: ProgressionPlan) -> PlannedSession? {
        plan.blocks.flatMap(\.weeks).flatMap(\.sessions).first { $0.id == id }
    }

    // MARK: - 1: Completion + engine 1RM update

    @Test("handleSessionCompleted marks the session completed and updates current1RM via the engine")
    func completionUpdatesOneRM() async {
        let plan = makePlan()
        // 90 kg x 5 -> Epley: 90 * (1 + 5/30) = 105. PR (>= current 100) is accepted
        // immediately by the asymmetric EWMA -> current1RM = 105.
        let workout = makeBenchWorkout(weight: 90.0, reps: 5)
        let fixture = makeFixture(plan: plan, workouts: [workout])

        await fixture.vm.handleSessionCompleted(sessionId: sessionAId, planId: plan.id, workoutId: workout.id)

        let saved = fixture.planRepo.plans[0]
        #expect(session(sessionAId, in: saved)?.completedWorkoutId == workout.id)
        #expect(saved.exercises[0].current1RM == 105.0)
        #expect(saved.adjustments.contains { $0.trigger == .oneRMUpdate && $0.wasAccepted == true })

        // Future percentage-based session re-anchors to the new 1RM: 105 * 0.80 = 84 -> 85.0.
        #expect(session(sessionBId, in: saved)?.plannedExercises[0].targetWeight == 85.0)
        // Completed session keeps its historical prescription.
        #expect(session(sessionAId, in: saved)?.plannedExercises[0].targetWeight == 80.0)
    }

    // MARK: - 2: Idempotency

    @Test("handleSessionCompleted is idempotent — a retried completion changes nothing")
    func idempotentOnRetry() async {
        let plan = makePlan()
        let workout = makeBenchWorkout(weight: 90.0, reps: 5)
        let fixture = makeFixture(plan: plan, workouts: [workout])

        await fixture.vm.handleSessionCompleted(sessionId: sessionAId, planId: plan.id, workoutId: workout.id)
        let afterFirst = fixture.planRepo.plans[0]

        await fixture.vm.handleSessionCompleted(sessionId: sessionAId, planId: plan.id, workoutId: workout.id)
        let afterSecond = fixture.planRepo.plans[0]

        #expect(afterSecond.adjustments.count == afterFirst.adjustments.count)
        #expect(afterSecond.exercises[0].current1RM == afterFirst.exercises[0].current1RM)
        #expect(session(sessionAId, in: afterSecond)?.completedWorkoutId == workout.id)
    }

    // MARK: - 3: Fallback when workout missing

    @Test("handleSessionCompleted falls back to markSessionCompleted when the workout is not found")
    func fallbackWhenWorkoutMissing() async {
        let plan = makePlan()
        let unknownWorkoutId = UUID()
        let fixture = makeFixture(plan: plan, workouts: [])

        await fixture.vm.handleSessionCompleted(sessionId: sessionAId, planId: plan.id, workoutId: unknownWorkoutId)

        let saved = fixture.planRepo.plans[0]
        // Completion is still recorded...
        #expect(session(sessionAId, in: saved)?.completedWorkoutId == unknownWorkoutId)
        // ...but no engine work happened.
        #expect(saved.exercises[0].current1RM == 100.0)
        #expect(saved.adjustments.isEmpty)
    }

    // MARK: - 4: acceptAdjustment

    @Test("acceptAdjustment sets wasAccepted, scales future weights, and persists")
    func acceptLoadDecrease() async {
        let pending = PlanAdjustment(
            adjustmentType: .loadDecrease,
            trigger: .performanceDecline,
            description: "Load decrease 10% for Bench Press",
            affectedExerciseIds: [benchLibId],
            newValues: ["decreasePercent": "10"]
        )
        let plan = makePlan(adjustments: [pending])
        let fixture = makeFixture(plan: plan)
        await fixture.vm.loadActivePlan()
        #expect(fixture.vm.pendingAdjustments.count == 1)

        await fixture.vm.acceptAdjustment(id: pending.id)

        let saved = fixture.planRepo.plans[0]
        #expect(saved.adjustments[0].wasAccepted == true)
        #expect(fixture.vm.pendingAdjustments.isEmpty)
        // 80 * 0.9 = 72 -> rounded to nearest 2.5 = 72.5, on both uncompleted sessions.
        #expect(session(sessionAId, in: saved)?.plannedExercises[0].targetWeight == 72.5)
        #expect(session(sessionBId, in: saved)?.plannedExercises[0].targetWeight == 72.5)
    }

    // MARK: - 5: dismissAdjustment

    @Test("dismissAdjustment sets wasAccepted=false without touching weights")
    func dismissLeavesWeightsAlone() async {
        let pending = PlanAdjustment(
            adjustmentType: .loadDecrease,
            trigger: .performanceDecline,
            description: "Load decrease 10% for Bench Press",
            affectedExerciseIds: [benchLibId],
            newValues: ["decreasePercent": "10"]
        )
        let plan = makePlan(adjustments: [pending])
        let fixture = makeFixture(plan: plan)
        await fixture.vm.loadActivePlan()

        await fixture.vm.dismissAdjustment(id: pending.id)

        let saved = fixture.planRepo.plans[0]
        #expect(saved.adjustments[0].wasAccepted == false)
        #expect(fixture.vm.pendingAdjustments.isEmpty)
        #expect(session(sessionBId, in: saved)?.plannedExercises[0].targetWeight == 80.0)
    }

    // MARK: - 6: Adviser proposal dedup

    @Test("adviser proposals duplicated within 14 days are not re-appended")
    func dedupesRecentProposals() async {
        let now = Date()
        // Beginner regression scenario: the completing workout + the previous one both miss
        // the 5-rep target (2 consecutive misses -> 5% loadDecrease proposal); the workout
        // before that hit the target, capping the streak at exactly 2.
        let completingWorkout = makeBenchWorkout(weight: 80.0, reps: 4, completedAt: now)
        let previousMiss = makeBenchWorkout(weight: 80.0, reps: 4, completedAt: now.addingTimeInterval(-2 * 86400))
        let olderHit = makeBenchWorkout(weight: 80.0, reps: 5, completedAt: now.addingTimeInterval(-4 * 86400))
        let workouts = [completingWorkout, previousMiss, olderHit]

        // Without a recent matching record, the proposal IS appended (positive control).
        let freshPlan = makePlan(trainingStatus: .beginner)
        let freshFixture = makeFixture(plan: freshPlan, workouts: workouts, withAdviser: true)
        await freshFixture.vm.handleSessionCompleted(
            sessionId: sessionAId, planId: freshPlan.id, workoutId: completingWorkout.id
        )
        let freshSaved = freshFixture.planRepo.plans[0]
        let freshMatches = freshSaved.adjustments.filter {
            $0.adjustmentType == .loadDecrease && $0.trigger == .performanceDecline
        }
        #expect(freshMatches.count == 1)
        #expect(freshMatches.first?.wasAccepted == nil)

        // With a matching record from 3 days ago (even a dismissed one), it is deduped.
        let recentRecord = PlanAdjustment(
            adjustmentType: .loadDecrease,
            trigger: .performanceDecline,
            description: "Load decrease 5% for Bench Press",
            affectedExerciseIds: [benchLibId],
            newValues: ["decreasePercent": "5"],
            appliedAt: now.addingTimeInterval(-3 * 86400),
            wasAccepted: false
        )
        let seededPlan = makePlan(trainingStatus: .beginner, adjustments: [recentRecord])
        let seededFixture = makeFixture(plan: seededPlan, workouts: workouts, withAdviser: true)
        await seededFixture.vm.handleSessionCompleted(
            sessionId: sessionAId, planId: seededPlan.id, workoutId: completingWorkout.id
        )
        let seededSaved = seededFixture.planRepo.plans[0]
        let seededMatches = seededSaved.adjustments.filter {
            $0.adjustmentType == .loadDecrease && $0.trigger == .performanceDecline
        }
        #expect(seededMatches.count == 1, "Only the pre-existing record should remain")
        #expect(seededMatches.first?.id == recentRecord.id)
    }
}

// MARK: - Stubs

private final class PipelineStubExerciseRepository: ExerciseRepository, @unchecked Sendable {
    func fetchAll() async throws -> [Exercise] { [] }
    func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise] { [] }
    func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise] { [] }
    func search(name: String) async throws -> [Exercise] { [] }
    func save(_ exercise: Exercise) async throws -> Exercise { exercise }
    func delete(_ exercise: Exercise) async throws {}
}

private final class PipelineStubTemplateRepository: TemplateRepository, @unchecked Sendable {
    func fetchAll() async throws -> [WorkoutTemplate] { [] }
    func save(_ template: WorkoutTemplate) async throws -> WorkoutTemplate { template }
    func delete(_ template: WorkoutTemplate) async throws {}
    func incrementUsage(_ templateId: UUID) async throws {}
}
#endif
