import Foundation

@MainActor
public protocol ExerciseRepository: Sendable {
    func fetchAll() async throws -> [Exercise]
    func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise]
    func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise]
    func search(name: String) async throws -> [Exercise]
    func save(_ exercise: Exercise) async throws -> Exercise
    func delete(_ exercise: Exercise) async throws
}
