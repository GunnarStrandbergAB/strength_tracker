import Foundation

/// Maps between WorkoutVectorEntity (persistence) and WorkoutVector (domain).
/// Handles Float32<->Double conversion at the repository boundary (ADR-002).
public enum WorkoutVectorMapper {

    // MARK: - Float32<->Double Conversion (ADR-002)

    /// Convert [Double] domain values to Float32 Data for storage (72 bytes)
    public static func doublesToData(_ dimensions: [Double]) -> Data {
        let floats = dimensions.map { Float($0) }
        return floats.withUnsafeBytes { Data($0) }
    }

    /// Convert Float32 Data back to [Double] domain values
    public static func dataToDoubles(_ data: Data) -> [Double] {
        let floatCount = data.count / MemoryLayout<Float>.size
        let floats = data.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self).prefix(floatCount))
        }
        return floats.map { Double($0) }
    }

    #if canImport(SwiftData)
    // MARK: - Entity -> Domain

    /// Converts a WorkoutVectorEntity (SwiftData) to a WorkoutVector (domain model)
    public static func toDomain(_ entity: WorkoutVectorEntity) -> WorkoutVector {
        WorkoutVector(
            id: entity.id,
            workoutId: entity.workoutId,
            dimensions: dataToDoubles(entity.vectorData),
            magnitude: entity.magnitude,
            createdAt: entity.createdAt
        )
    }

    // MARK: - Domain -> Entity

    /// Converts a WorkoutVector (domain model) to a WorkoutVectorEntity (SwiftData)
    public static func toEntity(
        _ domain: WorkoutVector,
        totalVolume: Double,
        workoutDate: Date,
        primaryMuscleGroups: [String]
    ) -> WorkoutVectorEntity {
        WorkoutVectorEntity(
            id: domain.id,
            workoutId: domain.workoutId,
            createdAt: domain.createdAt,
            vectorData: doublesToData(domain.dimensions),
            magnitude: domain.magnitude,
            totalVolume: totalVolume,
            workoutDate: workoutDate,
            primaryMuscleGroups: primaryMuscleGroups
        )
    }

    /// Updates an existing WorkoutVectorEntity with values from a WorkoutVector domain model
    public static func updateEntity(
        _ entity: WorkoutVectorEntity,
        from domain: WorkoutVector,
        totalVolume: Double,
        workoutDate: Date,
        primaryMuscleGroups: [String]
    ) {
        entity.vectorData = doublesToData(domain.dimensions)
        entity.magnitude = domain.magnitude
        entity.createdAt = domain.createdAt
        entity.totalVolume = totalVolume
        entity.workoutDate = workoutDate
        entity.primaryMuscleGroups = primaryMuscleGroups
    }
    #endif
}
