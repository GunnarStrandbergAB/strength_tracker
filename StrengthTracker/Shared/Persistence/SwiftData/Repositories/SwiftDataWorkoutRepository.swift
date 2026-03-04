#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
public final class SwiftDataWorkoutRepository: WorkoutRepository, Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchAll() async throws -> [Workout] {
        let descriptor = FetchDescriptor<WorkoutEntity>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { WorkoutMapper.toDomain($0) }
    }

    public func fetchActive() async throws -> Workout? {
        let descriptor = FetchDescriptor<WorkoutEntity>(
            predicate: #Predicate { entity in
                entity.completedAt == nil
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        let entities = try modelContext.fetch(descriptor)
        return entities.first.map { WorkoutMapper.toDomain($0) }
    }

    public func fetchByDateRange(_ start: Date, _ end: Date) async throws -> [Workout] {
        let descriptor = FetchDescriptor<WorkoutEntity>(
            predicate: #Predicate { entity in
                entity.startedAt >= start && entity.startedAt <= end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let entities = try modelContext.fetch(descriptor)
        return entities.map { WorkoutMapper.toDomain($0) }
    }

    public func save(_ workout: Workout) async throws -> Workout {
        let descriptor = FetchDescriptor<WorkoutEntity>(
            predicate: #Predicate { entity in
                entity.id == workout.id
            }
        )

        if let existingEntity = try modelContext.fetch(descriptor).first {
            WorkoutMapper.updateEntity(existingEntity, from: workout, context: modelContext)
        } else {
            let newEntity = WorkoutMapper.toEntity(workout)
            modelContext.insert(newEntity)
        }

        try modelContext.save()
        return workout
    }

    public func complete(_ workoutId: UUID) async throws {
        let descriptor = FetchDescriptor<WorkoutEntity>(
            predicate: #Predicate { entity in
                entity.id == workoutId
            }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            entity.completedAt = Date()
            try modelContext.save()
        }
    }

    public func delete(_ workout: Workout) async throws {
        let descriptor = FetchDescriptor<WorkoutEntity>(
            predicate: #Predicate { entity in
                entity.id == workout.id
            }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}
#endif
