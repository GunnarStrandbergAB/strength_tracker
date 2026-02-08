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

    // MARK: - totalVolume

    @Test("totalVolume computed correctly as sets are added")
    func totalVolume() async throws {
        let (vm, _, _) = makeViewModel()
        await vm.startWorkout(name: "Push Day")

        let exercise = makeExercise()
        vm.addExercise(exercise)

        try await vm.logSet(exerciseId: exercise.id, weight: 100, reps: 10) // 1000
        try await vm.logSet(exerciseId: exercise.id, weight: 100, reps: 8)  // 800

        #expect(vm.currentWorkout?.totalVolume == 1800)
    }
}
