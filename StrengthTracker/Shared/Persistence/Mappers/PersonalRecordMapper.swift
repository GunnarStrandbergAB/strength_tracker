#if canImport(SwiftData)
import Foundation

enum PersonalRecordMapper {
    /// Converts a PersonalRecordEntity (SwiftData) to a PersonalRecord (domain model)
    static func toDomain(_ entity: PersonalRecordEntity) -> PersonalRecord {
        PersonalRecord(
            id: entity.id,
            exerciseId: entity.exerciseId,
            recordType: RecordType(rawValue: entity.recordType) ?? .maxWeight,
            value: entity.value,
            setId: entity.setId,
            achievedAt: entity.achievedAt
        )
    }

    /// Converts a PersonalRecord (domain model) to a PersonalRecordEntity (SwiftData)
    static func toEntity(_ domain: PersonalRecord) -> PersonalRecordEntity {
        PersonalRecordEntity(
            id: domain.id,
            exerciseId: domain.exerciseId,
            recordType: domain.recordType.rawValue,
            value: domain.value,
            setId: domain.setId,
            achievedAt: domain.achievedAt
        )
    }

    /// Updates an existing PersonalRecordEntity with values from a PersonalRecord domain model
    static func updateEntity(_ entity: PersonalRecordEntity, from domain: PersonalRecord) {
        entity.exerciseId = domain.exerciseId
        entity.recordType = domain.recordType.rawValue
        entity.value = domain.value
        entity.setId = domain.setId
        entity.achievedAt = domain.achievedAt
    }
}
#endif
