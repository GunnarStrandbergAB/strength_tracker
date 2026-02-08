import Foundation

@MainActor
public protocol PersonalRecordRepository: Sendable {
    func fetchForExercise(_ exerciseId: UUID) async throws -> [PersonalRecord]
    func save(_ record: PersonalRecord) async throws -> PersonalRecord
    func deleteForExercise(_ exerciseId: UUID) async throws
}
