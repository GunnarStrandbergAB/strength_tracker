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

extension Array where Element == PersonalRecord {
    /// The best record per type: highest value wins; achievedAt breaks value ties
    /// (newest). Never pick by date alone — retro-logged records can carry a past
    /// achievedAt while holding the best value.
    public func bestPerType() -> [PersonalRecord] {
        var best: [RecordType: PersonalRecord] = [:]
        for record in self {
            if let existing = best[record.recordType] {
                if record.value > existing.value ||
                    (record.value == existing.value && record.achievedAt > existing.achievedAt) {
                    best[record.recordType] = record
                }
            } else {
                best[record.recordType] = record
            }
        }
        return Array(best.values)
    }
}
