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

    /// Convenience: wraps exercise(s) into a single-set template for tests that used the old exercises: API.
    private func makeTemplateFrom(_ exercises: [Exercise], setsPerExercise: Int = 3) -> WorkoutTemplate {
        let templateExercises = exercises.enumerated().map { i, ex in
            TemplateExercise(
                id: UUID(), exercise: ex, order: i,
                supersetGroup: nil, notes: nil, restTimerSeconds: nil,
                targetSets: setsPerExercise, targetReps: 10, targetWeight: 80,
                targetDurationSeconds: nil, targetDistanceMeters: nil
            )
        }
        return WorkoutTemplate(
            id: UUID(), name: "Test", notes: nil, sortOrder: 0,
            lastUsedAt: nil, timesUsed: 0, exercises: templateExercises
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

        await vm.startWorkout(name: "Push", from: makeTemplateFrom(exercises))

        #expect(vm.activeWorkout != nil)
        #expect(vm.activeWorkout?.exercises.count == 2)
        #expect(vm.currentExerciseIndex == 0)
        #expect(vm.isActive == true)
    }

    // MARK: - logSet

    @Test("logSet records weight/reps for current exercise")
    func logSet() async throws {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", from: makeTemplateFrom([makeExercise()]))

        try await vm.logSet(weight: 100, reps: 10)

        // Template pre-populates 3 sets; logSet completes the first incomplete one
        #expect(vm.activeWorkout?.exercises[0].sets.count == 3)
        #expect(vm.activeWorkout?.exercises[0].sets[0].weight == 100)
        #expect(vm.activeWorkout?.exercises[0].sets[0].reps == 10)
        #expect(vm.activeWorkout?.exercises[0].sets[0].isCompleted == true)
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
        await vm.startWorkout(name: "Push", from: makeTemplateFrom([makeExercise(name: "A"), makeExercise(name: "B")]))

        #expect(vm.currentExerciseIndex == 0)
        vm.nextExercise()
        #expect(vm.currentExerciseIndex == 1)
    }

    @Test("nextExercise does not go past last exercise")
    func nextExerciseBounds() async {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", from: makeTemplateFrom([makeExercise()]))

        vm.nextExercise()
        #expect(vm.currentExerciseIndex == 0)
    }

    @Test("previousExercise goes back")
    func previousExercise() async {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", from: makeTemplateFrom([makeExercise(name: "A"), makeExercise(name: "B")]))

        vm.nextExercise()
        #expect(vm.currentExerciseIndex == 1)

        vm.previousExercise()
        #expect(vm.currentExerciseIndex == 0)
    }

    @Test("previousExercise does not go below 0")
    func previousExerciseBounds() async {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Push", from: makeTemplateFrom([makeExercise()]))

        vm.previousExercise()
        #expect(vm.currentExerciseIndex == 0)
    }

    // MARK: - completeWorkout

    @Test("completeWorkout marks complete and saves")
    func completeWorkout() async throws {
        let (vm, repo) = makeViewModel()
        await vm.startWorkout(name: "Push", from: makeTemplateFrom([makeExercise()]))

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

    // MARK: - Helpers (template)

    private func makeTemplate(exerciseCount: Int = 2, setsPerExercise: Int = 3) -> WorkoutTemplate {
        let exercises = (0..<exerciseCount).map { i in
            TemplateExercise(
                id: UUID(),
                exercise: makeExercise(name: "Exercise \(i + 1)"),
                order: i + 1,
                supersetGroup: nil,
                notes: nil,
                restTimerSeconds: nil,
                targetSets: setsPerExercise,
                targetReps: 10,
                targetWeight: 80,
                targetDurationSeconds: nil,
                targetDistanceMeters: nil
            )
        }
        return WorkoutTemplate(
            id: UUID(),
            name: "Test Template",
            notes: nil,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: exercises
        )
    }

    // MARK: - currentExercisePlannedSetsComplete

    @Test("plannedSetsComplete returns false for quick-start workout")
    func plannedSetsCompleteFalseForQuickStart() async throws {
        let (vm, _) = makeViewModel()
        await vm.startWorkout(name: "Quick", from: makeTemplateFrom([makeExercise()]))

        try await vm.logSet(weight: 80, reps: 10)

        #expect(vm.currentExercisePlannedSetsComplete == false)
    }

    @Test("plannedSetsComplete returns false when completed < planned")
    func plannedSetsCompleteIncomplete() async throws {
        let (vm, _) = makeViewModel()
        let template = makeTemplate(exerciseCount: 1, setsPerExercise: 3)
        await vm.startWorkout(name: "Template", from: template)

        // Complete 2 of 3 planned sets
        try await vm.logSet(weight: 80, reps: 10)
        vm.skipRestTimer()
        try await vm.logSet(weight: 80, reps: 10)
        vm.skipRestTimer()

        #expect(vm.currentExercisePlannedSetsComplete == false)
    }

    @Test("plannedSetsComplete returns true when completed == planned")
    func plannedSetsCompleteExact() async throws {
        let (vm, _) = makeViewModel()
        let template = makeTemplate(exerciseCount: 1, setsPerExercise: 3)
        await vm.startWorkout(name: "Template", from: template)

        // Complete all 3 planned sets
        for _ in 0..<3 {
            try await vm.logSet(weight: 80, reps: 10)
            vm.skipRestTimer()
        }

        #expect(vm.currentExercisePlannedSetsComplete == true)
    }

    @Test("plannedSetsComplete returns true when completed > planned (extra sets)")
    func plannedSetsCompleteExtra() async throws {
        let (vm, _) = makeViewModel()
        let template = makeTemplate(exerciseCount: 1, setsPerExercise: 2)
        await vm.startWorkout(name: "Template", from: template)

        // Complete 3 sets when only 2 planned
        for _ in 0..<3 {
            try await vm.logSet(weight: 80, reps: 10)
            vm.skipRestTimer()
        }

        #expect(vm.currentExercisePlannedSetsComplete == true)
    }

    // MARK: - isLastExercise

    @Test("isLastExercise returns false for first exercise with multiple exercises")
    func isLastExerciseFirstOfMany() async {
        let (vm, _) = makeViewModel()
        let template = makeTemplate(exerciseCount: 2)
        await vm.startWorkout(name: "Template", from: template)

        #expect(vm.isLastExercise == false)
    }

    @Test("isLastExercise returns true for last exercise")
    func isLastExerciseLast() async {
        let (vm, _) = makeViewModel()
        let template = makeTemplate(exerciseCount: 2)
        await vm.startWorkout(name: "Template", from: template)

        vm.nextExercise()
        #expect(vm.isLastExercise == true)
    }

    @Test("isLastExercise returns true for single-exercise workout")
    func isLastExerciseSingle() async {
        let (vm, _) = makeViewModel()
        let template = makeTemplate(exerciseCount: 1)
        await vm.startWorkout(name: "Template", from: template)

        #expect(vm.isLastExercise == true)
    }

    // MARK: - Offline-ready

    @Test("Works standalone without connection")
    func offlineReady() async {
        let (vm, _) = makeViewModel()
        let exercises = [makeExercise()]

        await vm.startWorkout(name: "Offline Push", from: makeTemplateFrom(exercises))

        #expect(vm.isActive == true)
        #expect(vm.activeWorkout != nil)
    }
}
