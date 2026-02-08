#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
public final class SwiftDataTemplateRepository: TemplateRepository, Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchAll() async throws -> [WorkoutTemplate] {
        let descriptor = FetchDescriptor<WorkoutTemplateEntity>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { TemplateMapper.toDomain($0) }
    }

    public func save(_ template: WorkoutTemplate) async throws -> WorkoutTemplate {
        let descriptor = FetchDescriptor<WorkoutTemplateEntity>(
            predicate: #Predicate { entity in
                entity.id == template.id
            }
        )

        if let existingEntity = try modelContext.fetch(descriptor).first {
            // Delete old exercise entities from context before replacing
            for exercise in existingEntity.exercises {
                modelContext.delete(exercise)
            }
            TemplateMapper.updateEntity(existingEntity, from: template)
        } else {
            let newEntity = TemplateMapper.toEntity(template)
            modelContext.insert(newEntity)
        }

        try modelContext.save()
        return template
    }

    public func delete(_ template: WorkoutTemplate) async throws {
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

    public func incrementUsage(_ templateId: UUID) async throws {
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
