import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("WorkoutRepository")
@MainActor
struct WorkoutRepositoryTests {

    // MARK: - Helpers

    private func makeRepository() -> InMemoryWorkoutRepository {
        InMemoryWorkoutRepository()
    }

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

    private func makeSet(weight: Double = 100, reps: Int = 10) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: 1,
            setType: .normal,
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

    private func makeWorkout(
        name: String = "Push Day",
        startedAt: Date = Date(),
        completedAt: Date? = nil,
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

    // MARK: - fetchAll

    @Test("fetchAll returns empty when no workouts")
    func fetchAllEmpty() async throws {
        let repo = makeRepository()
        let result = try await repo.fetchAll()
        #expect(result.isEmpty)
    }

    @Test("fetchAll returns workouts sorted by startedAt descending")
    func fetchAllSorted() async throws {
        let repo = makeRepository()
        let now = Date()
        let w1 = makeWorkout(name: "First", startedAt: now.addingTimeInterval(-3600))
        let w2 = makeWorkout(name: "Second", startedAt: now.addingTimeInterval(-1800))
        let w3 = makeWorkout(name: "Third", startedAt: now)

        _ = try await repo.save(w1)
        _ = try await repo.save(w2)
        _ = try await repo.save(w3)

        let result = try await repo.fetchAll()
        #expect(result.count == 3)
        #expect(result[0].name == "Third")
        #expect(result[1].name == "Second")
        #expect(result[2].name == "First")
    }

    // MARK: - fetchActive

    @Test("fetchActive returns in-progress workout")
    func fetchActiveReturns() async throws {
        let repo = makeRepository()
        let active = makeWorkout(name: "Active", completedAt: nil)
        let completed = makeWorkout(name: "Done", completedAt: Date())

        _ = try await repo.save(active)
        _ = try await repo.save(completed)

        let result = try await repo.fetchActive()
        #expect(result != nil)
        #expect(result?.name == "Active")
    }

    @Test("fetchActive returns nil when no active workout")
    func fetchActiveNil() async throws {
        let repo = makeRepository()
        let completed = makeWorkout(completedAt: Date())
        _ = try await repo.save(completed)

        let result = try await repo.fetchActive()
        #expect(result == nil)
    }

    // MARK: - fetchByDateRange

    @Test("fetchByDateRange filters correctly")
    func fetchByDateRange() async throws {
        let repo = makeRepository()
        let now = Date()
        let today = makeWorkout(name: "Today", startedAt: now)
        let yesterday = makeWorkout(name: "Yesterday", startedAt: now.addingTimeInterval(-86400))
        let lastWeek = makeWorkout(name: "Last Week", startedAt: now.addingTimeInterval(-604800))

        _ = try await repo.save(today)
        _ = try await repo.save(yesterday)
        _ = try await repo.save(lastWeek)

        let start = now.addingTimeInterval(-90000) // ~25 hours ago
        let result = try await repo.fetchByDateRange(start, now)
        #expect(result.count == 2)
    }

    // MARK: - save

    @Test("save persists workout with nested exercises and sets")
    func savePersists() async throws {
        let repo = makeRepository()
        let exercise = makeExercise()
        let set1 = makeSet(weight: 100, reps: 10)
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: [set1]
        )
        let workout = makeWorkout(exercises: [workoutExercise])

        let saved = try await repo.save(workout)
        #expect(saved.exercises.count == 1)
        #expect(saved.exercises[0].sets.count == 1)
        #expect(saved.exercises[0].sets[0].weight == 100)
    }

    @Test("save overwrites existing workout with same ID")
    func saveOverwrites() async throws {
        let repo = makeRepository()
        var workout = makeWorkout(name: "Push Day")
        _ = try await repo.save(workout)

        workout.name = "Heavy Push Day"
        _ = try await repo.save(workout)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].name == "Heavy Push Day")
    }

    // MARK: - complete

    @Test("complete sets completedAt on workout")
    func completeWorkout() async throws {
        let repo = makeRepository()
        let workout = makeWorkout(completedAt: nil)
        _ = try await repo.save(workout)

        #expect(workout.isInProgress)

        try await repo.complete(workout.id)

        let fetched = try await repo.fetchAll()
        #expect(fetched[0].completedAt != nil)
        #expect(!fetched[0].isInProgress)
    }

    @Test("complete non-existent workout does not throw")
    func completeNonExistent() async throws {
        let repo = makeRepository()
        try await repo.complete(UUID()) // Should not throw
    }

    // MARK: - delete

    @Test("delete removes workout")
    func deleteRemoves() async throws {
        let repo = makeRepository()
        let workout = makeWorkout()
        _ = try await repo.save(workout)

        try await repo.delete(workout)

        let all = try await repo.fetchAll()
        #expect(all.isEmpty)
    }

    @Test("delete non-existent workout does not throw")
    func deleteNonExistent() async throws {
        let repo = makeRepository()
        let workout = makeWorkout()
        try await repo.delete(workout) // Should not throw
    }
}
