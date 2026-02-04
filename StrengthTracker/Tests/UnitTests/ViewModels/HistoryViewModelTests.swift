import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("HistoryViewModel")
@MainActor
struct HistoryViewModelTests {

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

    private func makeSet(weight: Double = 100, reps: Int = 10, isCompleted: Bool = true) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: 1,
            setType: .normal,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: isCompleted,
            isPersonalRecord: false,
            completedAt: isCompleted ? Date() : nil
        )
    }

    private func makeWorkout(
        name: String = "Push Day",
        startedAt: Date = Date(),
        completedAt: Date? = Date(),
        exercises: [WorkoutExercise] = []
    ) -> Workout {
        Workout(
            id: UUID(),
            name: name,
            startedAt: startedAt,
            completedAt: completedAt,
            notes: nil,
            templateId: nil,
            exercises: exercises
        )
    }

    private func makeViewModel() -> (HistoryViewModel, InMemoryWorkoutRepository) {
        let repo = InMemoryWorkoutRepository()
        let vm = HistoryViewModel(workoutRepository: repo)
        return (vm, repo)
    }

    // MARK: - loadHistory

    @Test("Loads completed workouts excluding active ones")
    func loadHistory() async throws {
        let (vm, repo) = makeViewModel()
        let now = Date()
        let w1 = makeWorkout(name: "Old", startedAt: now.addingTimeInterval(-7200), completedAt: now.addingTimeInterval(-3600))
        let w2 = makeWorkout(name: "New", startedAt: now.addingTimeInterval(-1800), completedAt: now)
        let active = makeWorkout(name: "Active", completedAt: nil)

        _ = try await repo.save(w1)
        _ = try await repo.save(w2)
        _ = try await repo.save(active)

        await vm.loadHistory()

        #expect(vm.workouts.count == 2)
        #expect(vm.workouts.allSatisfy { $0.completedAt != nil })
        #expect(vm.isLoading == false)
    }

    @Test("Empty history returns empty array")
    func emptyHistory() async {
        let (vm, _) = makeViewModel()
        await vm.loadHistory()
        #expect(vm.workouts.isEmpty)
    }

    // MARK: - selectWorkout

    @Test("selectWorkout sets selectedWorkout")
    func selectWorkout() async throws {
        let (vm, repo) = makeViewModel()
        let workout = makeWorkout()
        _ = try await repo.save(workout)

        await vm.loadHistory()
        vm.selectWorkout(vm.workouts[0])

        #expect(vm.selectedWorkout != nil)
        #expect(vm.selectedWorkout?.id == workout.id)
    }

    // MARK: - exerciseProgression

    @Test("exerciseProgression returns weight/reps over time sorted by date")
    func exerciseProgression() async throws {
        let (vm, repo) = makeViewModel()
        let exercise = makeExercise()
        let now = Date()

        let set1 = makeSet(weight: 100, reps: 10)
        let set2 = makeSet(weight: 110, reps: 8)

        let we1 = WorkoutExercise(id: UUID(), exercise: exercise, order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: [set1])
        let we2 = WorkoutExercise(id: UUID(), exercise: exercise, order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: [set2])

        let w1 = makeWorkout(startedAt: now.addingTimeInterval(-86400), completedAt: now.addingTimeInterval(-82800), exercises: [we1])
        let w2 = makeWorkout(startedAt: now, completedAt: now.addingTimeInterval(3600), exercises: [we2])

        _ = try await repo.save(w1)
        _ = try await repo.save(w2)

        await vm.loadHistory()

        let progression = vm.exerciseProgression(for: exercise.id)
        #expect(progression.count == 2)
        #expect(progression[0].weight == 100)
        #expect(progression[1].weight == 110)
    }

    @Test("exerciseProgression excludes incomplete sets")
    func progressionExcludesIncomplete() async throws {
        let (vm, repo) = makeViewModel()
        let exercise = makeExercise()

        let completedSet = makeSet(weight: 100, reps: 10, isCompleted: true)
        let incompleteSet = makeSet(weight: 50, reps: 5, isCompleted: false)

        let we = WorkoutExercise(id: UUID(), exercise: exercise, order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: [completedSet, incompleteSet])
        let workout = makeWorkout(exercises: [we])

        _ = try await repo.save(workout)
        await vm.loadHistory()

        let progression = vm.exerciseProgression(for: exercise.id)
        #expect(progression.count == 1)
        #expect(progression[0].weight == 100)
    }

    @Test("exerciseProgression for unknown exercise returns empty")
    func progressionUnknownExercise() async {
        let (vm, _) = makeViewModel()
        await vm.loadHistory()
        let progression = vm.exerciseProgression(for: UUID())
        #expect(progression.isEmpty)
    }
}
