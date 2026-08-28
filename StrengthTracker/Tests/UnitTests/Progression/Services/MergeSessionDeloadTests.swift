#if canImport(SwiftData)
import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("mergeSessionIntoTemplate deload behavior")
struct MergeSessionDeloadTests {

    // MARK: - Helpers

    private func makeExercise(id: UUID = UUID(), name: String) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeTemplateExercise(exercise: Exercise, order: Int, sets: Int = 4, reps: Int = 10, weight: Double = 60.0) -> TemplateExercise {
        let setTargets = (0..<sets).map { i in
            TemplateSetTarget(order: i, targetReps: reps, targetWeight: weight)
        }
        return TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            targetSets: sets,
            targetReps: reps,
            targetWeight: weight,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil,
            setTargets: setTargets,
            isWarmUp: false
        )
    }

    @MainActor
    private func makeDummyVM() -> ProgressionPlanViewModel {
        // mergeSessionIntoTemplate is pure — repos are never called
        let workoutRepo = StubWorkoutRepository()
        return ProgressionPlanViewModel(
            progressionPlanRepository: StubProgressionPlanRepository(),
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: workoutRepo),
            programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: workoutRepo),
            exerciseRepository: StubExerciseRepository(),
            templateRepository: StubTemplateRepository()
        )
    }

    // MARK: - Tests

    @Test("Deload session halves unmatched template exercises")
    @MainActor
    func testDeloadSession_halvesUnmatchedExercises() {
        let squatId = UUID()
        let squat = makeExercise(id: squatId, name: "Squat")
        let lateralRaise = makeExercise(name: "Lateral Raise")
        let tricepPushdown = makeExercise(name: "Tricep Pushdown")

        let template = WorkoutTemplate(
            id: UUID(),
            name: "Push Day",
            notes: nil,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                makeTemplateExercise(exercise: squat, order: 0, sets: 4, reps: 5, weight: 100),
                makeTemplateExercise(exercise: lateralRaise, order: 1, sets: 4, reps: 12, weight: 10),
                makeTemplateExercise(exercise: tricepPushdown, order: 2, sets: 3, reps: 15, weight: 25),
            ]
        )

        let session = PlannedSession(
            sessionLabel: "Deload - Monday",
            plannedExercises: [
                PlannedExerciseSet(
                    planExerciseId: UUID(),
                    exerciseId: squatId,
                    exerciseName: "Squat",
                    sets: 2,
                    targetReps: 8,
                    targetWeight: 50,
                    percentageOf1RM: 0.50,
                    restSeconds: 120
                )
            ],
            isDeload: true
        )

        let vm = makeDummyVM()
        let result = vm.mergeSessionIntoTemplate(session: session, template: template, exercises: [squat, lateralRaise, tricepPushdown])

        // Squat: matched by plan -> gets plan prescription (2x8@50)
        let mergedSquat = result.exercises.first { $0.exercise.id == squatId }!
        #expect(mergedSquat.targetSets == 2)
        #expect(mergedSquat.targetReps == 8)
        #expect(mergedSquat.targetWeight == 50)

        // Lateral Raise: unmatched + deload -> halved sets (4/2=2), halved weight (10*0.5=5)
        let mergedLateral = result.exercises.first { $0.exercise.id == lateralRaise.id }!
        #expect(mergedLateral.targetSets == 2, "Lateral sets should be halved from 4 to 2")
        #expect(mergedLateral.targetWeight == 5.0, "Lateral weight should be halved from 10 to 5")
        #expect(mergedLateral.targetReps == 12, "Reps should be unchanged")
        #expect(mergedLateral.setTargets.isEmpty, "Per-set targets should be cleared")

        // Tricep Pushdown: unmatched + deload -> halved sets (max(2, 3/2)=2), halved weight (25*0.5=12.5)
        let mergedTricep = result.exercises.first { $0.exercise.id == tricepPushdown.id }!
        #expect(mergedTricep.targetSets == 2, "Tricep sets should be halved from 3 to 2 (min 2)")
        #expect(mergedTricep.targetWeight == 12.5, "Tricep weight should be halved from 25 to 12.5")
        #expect(mergedTricep.setTargets.isEmpty, "Per-set targets should be cleared")
    }

    @Test("Non-deload session keeps unmatched template exercises unchanged")
    @MainActor
    func testNonDeloadSession_keepsUnmatchedExercisesUnchanged() {
        let squatId = UUID()
        let squat = makeExercise(id: squatId, name: "Squat")
        let lateralRaise = makeExercise(name: "Lateral Raise")

        let template = WorkoutTemplate(
            id: UUID(),
            name: "Push Day",
            notes: nil,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                makeTemplateExercise(exercise: squat, order: 0, sets: 4, reps: 5, weight: 100),
                makeTemplateExercise(exercise: lateralRaise, order: 1, sets: 4, reps: 12, weight: 10),
            ]
        )

        let session = PlannedSession(
            sessionLabel: "Monday - Strength",
            plannedExercises: [
                PlannedExerciseSet(
                    planExerciseId: UUID(),
                    exerciseId: squatId,
                    exerciseName: "Squat",
                    sets: 5,
                    targetReps: 3,
                    targetWeight: 110,
                    percentageOf1RM: 0.85,
                    restSeconds: 180
                )
            ],
            isDeload: false
        )

        let vm = makeDummyVM()
        let result = vm.mergeSessionIntoTemplate(session: session, template: template, exercises: [squat, lateralRaise])

        // Lateral Raise: unmatched, non-deload -> unchanged
        let mergedLateral = result.exercises.first { $0.exercise.id == lateralRaise.id }!
        #expect(mergedLateral.targetSets == 4, "Sets should be unchanged")
        #expect(mergedLateral.targetWeight == 10, "Weight should be unchanged")
        #expect(mergedLateral.targetReps == 12, "Reps should be unchanged")
        #expect(mergedLateral.setTargets.count == 4, "Per-set targets should be preserved")
    }

    @Test("Ambiguous name fallback is disabled — same-named variants never cross-apply targets")
    @MainActor
    func testAmbiguousNameFallbackDisabled() {
        // Template's "Hip Thrust" (own id) vs TWO planned "Hip Thrust" variants
        // with different ids — the name fallback must not pick either.
        let templateHipThrust = makeExercise(name: "Hip Thrust")
        let template = WorkoutTemplate(
            id: UUID(), name: "Glutes", notes: nil, sortOrder: 0,
            lastUsedAt: nil, timesUsed: 0,
            exercises: [makeTemplateExercise(exercise: templateHipThrust, order: 0, sets: 4, reps: 10, weight: 60)]
        )

        let session = PlannedSession(
            sessionLabel: "Monday",
            plannedExercises: [
                PlannedExerciseSet(
                    planExerciseId: UUID(), exerciseId: UUID(), exerciseName: "Hip Thrust",
                    sets: 5, targetReps: 5, targetWeight: 120, percentageOf1RM: 0.75, restSeconds: 120
                ),
                PlannedExerciseSet(
                    planExerciseId: UUID(), exerciseId: UUID(), exerciseName: "Hip Thrust",
                    sets: 3, targetReps: 12, targetWeight: 45, percentageOf1RM: 0.75, restSeconds: 90
                )
            ],
            isDeload: false
        )

        let vm = makeDummyVM()
        let result = vm.mergeSessionIntoTemplate(session: session, template: template, exercises: [templateHipThrust])

        // Template row keeps its own targets — neither variant's prescription applied
        let merged = result.exercises.first { $0.exercise.id == templateHipThrust.id }!
        #expect(merged.targetSets == 4)
        #expect(merged.targetReps == 10)
        #expect(merged.targetWeight == 60)
    }

    @Test("Uniquely named fallback still applies plan targets on id mismatch")
    @MainActor
    func testUniqueNameFallbackStillWorks() {
        let templateSquat = makeExercise(name: "Squat")
        let template = WorkoutTemplate(
            id: UUID(), name: "Legs", notes: nil, sortOrder: 0,
            lastUsedAt: nil, timesUsed: 0,
            exercises: [makeTemplateExercise(exercise: templateSquat, order: 0, sets: 4, reps: 10, weight: 80)]
        )

        let session = PlannedSession(
            sessionLabel: "Monday",
            plannedExercises: [
                PlannedExerciseSet(
                    planExerciseId: UUID(), exerciseId: UUID(),  // id differs from template's
                    exerciseName: "Squat",
                    sets: 5, targetReps: 3, targetWeight: 110, percentageOf1RM: 0.75, restSeconds: 180
                )
            ],
            isDeload: false
        )

        let vm = makeDummyVM()
        let result = vm.mergeSessionIntoTemplate(session: session, template: template, exercises: [templateSquat])

        let merged = result.exercises.first { $0.exercise.id == templateSquat.id }!
        #expect(merged.targetSets == 5)
        #expect(merged.targetReps == 3)
        #expect(merged.targetWeight == 110)
    }

    @Test("Deload with nil weight keeps nil (bodyweight exercises)")
    @MainActor
    func testDeloadSession_nilWeightStaysNil() {
        let pullUp = makeExercise(name: "Pull Up")

        let templateExercise = TemplateExercise(
            id: UUID(),
            exercise: pullUp,
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            targetSets: 4,
            targetReps: 10,
            targetWeight: nil,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil,
            setTargets: [],
            isWarmUp: false
        )

        let template = WorkoutTemplate(
            id: UUID(),
            name: "Pull Day",
            notes: nil,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [templateExercise]
        )

        let session = PlannedSession(
            sessionLabel: "Deload",
            plannedExercises: [],
            isDeload: true
        )

        let vm = makeDummyVM()
        let result = vm.mergeSessionIntoTemplate(session: session, template: template, exercises: [pullUp])

        let merged = result.exercises[0]
        #expect(merged.targetSets == 2, "Sets should be halved from 4 to 2")
        #expect(merged.targetWeight == nil, "Nil weight should stay nil for bodyweight exercises")
    }

    @Test("TemplateExercise.deloaded() rounds weight to nearest 2.5")
    func testDeloaded_roundsWeight() {
        let exercise = makeExercise(name: "DB Curl")
        let te = TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 60,
            targetSets: 4,
            targetReps: 12,
            targetWeight: 17.5,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil,
            setTargets: [],
            isWarmUp: false
        )

        let deloaded = te.deloaded()
        // 17.5 * 0.5 = 8.75 -> rounded to nearest 2.5 = 10.0
        #expect(deloaded.targetWeight == 10.0, "17.5 * 0.5 = 8.75 should round to 10.0")
        #expect(deloaded.targetSets == 2, "4 / 2 = 2")
    }

    @Test("TemplateExercise.deloaded() enforces minimum 2 sets")
    func testDeloaded_minimumSets() {
        let exercise = makeExercise(name: "Curl")
        let te = TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 60,
            targetSets: 3,
            targetReps: 10,
            targetWeight: 20,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil,
            setTargets: [],
            isWarmUp: false
        )

        let deloaded = te.deloaded()
        // 3 / 2 = 1, but min is 2
        #expect(deloaded.targetSets == 2, "min(2, 3/2) should be 2")
    }
}

