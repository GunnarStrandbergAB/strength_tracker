import Foundation

@MainActor
protocol WorkoutRepository: Sendable {
    func fetchAll() async throws -> [Workout]
    func fetchActive() async throws -> Workout?
    func fetchByDateRange(_ start: Date, _ end: Date) async throws -> [Workout]
    func save(_ workout: Workout) async throws -> Workout
    func complete(_ workoutId: UUID) async throws
    func delete(_ workout: Workout) async throws
}
