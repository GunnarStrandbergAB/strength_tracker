#if canImport(SwiftData)
import Foundation

public enum ExerciseMapper {
    /// Converts an ExerciseEntity (SwiftData) to an Exercise (domain model)
    public static func toDomain(_ entity: ExerciseEntity) -> Exercise {
        Exercise(
            id: entity.id,
            name: entity.name,
            primaryMuscleGroup: MuscleGroup(rawValue: entity.primaryMuscleGroup) ?? .other,
            secondaryMuscleGroups: decodeSecondaryMuscleGroups(entity.secondaryMuscleGroups),
            category: ExerciseCategory(rawValue: entity.category) ?? .other,
            exerciseType: ExerciseType(rawValue: entity.exerciseType) ?? .weightedReps,
            instructions: entity.instructions,
            isCustom: entity.isCustom,
            isArchived: entity.isArchived,
            bodyweightFactor: entity.bodyweightFactor,
            equipmentBrand: entity.equipmentBrand,
            loadingType: entity.loadingType.flatMap { LoadingType(rawValue: $0) }
        )
    }

    /// Converts an Exercise (domain model) to an ExerciseEntity (SwiftData)
    public static func toEntity(_ domain: Exercise) -> ExerciseEntity {
        ExerciseEntity(
            id: domain.id,
            name: domain.name,
            primaryMuscleGroup: domain.primaryMuscleGroup.rawValue,
            secondaryMuscleGroups: encodeSecondaryMuscleGroups(domain.secondaryMuscleGroups),
            category: domain.category.rawValue,
            exerciseType: domain.exerciseType.rawValue,
            instructions: domain.instructions,
            isCustom: domain.isCustom,
            isArchived: domain.isArchived,
            bodyweightFactor: domain.bodyweightFactor,
            equipmentBrand: domain.equipmentBrand,
            loadingType: domain.loadingType?.rawValue
        )
    }

    /// Updates an existing ExerciseEntity with values from an Exercise domain model
    public static func updateEntity(_ entity: ExerciseEntity, from domain: Exercise) {
        entity.name = domain.name
        entity.primaryMuscleGroup = domain.primaryMuscleGroup.rawValue
        entity.secondaryMuscleGroups = encodeSecondaryMuscleGroups(domain.secondaryMuscleGroups)
        entity.category = domain.category.rawValue
        entity.exerciseType = domain.exerciseType.rawValue
        entity.instructions = domain.instructions
        entity.isCustom = domain.isCustom
        entity.isArchived = domain.isArchived
        entity.bodyweightFactor = domain.bodyweightFactor
        entity.equipmentBrand = domain.equipmentBrand
        entity.loadingType = domain.loadingType?.rawValue
    }

    // MARK: - Private Helpers

    private static func encodeSecondaryMuscleGroups(_ groups: [MuscleGroup]) -> [String] {
        groups.map { $0.rawValue }
    }

    private static func decodeSecondaryMuscleGroups(_ encoded: [String]) -> [MuscleGroup] {
        encoded.compactMap { MuscleGroup(rawValue: $0) }
    }
}
#endif
