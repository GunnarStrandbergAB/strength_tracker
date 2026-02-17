import Foundation
@testable import StrengthTrackerShared

/// London School mock for WorkoutRepository that tracks all interactions.
/// Provides in-memory storage with call-count verification.
@MainActor
final class MockWorkoutRepository: WorkoutRepository {
    // MARK: - Storage

    var workouts: [UUID: Workout] = [:]

    // MARK: - Interaction Tracking

    var fetchAllCallCount = 0
    var fetchActiveCallCount = 0
    var fetchByDateRangeCallCount = 0
    var saveCallCount = 0
    var completeCallCount = 0
    var deleteCallCount = 0

    var fetchByDateRangeArguments: [(start: Date, end: Date)] = []
    var saveArguments: [Workout] = []
    var completeArguments: [UUID] = []

    // MARK: - Error Simulation

    var shouldThrowOnFetchAll = false
    var shouldThrowOnSave = false
    var customError: Error?

    private var errorToThrow: Error {
        customError ?? MockWorkoutRepositoryError.intentional
    }

    // MARK: - WorkoutRepository Protocol

    func fetchAll() async throws -> [Workout] {
        fetchAllCallCount += 1
        if shouldThrowOnFetchAll { throw errorToThrow }
        return Array(workouts.values).sorted { $0.startedAt > $1.startedAt }
    }

    func fetchActive() async throws -> Workout? {
        fetchActiveCallCount += 1
        return workouts.values.first { $0.completedAt == nil }
    }

    func fetchByDateRange(_ start: Date, _ end: Date) async throws -> [Workout] {
        fetchByDateRangeCallCount += 1
        fetchByDateRangeArguments.append((start: start, end: end))
        return try await fetchAll().filter { $0.startedAt >= start && $0.startedAt <= end }
    }

    func save(_ workout: Workout) async throws -> Workout {
        saveCallCount += 1
        saveArguments.append(workout)
        if shouldThrowOnSave { throw errorToThrow }
        workouts[workout.id] = workout
        return workout
    }

    func complete(_ workoutId: UUID) async throws {
        completeCallCount += 1
        completeArguments.append(workoutId)
        guard var workout = workouts[workoutId] else { return }
        workout.completedAt = Date()
        workouts[workoutId] = workout
    }

    func delete(_ workout: Workout) async throws {
        deleteCallCount += 1
        workouts.removeValue(forKey: workout.id)
    }

    // MARK: - Test Helpers

    /// Seed multiple workouts into storage.
    func seed(_ workoutList: [Workout]) {
        for w in workoutList {
            workouts[w.id] = w
        }
    }

    func reset() {
        workouts.removeAll()
        fetchAllCallCount = 0
        fetchActiveCallCount = 0
        fetchByDateRangeCallCount = 0
        saveCallCount = 0
        completeCallCount = 0
        deleteCallCount = 0
        fetchByDateRangeArguments.removeAll()
        saveArguments.removeAll()
        completeArguments.removeAll()
        shouldThrowOnFetchAll = false
        shouldThrowOnSave = false
        customError = nil
    }
}

enum MockWorkoutRepositoryError: Error {
    case intentional
}
