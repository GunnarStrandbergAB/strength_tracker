import Foundation
@testable import StrengthTrackerShared

@MainActor
final class InMemoryWorkoutRepository: WorkoutRepository {
    private var storage: [UUID: Workout] = [:]

    func fetchAll() async throws -> [Workout] {
        Array(storage.values).sorted { $0.startedAt > $1.startedAt }
    }

    func fetchActive() async throws -> Workout? {
        storage.values.first { $0.completedAt == nil }
    }

    func fetchByDateRange(_ start: Date, _ end: Date) async throws -> [Workout] {
        try await fetchAll().filter { $0.startedAt >= start && $0.startedAt <= end }
    }

    func save(_ workout: Workout) async throws -> Workout {
        storage[workout.id] = workout
        return workout
    }

    func complete(_ workoutId: UUID) async throws {
        guard var workout = storage[workoutId] else { return }
        workout.completedAt = Date()
        storage[workoutId] = workout
    }

    func delete(_ workout: Workout) async throws {
        storage.removeValue(forKey: workout.id)
    }
}
