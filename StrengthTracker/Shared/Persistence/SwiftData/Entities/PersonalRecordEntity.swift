#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
final class PersonalRecordEntity {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var recordType: String
    var value: Double
    var setId: UUID?
    var achievedAt: Date

    init(
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
