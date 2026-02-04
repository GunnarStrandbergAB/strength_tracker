#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
final class SwiftDataExerciseRepository: ExerciseRepository, Sendable {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.category == category.rawValue
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.primaryMuscleGroup == muscleGroup.rawValue
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    func search(name: String) async throws -> [Exercise] {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.name.localizedStandardContains(name)
            },
            sortBy: [SortDescriptor(\.name)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { ExerciseMapper.toDomain($0) }
    }

    func save(_ exercise: Exercise) async throws -> Exercise {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.id == exercise.id
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

    func delete(_ exercise: Exercise) async throws {
        let descriptor = FetchDescriptor<ExerciseEntity>(
            predicate: #Predicate { entity in
                entity.id == exercise.id
            }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}
#endif
