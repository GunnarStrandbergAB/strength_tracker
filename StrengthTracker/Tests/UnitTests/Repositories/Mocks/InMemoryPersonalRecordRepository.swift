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
}
