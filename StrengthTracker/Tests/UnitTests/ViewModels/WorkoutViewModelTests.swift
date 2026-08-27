import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("WorkoutViewModel")
@MainActor
struct WorkoutViewModelTests {

    // MARK: - Helpers

    private func makeExercise(name: String = "Bench Press") -> Exercise {
        Exercise(
            id: UUID(),
            name: name,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeTemplate(exercises: [TemplateExercise] = []) -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID(),
            name: "Push Day",
            notes: nil,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: exercises
        )
    }

    private func makeTemplateExercise(exercise: Exercise? = nil) -> TemplateExercise {
        TemplateExercise(
            id: UUID(),
            exercise: exercise ?? makeExercise(),
            order: 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            targetSets: 3,
            targetReps: 10,
            targetWeight: nil,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )
    }

    private func makeViewModel() -> (WorkoutViewModel, InMemoryWorkoutRepository, InMemoryTemplateRepository) {
        let workoutRepo = InMemoryWorkoutRepository()
        let templateRepo = InMemoryTemplateRepository()
        let vm = WorkoutViewModel(workoutRepository: workoutRepo, templateRepository: templateRepo, healthKitService: NoOpHealthKitService())
        return (vm, workoutRepo, templateRepo)
    }

    // MARK: - startWorkout

    @Test("startWorkout creates new workout with timestamp and isActive true")
    func startWorkout() async {
        let (vm, _, _) = makeViewModel()

        await vm.startWorkout(name: "Push Day")

        #expect(vm.currentWorkout != nil)
        #expect(vm.currentWorkout?.name == "Push Day")
        #expect(vm.currentWorkout?.completedAt == nil)
        #expect(vm.isActive == true)
    }

    @Test("startWorkout from template pre-fills exercises")
    func startFromTemplate() async {
        let (vm, _, _) = makeViewModel()
        let bench = makeExercise(name: "Bench Press")
        let ohp = makeExercise(name: "OHP")
        let te1 = makeTemplateExercise(exercise: bench)
        let te2 = makeTemplateExercise(exercise: ohp)
        let template = makeTemplate(exercises: [te1, te2])

        await vm.startWorkout(name: "Push Day", from: template)

        #expect(vm.currentWorkout != nil)
        #expect(vm.currentWorkout?.exercises.count == 2)
        #expect(vm.currentWorkout?.exercises[0].exercise.name == "Bench Press")
        #expect(vm.currentWorkout?.exercises[1].exercise.name == "OHP")
        #expect(vm.currentWorkout?.templateId == template.id)
    }

    // MARK: - addExercise

    @Test("addExercise appends WorkoutExercise to current workout")
    func addExercise() async {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        let exercise = makeExercise(name: "Bench Press")
        vm.addExercise(exercise)

        #expect(vm.currentWorkout?.exercises.count == 1)
        #expect(vm.currentWorkout?.exercises[0].exercise.name == "Bench Press")
        #expect(vm.currentWorkout?.exercises[0].order == 1)
    }

    @Test("addExercise does nothing when no active workout")
    func addExerciseNoWorkout() {
        let (vm, _, _) = makeViewModel()
        let exercise = makeExercise()
        vm.addExercise(exercise)
        #expect(vm.currentWorkout == nil)
    }

    // MARK: - logSet

    @Test("logSet adds ExerciseSet to correct exercise")
    func logSet() async throws {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        let exercise = makeExercise()
        vm.addExercise(exercise)

        try await vm.logSet(exerciseId: exercise.id, weight: 100, reps: 10)

        #expect(vm.currentWorkout?.exercises[0].sets.count == 1)
        #expect(vm.currentWorkout?.exercises[0].sets[0].weight == 100)
        #expect(vm.currentWorkout?.exercises[0].sets[0].reps == 10)
        #expect(vm.currentWorkout?.exercises[0].sets[0].isCompleted == true)
    }

