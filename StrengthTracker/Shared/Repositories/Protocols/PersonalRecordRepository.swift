import Foundation

@MainActor
public protocol PersonalRecordRepository: Sendable {
    func fetchAll() async throws -> [PersonalRecord]
    func fetchForExercise(_ exerciseId: UUID) async throws -> [PersonalRecord]
    func save(_ record: PersonalRecord) async throws -> PersonalRecord
    func deleteForExercise(_ exerciseId: UUID) async throws
    func deleteForSet(_ setId: UUID) async throws
    /// Atomically replaces the automatic rows (`setId != nil`) of one exercise with
    /// `records`; manual rows (`setId == nil`) survive when `keepingManual`.
    func replace(records: [PersonalRecord], forExercise exerciseId: UUID, keepingManual: Bool) async throws
}
