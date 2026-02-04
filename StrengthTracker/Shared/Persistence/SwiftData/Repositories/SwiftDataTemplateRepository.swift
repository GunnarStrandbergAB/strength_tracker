#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
final class SwiftDataTemplateRepository: TemplateRepository, Sendable {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [WorkoutTemplate] {
        let descriptor = FetchDescriptor<WorkoutTemplateEntity>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { TemplateMapper.toDomain($0) }
    }

    func save(_ template: WorkoutTemplate) async throws -> WorkoutTemplate {
        let descriptor = FetchDescriptor<WorkoutTemplateEntity>(
            predicate: #Predicate { entity in
                entity.id == template.id
            }
        )

        if let existingEntity = try modelContext.fetch(descriptor).first {
            TemplateMapper.updateEntity(existingEntity, from: template)
        } else {
            let newEntity = TemplateMapper.toEntity(template)
            modelContext.insert(newEntity)
        }

        try modelContext.save()
        return template
    }

    func delete(_ template: WorkoutTemplate) async throws {
        let descriptor = FetchDescriptor<WorkoutTemplateEntity>(
            predicate: #Predicate { entity in
                entity.id == template.id
            }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }

    func incrementUsage(_ templateId: UUID) async throws {
        let descriptor = FetchDescriptor<WorkoutTemplateEntity>(
            predicate: #Predicate { entity in
                entity.id == templateId
            }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            entity.timesUsed += 1
            entity.lastUsedAt = Date()
            try modelContext.save()
        }
    }
}
#endif