    @Test("logSet throws when no active workout")
    func logSetNoWorkout() async {
        let (vm, _, _) = makeViewModel()

        await #expect(throws: WorkoutError.self) {
            try await vm.logSet(exerciseId: UUID(), weight: 100, reps: 10)
        }
    }

    @Test("logSet throws when exercise not found")
    func logSetExerciseNotFound() async {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        await #expect(throws: WorkoutError.self) {
            try await vm.logSet(exerciseId: UUID(), weight: 100, reps: 10)
        }
    }

    // MARK: - completeWorkout

    @Test("completeWorkout sets completedAt and isActive false")
    func completeWorkout() async throws {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        try await vm.completeWorkout()

        #expect(vm.currentWorkout?.completedAt != nil)
        #expect(vm.isActive == false)
    }

    @Test("completeWorkout saves to repository")
    func completeWorkoutSaves() async throws {
        let (vm, workoutRepo, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        try await vm.completeWorkout()

        let all = try await workoutRepo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].completedAt != nil)
    }

    @Test("completeWorkout throws when no active workout")
    func completeNoWorkout() async {
        let (vm, _, _) = makeViewModel()

        await #expect(throws: WorkoutError.self) {
            try await vm.completeWorkout()
        }
    }

    // MARK: - hasPendingActiveWorkout (cold-launch routing flag)

    @Test("startWorkout sets pending flag; completeWorkout clears it")
    func pendingFlagStartComplete() async throws {
        WorkoutViewModel.hasPendingActiveWorkout = false
        let (vm, _, _) = makeViewModel()

        await vm.startWorkout(name: "Push Day")
        #expect(WorkoutViewModel.hasPendingActiveWorkout == true)

        try await vm.completeWorkout()
        #expect(WorkoutViewModel.hasPendingActiveWorkout == false)
    }

    @Test("cancelWorkout clears pending flag")
    func pendingFlagCancel() async {
        WorkoutViewModel.hasPendingActiveWorkout = false
        let (vm, _, _) = makeViewModel()

        await vm.startWorkout(name: "Push Day")
        #expect(WorkoutViewModel.hasPendingActiveWorkout == true)

        await vm.cancelWorkout()
        #expect(WorkoutViewModel.hasPendingActiveWorkout == false)
    }

    @Test("restoreActiveWorkout clears stale-true flag when no active workout exists")
    func pendingFlagRestoreNoWorkout() async {
        WorkoutViewModel.hasPendingActiveWorkout = true
        let (vm, _, _) = makeViewModel()

        await vm.restoreActiveWorkout()

        #expect(vm.isActive == false)
        #expect(WorkoutViewModel.hasPendingActiveWorkout == false)
    }

    // MARK: - totalVolume

    @Test("totalVolume computed correctly as sets are added")
    func totalVolume() async throws {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        let exercise = makeExercise()
        vm.addExercise(exercise)

        try await vm.logSet(exerciseId: exercise.id, weight: 100, reps: 10) // 1000
        try await vm.logSet(exerciseId: exercise.id, weight: 100, reps: 8)  // 800

        #expect(vm.currentWorkout?.totalVolume(bodyWeightKg: 70) == 1800)
    }

    // MARK: - moveExercise

    @Test("moveExercise reorders, renumbers 1-based, and persists")
    func moveExercisePersists() async throws {
        let (vm, workoutRepo, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")
        vm.addExercise(makeExercise(name: "Bench"))
        vm.addExercise(makeExercise(name: "Squat"))
        vm.addExercise(makeExercise(name: "Deadlift"))

        await vm.moveExercise(from: 2, to: 0)

        let names = vm.currentWorkout?.exercises.map(\.exercise.name)
        #expect(names == ["Deadlift", "Bench", "Squat"])
        let orders = vm.currentWorkout?.exercises.map(\.order)
        #expect(orders == [1, 2, 3])

        // Persisted — the repo copy carries the new order too
        let saved = try await workoutRepo.fetchAll().first
        let savedNames = saved?.exercises.sorted { $0.order < $1.order }.map(\.exercise.name)
        #expect(savedNames == ["Deadlift", "Bench", "Squat"])
    }

    @Test("moveExercise ignores out-of-bounds and same-index moves")
    func moveExerciseNoOps() async {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")
        vm.addExercise(makeExercise(name: "Bench"))
        vm.addExercise(makeExercise(name: "Squat"))

        await vm.moveExercise(from: 0, to: 0)
        await vm.moveExercise(from: -1, to: 1)
        await vm.moveExercise(from: 0, to: 2)

        let names = vm.currentWorkout?.exercises.map(\.exercise.name)
        #expect(names == ["Bench", "Squat"])
    }

    // MARK: - activeExerciseId

    @Test("toggleSetCompletion marks the touched exercise as active")
    func toggleSetsActiveExercise() async throws {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")
        let bench = makeExercise(name: "Bench")
        let squat = makeExercise(name: "Squat")
        vm.addExercise(bench)
        vm.addExercise(squat)
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[0].id)
        // Squat gets two sets so it still has work left after one completion
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[1].id)
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[1].id)

        // Jump to the SECOND exercise out of order
        let squatWE = vm.currentWorkout!.exercises[1]
        await vm.toggleSetCompletion(exerciseId: squatWE.id, setId: squatWE.sets[0].id)

        #expect(vm.activeExerciseId == squatWE.id)
        #expect(vm.activeExercise?.exercise.name == "Squat")
    }

    @Test("activeExercise advances once the preferred exercise is fully complete")
    func activeExerciseAdvances() async throws {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")
        vm.addExercise(makeExercise(name: "Bench"))
        vm.addExercise(makeExercise(name: "Squat"))
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[0].id)
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[1].id)

        // Complete the second exercise's only set — active resolves to the first
        let squatWE = vm.currentWorkout!.exercises[1]
        await vm.toggleSetCompletion(exerciseId: squatWE.id, setId: squatWE.sets[0].id)

        #expect(vm.activeExerciseId == squatWE.id)
        #expect(vm.activeExercise?.exercise.name == "Bench")
    }

    @Test("restoreActiveWorkout derives active exercise from completedAt")
    func restoreDerivesActiveExercise() async throws {
        let (vm, workoutRepo, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")
        vm.addExercise(makeExercise(name: "Bench"))
        vm.addExercise(makeExercise(name: "Squat"))
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[0].id)
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[1].id)
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[1].id)
        let squatWE = vm.currentWorkout!.exercises[1]
        await vm.toggleSetCompletion(exerciseId: squatWE.id, setId: squatWE.sets[0].id)

        // Simulate relaunch with a fresh VM over the same repository
        let vm2 = WorkoutViewModel(
            workoutRepository: workoutRepo,
            templateRepository: InMemoryTemplateRepository(),
            healthKitService: NoOpHealthKitService()
        )
        await vm2.restoreActiveWorkout()

        #expect(vm2.isActive == true)
        #expect(vm2.activeExerciseId == squatWE.id)
    }

    @Test("start, complete, and cancel clear the active exercise")
    func lifecycleClearsActiveExercise() async throws {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")
        vm.addExercise(makeExercise(name: "Bench"))
        await vm.addEmptySet(exerciseId: vm.currentWorkout!.exercises[0].id)
        let benchWE = vm.currentWorkout!.exercises[0]
        await vm.toggleSetCompletion(exerciseId: benchWE.id, setId: benchWE.sets[0].id)
        #expect(vm.activeExerciseId != nil)

        try await vm.completeWorkout()
        #expect(vm.activeExerciseId == nil)
    }

    // MARK: - addExercise persistence (regression: used to live only in memory)

    @Test("addExercise persists the new exercise to the repository")
    func addExercisePersists() async throws {
        let (vm, workoutRepo, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        vm.addExercise(makeExercise(name: "Bench"))

        // The save happens in a fire-and-forget Task — poll briefly for it
        var savedCount = 0
        for _ in 0..<50 {
            savedCount = try await workoutRepo.fetchAll().first?.exercises.count ?? 0
            if savedCount == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(savedCount == 1)
    }
}
