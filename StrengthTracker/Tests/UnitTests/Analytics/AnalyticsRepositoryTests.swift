import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AnalyticsRepository")
@MainActor
struct AnalyticsRepositoryTests {

    // MARK: - Helpers

    private func makeRepository() -> InMemoryAnalyticsRepository {
        InMemoryAnalyticsRepository()
    }

    private func makeVector(
        workoutId: UUID = UUID(),
        createdAt: Date = Date(),
        dimensions: [Double]? = nil
    ) -> WorkoutVector {
        let dims = dimensions ?? [
            0.65, 0.45, 0.33, 0.20, 0.40, 0.50,
            0.30, 0.25, 0.15, 0.10, 0.12, 0.08,
            0.60, 0.70, 0.05, -0.10, 0.20, 0.75,
        ]
        return WorkoutVector(
            id: UUID(),
            workoutId: workoutId,
            dimensions: dims,
            createdAt: createdAt
        )
    }

    // MARK: - storeVector

    @Test("storeVector persists a vector that can be fetched")
    func storeAndFetch() async throws {
        let repo = makeRepository()
        let workoutId = UUID()
        let vector = makeVector(workoutId: workoutId)

        try await repo.storeVector(vector)

        let fetched = try await repo.fetchVector(for: workoutId)
        #expect(fetched != nil)
        #expect(fetched?.workoutId == workoutId)
        #expect(fetched?.dimensions.count == 18)
    }

    @Test("storeVector upserts when workoutId already exists")
    func storeUpserts() async throws {
        let repo = makeRepository()
        let workoutId = UUID()

        let vector1 = makeVector(workoutId: workoutId, dimensions: [
            0.1, 0.1, 0.1, 0.1, 0.1, 0.1,
            0.1, 0.1, 0.1, 0.1, 0.1, 0.1,
            0.1, 0.1, 0.1, 0.1, 0.1, 0.1,
        ])
        try await repo.storeVector(vector1)

        let vector2 = makeVector(workoutId: workoutId, dimensions: [
            0.9, 0.9, 0.9, 0.9, 0.9, 0.9,
            0.9, 0.9, 0.9, 0.9, 0.9, 0.9,
            0.9, 0.9, 0.9, 0.9, 0.9, 0.9,
        ])
        try await repo.storeVector(vector2)

        let all = try await repo.fetchAllVectors()
        #expect(all.count == 1)
        #expect(all[0].dimensions[0] == 0.9)
    }

    // MARK: - fetchVector

    @Test("fetchVector returns nil for non-existent workoutId")
    func fetchNonExistent() async throws {
        let repo = makeRepository()
        let result = try await repo.fetchVector(for: UUID())
        #expect(result == nil)
    }

    // MARK: - fetchAllVectors

    @Test("fetchAllVectors returns empty when no vectors stored")
    func fetchAllEmpty() async throws {
        let repo = makeRepository()
        let result = try await repo.fetchAllVectors()
        #expect(result.isEmpty)
    }

    @Test("fetchAllVectors returns all stored vectors sorted by createdAt descending")
    func fetchAllSorted() async throws {
        let repo = makeRepository()
        let now = Date()

        let v1 = makeVector(createdAt: now.addingTimeInterval(-3600))
        let v2 = makeVector(createdAt: now.addingTimeInterval(-1800))
        let v3 = makeVector(createdAt: now)

        try await repo.storeVector(v1)
        try await repo.storeVector(v2)
        try await repo.storeVector(v3)

        let result = try await repo.fetchAllVectors()
        #expect(result.count == 3)
        // Most recent first
        #expect(result[0].createdAt >= result[1].createdAt)
        #expect(result[1].createdAt >= result[2].createdAt)
    }

    // MARK: - fetchVectorsByDateRange

    @Test("fetchVectorsByDateRange filters correctly")
    func fetchByDateRange() async throws {
        let repo = makeRepository()
        let now = Date()

        let today = makeVector(createdAt: now)
        let yesterday = makeVector(createdAt: now.addingTimeInterval(-86400))
        let lastWeek = makeVector(createdAt: now.addingTimeInterval(-604800))

        try await repo.storeVector(today)
        try await repo.storeVector(yesterday)
        try await repo.storeVector(lastWeek)

        let start = now.addingTimeInterval(-90000) // ~25 hours ago
        let result = try await repo.fetchVectorsByDateRange(start, now)
        #expect(result.count == 2)
    }

    @Test("fetchVectorsByDateRange returns empty when no vectors in range")
    func fetchByDateRangeEmpty() async throws {
        let repo = makeRepository()
        let now = Date()

        let lastWeek = makeVector(createdAt: now.addingTimeInterval(-604800))
        try await repo.storeVector(lastWeek)

        let start = now.addingTimeInterval(-3600)
        let result = try await repo.fetchVectorsByDateRange(start, now)
        #expect(result.isEmpty)
    }

    // MARK: - deleteVector

    @Test("deleteVector removes vector for workoutId")
    func deleteRemoves() async throws {
        let repo = makeRepository()
        let workoutId = UUID()
        let vector = makeVector(workoutId: workoutId)

        try await repo.storeVector(vector)
        try await repo.deleteVector(for: workoutId)

        let result = try await repo.fetchVector(for: workoutId)
        #expect(result == nil)
    }

    @Test("deleteVector for non-existent workoutId does not throw")
    func deleteNonExistent() async throws {
        let repo = makeRepository()
        try await repo.deleteVector(for: UUID()) // Should not throw
    }

    @Test("deleteVector only removes the targeted vector")
    func deleteOnlyTarget() async throws {
        let repo = makeRepository()
        let id1 = UUID()
        let id2 = UUID()

        try await repo.storeVector(makeVector(workoutId: id1))
        try await repo.storeVector(makeVector(workoutId: id2))

        try await repo.deleteVector(for: id1)

        let all = try await repo.fetchAllVectors()
        #expect(all.count == 1)
        #expect(all[0].workoutId == id2)
    }
}
