import Foundation
@testable import StrengthTrackerShared

@MainActor
final class MockWorkoutRepositoryProgression: WorkoutRepository {
    var workouts: [Workout] = []

    func fetchAll() async throws -> [Workout] {
        workouts
    }

    func fetchActive() async throws -> Workout? {
        workouts.first { $0.isInProgress }
    }

    func fetchByDateRange(_ start: Date, _ end: Date) async throws -> [Workout] {
        workouts.filter { workout in
            guard let completed = workout.completedAt else { return false }
            return completed >= start && completed <= end
        }
    }

    func save(_ workout: Workout) async throws -> Workout {
        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = workout
        } else {
            workouts.append(workout)
        }
        return workout
    }

    func complete(_ workoutId: UUID) async throws {
        guard let index = workouts.firstIndex(where: { $0.id == workoutId }) else { return }
        var updated = workouts[index]
        // Create a new workout with completedAt set
        workouts[index] = Workout(
            id: updated.id,
            name: updated.name,
            startedAt: updated.startedAt,
            completedAt: Date(),
            notes: updated.notes,
            templateId: updated.templateId,
            exercises: updated.exercises
        )
    }

    func delete(_ workout: Workout) async throws {
        workouts.removeAll { $0.id == workout.id }
    }

    func deleteAllIncomplete() async throws {
        workouts.removeAll { $0.completedAt == nil }
    }
}
