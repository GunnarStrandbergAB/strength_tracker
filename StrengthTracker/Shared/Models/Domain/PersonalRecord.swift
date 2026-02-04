import Foundation

struct PersonalRecord: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var exerciseId: UUID
    var recordType: RecordType
    var value: Double
    var setId: UUID?
    var achievedAt: Date
}