// MARK: - Lightweight stubs (never called by mergeSessionIntoTemplate)

private final class StubProgressionPlanRepository: ProgressionPlanRepository, @unchecked Sendable {
    func fetchAll() async throws -> [ProgressionPlan] { [] }
    func fetchActive() async throws -> ProgressionPlan? { nil }
    func fetch(id: UUID) async throws -> ProgressionPlan? { nil }
    func save(_ plan: ProgressionPlan) async throws {}
    func delete(_ plan: ProgressionPlan) async throws {}
    func updateStatus(_ planId: UUID, status: PlanStatus) async throws {}
    func addAdjustment(_ adjustment: PlanAdjustment, toPlan planId: UUID) async throws {}
    func updateExercise(_ exercise: PlanExercise, inPlan planId: UUID) async throws {}
    func updateBlock(_ block: TrainingBlock, inPlan planId: UUID) async throws {}
    func markSessionCompleted(_ sessionId: UUID, workoutId: UUID, inPlan planId: UUID) async throws {}
}

private final class StubExerciseRepository: ExerciseRepository, @unchecked Sendable {
    func fetchAll() async throws -> [Exercise] { [] }
    func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise] { [] }
    func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise] { [] }
    func search(name: String) async throws -> [Exercise] { [] }
    func save(_ exercise: Exercise) async throws -> Exercise { exercise }
    func delete(_ exercise: Exercise) async throws {}
}

private final class StubTemplateRepository: TemplateRepository, @unchecked Sendable {
    func fetchAll() async throws -> [WorkoutTemplate] { [] }
    func save(_ template: WorkoutTemplate) async throws -> WorkoutTemplate { template }
    func delete(_ template: WorkoutTemplate) async throws {}
    func incrementUsage(_ templateId: UUID) async throws {}
}

private final class StubWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    func fetchAll() async throws -> [Workout] { [] }
    func fetchActive() async throws -> Workout? { nil }
    func fetchByDateRange(_ start: Date, _ end: Date) async throws -> [Workout] { [] }
    func save(_ workout: Workout) async throws -> Workout { workout }
    func complete(_ workoutId: UUID) async throws {}
    func delete(_ workout: Workout) async throws {}
    func deleteAllIncomplete() async throws {}
}
#endif
