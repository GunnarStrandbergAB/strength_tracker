import Foundation
@testable import StrengthTrackerShared

@MainActor
final class InMemoryPersonalRecordRepository: PersonalRecordRepository {
    private var storage: [UUID: PersonalRecord] = [:]

    func fetchForExercise(_ exerciseId: UUID) async throws -> [PersonalRecord] {
        storage.values.filter { $0.exerciseId == exerciseId }
    }

    func save(_ record: PersonalRecord) async throws -> PersonalRecord {
        storage[record.id] = record
        return record
    }

    func deleteForExercise(_ exerciseId: UUID) async throws {
        storage = storage.filter { $0.value.exerciseId != exerciseId }
    }

    func fetchAll() async throws -> [PersonalRecord] {
        Array(storage.values)
    }

    func deleteForSet(_ setId: UUID) async throws {
        storage = storage.filter { $0.value.setId != setId }
    }

    func replace(records: [PersonalRecord], forExercise exerciseId: UUID, keepingManual: Bool) async throws {
        storage = storage.filter { $0.value.exerciseId != exerciseId || (keepingManual && $0.value.setId == nil) }
        for record in records { storage[record.id] = record }
    }
}
