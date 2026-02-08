import Foundation

public struct PersonalRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var exerciseId: UUID
    public var recordType: RecordType
    public var value: Double
    public var setId: UUID?
    public var achievedAt: Date

    public init(id: UUID, exerciseId: UUID, recordType: RecordType, value: Double, setId: UUID?, achievedAt: Date) {
        self.id = id
        self.exerciseId = exerciseId
        self.recordType = recordType
        self.value = value
        self.setId = setId
        self.achievedAt = achievedAt
    }
}
