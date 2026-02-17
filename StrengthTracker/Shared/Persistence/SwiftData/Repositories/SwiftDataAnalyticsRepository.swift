#if canImport(SwiftData)
import SwiftData
import Foundation

/// Manages WorkoutVectorEntity only. Uses WorkoutVectorMapper for entity<->domain conversion.
/// Workout queries are handled by WorkoutRepository (DDD: single-entity repository).
@MainActor
public final class SwiftDataAnalyticsRepository: AnalyticsRepository, Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Vector CRUD

    public func storeVector(_ vector: WorkoutVector) async throws {
        let workoutId = vector.workoutId
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            WorkoutVectorMapper.updateEntity(existing, from: vector)
        } else {
            let entity = WorkoutVectorMapper.toEntity(
                vector,
                totalVolume: 0,
                workoutDate: vector.createdAt,
                primaryMuscleGroups: []
            )
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    public func fetchVector(for workoutId: UUID) async throws -> WorkoutVector? {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )

        guard let entity = try modelContext.fetch(descriptor).first else {
            return nil
        }

        return WorkoutVectorMapper.toDomain(entity)
    }

    public func fetchAllVectors() async throws -> [WorkoutVector] {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { WorkoutVectorMapper.toDomain($0) }
    }

    public func fetchVectorsByDateRange(_ start: Date, _ end: Date) async throws -> [WorkoutVector] {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { entity in
                entity.workoutDate >= start && entity.workoutDate <= end
            },
            sortBy: [SortDescriptor(\.workoutDate, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { WorkoutVectorMapper.toDomain($0) }
    }

    public func deleteVector(for workoutId: UUID) async throws {
        let descriptor = FetchDescriptor<WorkoutVectorEntity>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }
}
#endif
