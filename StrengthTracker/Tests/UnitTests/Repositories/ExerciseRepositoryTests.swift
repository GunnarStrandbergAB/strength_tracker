import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("ExerciseRepository")
@MainActor
struct ExerciseRepositoryTests {

    // MARK: - Helpers

    private func makeRepository() -> InMemoryExerciseRepository {
        InMemoryExerciseRepository()
    }

    private func makeExercise(
        name: String = "Bench Press",
        primaryMuscleGroup: MuscleGroup = .chest,
        secondaryMuscleGroups: [MuscleGroup] = [.triceps, .shoulders],
        category: ExerciseCategory = .barbell,
        exerciseType: ExerciseType = .weightedReps
    ) -> Exercise {
        Exercise(
            id: UUID(),
            name: name,
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: secondaryMuscleGroups,
            category: category,
            exerciseType: exerciseType,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    // MARK: - fetchAll

    @Test("fetchAll returns empty array when no exercises")
    func fetchAllEmpty() async throws {
        let repo = makeRepository()
        let result = try await repo.fetchAll()
        #expect(result.isEmpty)
    }

    @Test("fetchAll returns exercises sorted by name")
    func fetchAllSorted() async throws {
        let repo = makeRepository()
        let squat = makeExercise(name: "Squat")
        let bench = makeExercise(name: "Bench Press")
        let deadlift = makeExercise(name: "Deadlift")

        _ = try await repo.save(squat)
        _ = try await repo.save(bench)
        _ = try await repo.save(deadlift)

        let result = try await repo.fetchAll()
        #expect(result.count == 3)
        #expect(result[0].name == "Bench Press")
        #expect(result[1].name == "Deadlift")
        #expect(result[2].name == "Squat")
    }

    // MARK: - fetchByCategory

    @Test("fetchByCategory filters correctly")
    func fetchByCategory() async throws {
        let repo = makeRepository()
        let barbell = makeExercise(name: "Bench Press", category: .barbell)
        let dumbbell = makeExercise(name: "DB Curl", category: .dumbbell)
        let barbell2 = makeExercise(name: "Squat", category: .barbell)

        _ = try await repo.save(barbell)
        _ = try await repo.save(dumbbell)
        _ = try await repo.save(barbell2)

        let result = try await repo.fetchByCategory(.barbell)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.category == .barbell })
    }

    @Test("fetchByCategory returns empty for no matches")
    func fetchByCategoryEmpty() async throws {
        let repo = makeRepository()
        _ = try await repo.save(makeExercise(category: .barbell))

        let result = try await repo.fetchByCategory(.cable)
        #expect(result.isEmpty)
    }

    // MARK: - fetchByMuscleGroup

    @Test("fetchByMuscleGroup filters by primary muscle group")
    func fetchByMuscleGroup() async throws {
        let repo = makeRepository()
        let chest1 = makeExercise(name: "Bench Press", primaryMuscleGroup: .chest)
        let back1 = makeExercise(name: "Row", primaryMuscleGroup: .back)
        let chest2 = makeExercise(name: "Fly", primaryMuscleGroup: .chest)

        _ = try await repo.save(chest1)
        _ = try await repo.save(back1)
        _ = try await repo.save(chest2)

        let result = try await repo.fetchByMuscleGroup(.chest)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.primaryMuscleGroup == .chest })
    }

    // MARK: - search

    @Test("search matches case-insensitive partial name")
    func searchCaseInsensitive() async throws {
        let repo = makeRepository()
        _ = try await repo.save(makeExercise(name: "Bench Press"))
        _ = try await repo.save(makeExercise(name: "Incline Bench"))
        _ = try await repo.save(makeExercise(name: "Squat"))

        let result = try await repo.search(name: "bench")
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.name.lowercased().contains("bench") })
    }

    @Test("search returns empty for no matches")
    func searchNoMatch() async throws {
        let repo = makeRepository()
        _ = try await repo.save(makeExercise(name: "Bench Press"))

        let result = try await repo.search(name: "deadlift")
        #expect(result.isEmpty)
    }

    @Test("search with empty string returns all")
    func searchEmptyString() async throws {
        let repo = makeRepository()
        _ = try await repo.save(makeExercise(name: "Bench"))
        _ = try await repo.save(makeExercise(name: "Squat"))

        let result = try await repo.search(name: "")
        #expect(result.count == 2)
    }

    // MARK: - save

    @Test("save persists and returns exercise")
    func savePersists() async throws {
        let repo = makeRepository()
        let exercise = makeExercise(name: "Bench Press")

        let saved = try await repo.save(exercise)
        #expect(saved.id == exercise.id)
        #expect(saved.name == "Bench Press")

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].id == exercise.id)
    }

    @Test("save overwrites existing exercise with same ID")
    func saveOverwrites() async throws {
        let repo = makeRepository()
        var exercise = makeExercise(name: "Bench Press")
        _ = try await repo.save(exercise)

        exercise.name = "Flat Bench Press"
        _ = try await repo.save(exercise)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].name == "Flat Bench Press")
    }

    // MARK: - delete

    @Test("delete removes exercise from subsequent fetches")
    func deleteRemoves() async throws {
        let repo = makeRepository()
        let exercise = makeExercise(name: "Bench Press")
        _ = try await repo.save(exercise)

        try await repo.delete(exercise)

        let all = try await repo.fetchAll()
        #expect(all.isEmpty)
    }

    @Test("delete non-existent exercise does not throw")
    func deleteNonExistent() async throws {
        let repo = makeRepository()
        let exercise = makeExercise()
        try await repo.delete(exercise) // Should not throw
    }
}
