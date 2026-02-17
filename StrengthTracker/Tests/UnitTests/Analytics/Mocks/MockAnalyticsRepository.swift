import Foundation
@testable import StrengthTrackerShared

/// London School mock for AnalyticsRepository that tracks all interactions.
/// Verifies both behavior (call counts, arguments) and state (stored vectors).
@MainActor
final class MockAnalyticsRepository: AnalyticsRepository {
    // MARK: - Storage

    var storedVectors: [UUID: WorkoutVector] = [:] // keyed by workoutId

    // MARK: - Interaction Tracking

    var storeVectorCallCount = 0
    var storeVectorArguments: [WorkoutVector] = []

    var fetchVectorCallCount = 0
    var fetchVectorArguments: [UUID] = []

    var fetchAllVectorsCallCount = 0

    var fetchVectorsByDateRangeCallCount = 0
    var fetchVectorsByDateRangeArguments: [(start: Date, end: Date)] = []

    var deleteVectorCallCount = 0
    var deleteVectorArguments: [UUID] = []

    // MARK: - Error Simulation

    var shouldThrowOnStore = false
    var shouldThrowOnFetch = false
    var shouldThrowOnDelete = false
    var customError: Error?

    private var errorToThrow: Error {
        customError ?? MockAnalyticsError.intentional
    }

    // MARK: - AnalyticsRepository Protocol

    func storeVector(_ vector: WorkoutVector) async throws {
        storeVectorCallCount += 1
        storeVectorArguments.append(vector)
        if shouldThrowOnStore { throw errorToThrow }
        storedVectors[vector.workoutId] = vector
    }

    func fetchVector(for workoutId: UUID) async throws -> WorkoutVector? {
        fetchVectorCallCount += 1
        fetchVectorArguments.append(workoutId)
        if shouldThrowOnFetch { throw errorToThrow }
        return storedVectors[workoutId]
    }

    func fetchAllVectors() async throws -> [WorkoutVector] {
        fetchAllVectorsCallCount += 1
        if shouldThrowOnFetch { throw errorToThrow }
        return Array(storedVectors.values).sorted { $0.createdAt > $1.createdAt }
    }

    func fetchVectorsByDateRange(_ start: Date, _ end: Date) async throws -> [WorkoutVector] {
        fetchVectorsByDateRangeCallCount += 1
        fetchVectorsByDateRangeArguments.append((start: start, end: end))
        if shouldThrowOnFetch { throw errorToThrow }
        return Array(storedVectors.values).filter {
            $0.createdAt >= start && $0.createdAt <= end
        }
    }

    func deleteVector(for workoutId: UUID) async throws {
        deleteVectorCallCount += 1
        deleteVectorArguments.append(workoutId)
        if shouldThrowOnDelete { throw errorToThrow }
        storedVectors.removeValue(forKey: workoutId)
    }

    // MARK: - Test Helpers

    func reset() {
        storedVectors.removeAll()
        storeVectorCallCount = 0
        storeVectorArguments.removeAll()
        fetchVectorCallCount = 0
        fetchVectorArguments.removeAll()
        fetchAllVectorsCallCount = 0
        fetchVectorsByDateRangeCallCount = 0
        fetchVectorsByDateRangeArguments.removeAll()
        deleteVectorCallCount = 0
        deleteVectorArguments.removeAll()
        shouldThrowOnStore = false
        shouldThrowOnFetch = false
        shouldThrowOnDelete = false
        customError = nil
    }
}

enum MockAnalyticsError: Error, Equatable {
    case intentional
}
