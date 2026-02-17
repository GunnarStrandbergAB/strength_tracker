import Foundation
@testable import StrengthTrackerShared

/// London School mock for ExerciseRepository that tracks all interactions.
@MainActor
final class MockExerciseRepository: ExerciseRepository {
    // MARK: - Storage

    var exercises: [UUID: Exercise] = [:]

    // MARK: - Interaction Tracking

    var fetchAllCallCount = 0
    var fetchByCategoryCallCount = 0
    var fetchByMuscleGroupCallCount = 0
    var searchCallCount = 0
    var saveCallCount = 0
    var deleteCallCount = 0

    var fetchByCategoryArguments: [ExerciseCategory] = []
    var fetchByMuscleGroupArguments: [MuscleGroup] = []
    var searchArguments: [String] = []

    // MARK: - Error Simulation

    var shouldThrowOnFetch = false
    var customError: Error?

    private var errorToThrow: Error {
        customError ?? MockExerciseRepositoryError.intentional
    }

    // MARK: - ExerciseRepository Protocol

    func fetchAll() async throws -> [Exercise] {
        fetchAllCallCount += 1
        if shouldThrowOnFetch { throw errorToThrow }
        return Array(exercises.values).sorted { $0.name < $1.name }
    }

    func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise] {
        fetchByCategoryCallCount += 1
        fetchByCategoryArguments.append(category)
        if shouldThrowOnFetch { throw errorToThrow }
        return exercises.values.filter { $0.category == category }.sorted { $0.name < $1.name }
    }

    func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise] {
        fetchByMuscleGroupCallCount += 1
        fetchByMuscleGroupArguments.append(muscleGroup)
        if shouldThrowOnFetch { throw errorToThrow }
        return exercises.values.filter { $0.primaryMuscleGroup == muscleGroup }.sorted { $0.name < $1.name }
    }

    func search(name: String) async throws -> [Exercise] {
        searchCallCount += 1
        searchArguments.append(name)
        if shouldThrowOnFetch { throw errorToThrow }
        guard !name.isEmpty else { return try await fetchAll() }
        let lowered = name.lowercased()
        return exercises.values.filter { $0.name.lowercased().contains(lowered) }.sorted { $0.name < $1.name }
    }

    func save(_ exercise: Exercise) async throws -> Exercise {
        saveCallCount += 1
        exercises[exercise.id] = exercise
        return exercise
    }

    func delete(_ exercise: Exercise) async throws {
        deleteCallCount += 1
        exercises.removeValue(forKey: exercise.id)
    }

    // MARK: - Test Helpers

    func seed(_ exerciseList: [Exercise]) {
        for e in exerciseList {
            exercises[e.id] = e
        }
    }

    func reset() {
        exercises.removeAll()
        fetchAllCallCount = 0
        fetchByCategoryCallCount = 0
        fetchByMuscleGroupCallCount = 0
        searchCallCount = 0
        saveCallCount = 0
        deleteCallCount = 0
        fetchByCategoryArguments.removeAll()
        fetchByMuscleGroupArguments.removeAll()
        searchArguments.removeAll()
        shouldThrowOnFetch = false
        customError = nil
    }
}

enum MockExerciseRepositoryError: Error {
    case intentional
}
