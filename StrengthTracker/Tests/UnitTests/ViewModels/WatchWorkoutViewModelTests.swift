import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("WatchWorkoutViewModel")
@MainActor
struct WatchWorkoutViewModelTests {

    // MARK: - Helpers

    private func makeExercise(name: String = "Bench Press") -> Exercise {
        Exercise(
            id: UUID(),
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

    private func makeViewModel() -> (WatchWorkoutViewModel, InMemoryWorkoutRepository) {
        let repo = InMemoryWorkoutRepository()
        let vm = WatchWorkoutViewModel(workoutRepository: repo, healthKitService: NoOpHealthKitService(), connectivityManager: ConnectivityManager())
        return (vm, repo)
    }

    // MARK: - startWorkout

    @Test("Can start workout with exercises")
    func startWorkout() async {
        let (vm, _) = makeViewModel()
        let exercises = [makeExercise(name: "Bench"), makeExercise(name: "OHP")]

        await vm.startWorkout(name: "Push", exercises: exercises)

        #expect(vm.activeWorkout != nil)
        #expect(vm.activeWorkout?.exercises.count == 2)
        #expect(vm.currentExerciseIndex == 0)
        #expect(vm.isActive == true)
    }

    // MARK: - logSet

    @Test("logSet records weight/reps for current exercise")
    func logSet() async throws {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", exercises: [makeExercise()])

        try await vm.logSet(weight: 100, reps: 10)

        #expect(vm.activeWorkout?.exercises[0].sets.count == 1)
        #expect(vm.activeWorkout?.exercises[0].sets[0].weight == 100)
        #expect(vm.activeWorkout?.exercises[0].sets[0].reps == 10)
    }

    @Test("logSet throws when no active workout")
    func logSetNoWorkout() async {
        let (vm, _) = makeViewModel()

        await #expect(throws: WorkoutError.self) {
            try await vm.logSet(weight: 100, reps: 10)
        }
    }

    // MARK: - nextExercise / previousExercise

    @Test("nextExercise advances currentExerciseIndex")
    func nextExercise() async {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", exercises: [makeExercise(name: "A"), makeExercise(name: "B")])

        #expect(vm.currentExerciseIndex == 0)
        vm.nextExercise()
        #expect(vm.currentExerciseIndex == 1)
    }

    @Test("nextExercise does not go past last exercise")
    func nextExerciseBounds() async {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", exercises: [makeExercise()])

        vm.nextExercise()
        #expect(vm.currentExerciseIndex == 0)
    }

    @Test("previousExercise goes back")
    func previousExercise() async {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", exercises: [makeExercise(name: "A"), makeExercise(name: "B")])

        vm.nextExercise()
        #expect(vm.currentExerciseIndex == 1)

        vm.previousExercise()
        #expect(vm.currentExerciseIndex == 0)
    }

    @Test("previousExercise does not go below 0")
    func previousExerciseBounds() async {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", exercises: [makeExercise()])

        vm.previousExercise()
        #expect(vm.currentExerciseIndex == 0)
    }

    // MARK: - completeWorkout

    @Test("completeWorkout marks complete and saves")
    func completeWorkout() async throws {
        let (vm, repo) = makeViewModel()
        await vm.startWorkout(name: "Push", exercises: [makeExercise()])

        try await vm.logSet(weight: 100, reps: 10)
        try await vm.completeWorkout()

        #expect(vm.activeWorkout?.completedAt != nil)
        #expect(vm.isActive == false)

        let all = try await repo.fetchAll()
        #expect(all[0].completedAt != nil)
    }

    @Test("completeWorkout throws when no active workout")
    func completeNoWorkout() async {
        let (vm, _) = makeViewModel()

        await #expect(throws: WorkoutError.self) {
            try await vm.completeWorkout()
        }
    }

    // MARK: - Offline-ready

    @Test("Works standalone without connection")
    func offlineReady() async {
        let (vm, _) = makeViewModel()
        let exercises = [makeExercise()]

        await vm.startWorkout(name: "Offline Push", exercises: exercises)

        #expect(vm.isActive == true)
        #expect(vm.activeWorkout != nil)
    }
}
