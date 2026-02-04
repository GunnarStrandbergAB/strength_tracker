#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
final class SwiftDataPersonalRecordRepository: PersonalRecordRepository, Sendable {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchForExercise(_ exerciseId: UUID) async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecordEntity>(
            predicate: #Predicate { entity in
                entity.exerciseId == exerciseId
            },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { PersonalRecordMapper.toDomain($0) }
    }

    func save(_ record: PersonalRecord) async throws -> PersonalRecord {
        let descriptor = FetchDescriptor<PersonalRecordEntity>(
            predicate: #Predicate { entity in
                entity.id == record.id
            }
        )

        if let existingEntity = try modelContext.fetch(descriptor).first {
            PersonalRecordMapper.updateEntity(existingEntity, from: record)
        } else {
            let newEntity = PersonalRecordMapper.toEntity(record)
            modelContext.insert(newEntity)
        }

        try modelContext.save()
        return record
    }

    func deleteForExercise(_ exerciseId: UUID) async throws {
        let descriptor = FetchDescriptor<PersonalRecordEntity>(
            predicate: #Predicate { entity in
                entity.exerciseId == exerciseId
            }
        )

        let entities = try modelContext.fetch(descriptor)
        for entity in entities {
            modelContext.delete(entity)
        }
        try modelContext.save()
    }
}
#endif
