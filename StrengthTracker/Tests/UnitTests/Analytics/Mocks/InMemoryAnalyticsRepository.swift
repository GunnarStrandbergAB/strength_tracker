import Foundation
@testable import StrengthTrackerShared

@MainActor
final class InMemoryAnalyticsRepository: AnalyticsRepository {
    private var storage: [UUID: WorkoutVector] = [:] // keyed by workoutId

    func storeVector(_ vector: WorkoutVector) async throws {
        storage[vector.workoutId] = vector
    }

    func fetchVector(for workoutId: UUID) async throws -> WorkoutVector? {
        storage[workoutId]
    }

    func fetchAllVectors() async throws -> [WorkoutVector] {
        Array(storage.values).sorted { $0.createdAt > $1.createdAt }
    }

    func fetchVectorsByDateRange(_ start: Date, _ end: Date) async throws -> [WorkoutVector] {
        try await fetchAllVectors().filter { $0.createdAt >= start && $0.createdAt <= end }
    }

    func deleteVector(for workoutId: UUID) async throws {
        storage.removeValue(forKey: workoutId)
    }
}
