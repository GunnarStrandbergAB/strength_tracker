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
            // Update template scalar fields
            existingEntity.name = template.name
            existingEntity.notes = template.notes
            existingEntity.sortOrder = template.sortOrder
            existingEntity.lastUsedAt = template.lastUsedAt
            existingEntity.timesUsed = template.timesUsed

            // Build lookup of existing exercise entities by ID
            let existingExercises = Dictionary(
                uniqueKeysWithValues: existingEntity.exercises.map { ($0.id, $0) }
            )
            let domainExerciseIds = Set(template.exercises.map { $0.id })

            // Delete exercises no longer in the template
            for (id, exerciseEntity) in existingExercises where !domainExerciseIds.contains(id) {
                modelContext.delete(exerciseEntity)
            }

            // Update existing or create new exercise entities
            var updatedExercises: [TemplateExerciseEntity] = []
            for domainExercise in template.exercises {
                if let existing = existingExercises[domainExercise.id] {
                    TemplateExerciseMapper.updateEntity(existing, from: domainExercise)
                    existing.template = existingEntity
                    updatedExercises.append(existing)
                } else {
                    let newExercise = TemplateExerciseMapper.toEntity(domainExercise)
                    newExercise.template = existingEntity
                    modelContext.insert(newExercise)
                    updatedExercises.append(newExercise)
                }
            }
            existingEntity.exercises = updatedExercises
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
