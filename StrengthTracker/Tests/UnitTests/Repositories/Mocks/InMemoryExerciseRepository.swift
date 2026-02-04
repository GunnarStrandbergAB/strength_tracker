import Foundation
@testable import StrengthTrackerShared

@MainActor
final class InMemoryExerciseRepository: ExerciseRepository {
    private var storage: [UUID: Exercise] = [:]

    func fetchAll() async throws -> [Exercise] {
        Array(storage.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise] {
        try await fetchAll().filter { $0.category == category }
    }

    func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise] {
        try await fetchAll().filter { $0.primaryMuscleGroup == muscleGroup }
    }

    func search(name: String) async throws -> [Exercise] {
        guard !name.isEmpty else { return try await fetchAll() }
        let lowered = name.lowercased()
        return try await fetchAll().filter { $0.name.lowercased().contains(lowered) }
    }

    func save(_ exercise: Exercise) async throws -> Exercise {
        storage[exercise.id] = exercise
        return exercise
    }

    func delete(_ exercise: Exercise) async throws {
        storage.removeValue(forKey: exercise.id)
    }
}
