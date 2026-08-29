#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
public final class SwiftDataExerciseRepository: ExerciseRepository, Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchAll() async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    public func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.category == category.rawValue
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    public func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.primaryMuscleGroup == muscleGroup.rawValue
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    public func search(name: String) async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.name.localizedStandardContains(name)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    public func save(_ exercise: Exercise) async throws -> Exercise {
        // Hoisted capture — #Predicate keypathing into a captured struct is a
        // known SwiftData footgun.
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.id == exerciseID
            }
        )

        if let existingEntity = try modelContext.fetch(descriptor).first {
            ExerciseMapper.updateEntity(existingEntity, from: exercise)
        } else {
            let newEntity = ExerciseMapper.toEntity(exercise)
            modelContext.insert(newEntity)
        }

        try modelContext.save()
        return exercise
    }

    public func delete(_ exercise: Exercise) async throws {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.id == exerciseID
            }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}
#endif
