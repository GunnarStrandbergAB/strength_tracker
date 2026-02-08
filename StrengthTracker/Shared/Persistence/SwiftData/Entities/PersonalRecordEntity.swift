#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class PersonalRecordEntity {
    @Attribute(.unique) public var id: UUID
    public var exerciseId: UUID
    public var recordType: String
    public var value: Double
    public var setId: UUID?
    public var achievedAt: Date

    public init(
        id: UUID,
        exerciseId: UUID,
        recordType: String,
        value: Double,
        setId: UUID? = nil,
        achievedAt: Date
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.recordType = recordType
        self.value = value
        self.setId = setId
        self.achievedAt = achievedAt
    }
}
#endif
