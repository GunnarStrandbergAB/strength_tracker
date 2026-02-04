import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("PersonalRecordRepository")
@MainActor
struct PersonalRecordRepositoryTests {

    private func makeRepository() -> InMemoryPersonalRecordRepository {
        InMemoryPersonalRecordRepository()
    }

    private func makeRecord(
        exerciseId: UUID = UUID(),
        recordType: RecordType = .maxWeight,
        value: Double = 100.0
    ) -> PersonalRecord {
        PersonalRecord(
            id: UUID(),
            exerciseId: exerciseId,
            recordType: recordType,
            value: value,
            setId: nil,
            achievedAt: Date()
        )
    }

    // MARK: - fetchForExercise

    @Test("fetchForExercise returns empty when no records")
    func fetchEmpty() async throws {
        let repo = makeRepository()
        let result = try await repo.fetchForExercise(UUID())
        #expect(result.isEmpty)
    }

    @Test("fetchForExercise returns all PR types for exercise")
    func fetchForExercise() async throws {
        let repo = makeRepository()
        let exerciseId = UUID()
        let otherExerciseId = UUID()

        let pr1 = makeRecord(exerciseId: exerciseId, recordType: .maxWeight, value: 100)
        let pr2 = makeRecord(exerciseId: exerciseId, recordType: .maxReps, value: 12)
        let pr3 = makeRecord(exerciseId: exerciseId, recordType: .estimatedOneRepMax, value: 130)
        let otherPr = makeRecord(exerciseId: otherExerciseId, recordType: .maxWeight, value: 50)

        _ = try await repo.save(pr1)
        _ = try await repo.save(pr2)
        _ = try await repo.save(pr3)
        _ = try await repo.save(otherPr)

        let result = try await repo.fetchForExercise(exerciseId)
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.exerciseId == exerciseId })
    }

    // MARK: - save

    @Test("save persists record")
    func savePersists() async throws {
        let repo = makeRepository()
        let record = makeRecord(value: 225.0)

        let saved = try await repo.save(record)
        #expect(saved.id == record.id)
        #expect(saved.value == 225.0)

        let result = try await repo.fetchForExercise(record.exerciseId)
        #expect(result.count == 1)
    }

    @Test("save overwrites existing record")
    func saveOverwrites() async throws {
        let repo = makeRepository()
        var record = makeRecord(value: 100.0)
        _ = try await repo.save(record)

        record.value = 120.0
        _ = try await repo.save(record)

        let result = try await repo.fetchForExercise(record.exerciseId)
        #expect(result.count == 1)
        #expect(result[0].value == 120.0)
    }

    // MARK: - deleteForExercise

    @Test("deleteForExercise removes all PRs for exercise")
    func deleteForExercise() async throws {
        let repo = makeRepository()
        let exerciseId = UUID()
        let otherId = UUID()

        _ = try await repo.save(makeRecord(exerciseId: exerciseId, recordType: .maxWeight))
        _ = try await repo.save(makeRecord(exerciseId: exerciseId, recordType: .maxReps))
        _ = try await repo.save(makeRecord(exerciseId: otherId, recordType: .maxWeight))

        try await repo.deleteForExercise(exerciseId)

        let deleted = try await repo.fetchForExercise(exerciseId)
        #expect(deleted.isEmpty)

        let kept = try await repo.fetchForExercise(otherId)
        #expect(kept.count == 1)
    }

    @Test("deleteForExercise with no records does not throw")
    func deleteNonExistent() async throws {
        let repo = makeRepository()
        try await repo.deleteForExercise(UUID())
    }
}
