#if canImport(SwiftData)
import Foundation

public enum TemplateMapper {
    /// Converts a WorkoutTemplateEntity (SwiftData) to a WorkoutTemplate (domain model)
    public static func toDomain(_ entity: WorkoutTemplateEntity) -> WorkoutTemplate {
        WorkoutTemplate(
            id: entity.id,
            name: entity.name,
            notes: entity.notes,
            sortOrder: entity.sortOrder,
            lastUsedAt: entity.lastUsedAt,
            timesUsed: entity.timesUsed,
            exercises: entity.exercises.sorted(by: { $0.order < $1.order }).map { TemplateExerciseMapper.toDomain($0) },
            isCustom: entity.isCustom
        )
    }

    /// Converts a WorkoutTemplate (domain model) to a WorkoutTemplateEntity (SwiftData)
    public static func toEntity(_ domain: WorkoutTemplate) -> WorkoutTemplateEntity {
        let entity = WorkoutTemplateEntity(
            id: domain.id,
            name: domain.name,
            notes: domain.notes,
            sortOrder: domain.sortOrder,
            lastUsedAt: domain.lastUsedAt,
            timesUsed: domain.timesUsed,
            isCustom: domain.isCustom
        )
        let exerciseEntities = domain.exercises.map { TemplateExerciseMapper.toEntity($0) }
        for ex in exerciseEntities {
            ex.template = entity
        }
        entity.exercises = exerciseEntities
        return entity
    }

}

public enum TemplateExerciseMapper {
    /// Converts a TemplateExerciseEntity to a TemplateExercise (domain model)
    public static func toDomain(_ entity: TemplateExerciseEntity) -> TemplateExercise {
        let exercise = Exercise(
            id: entity.exerciseId,
            name: entity.exerciseName,
            primaryMuscleGroup: MuscleGroup(rawValue: entity.primaryMuscleGroup) ?? .other,
            secondaryMuscleGroups: entity.secondaryMuscleGroups.compactMap { MuscleGroup(rawValue: $0) },
            category: ExerciseCategory(rawValue: entity.category) ?? .other,
            exerciseType: ExerciseType(rawValue: entity.exerciseType) ?? .weightedReps,
            instructions: entity.instructions,
            isCustom: entity.isCustom,
            isArchived: entity.isArchived,
            bodyweightFactor: entity.bodyweightFactor,
            equipmentBrand: entity.equipmentBrand,
            loadingType: entity.loadingType.flatMap { LoadingType(rawValue: $0) }
        )

        var setTargets: [TemplateSetTarget] = []
        if let json = entity.setTargetsJSON, let data = json.data(using: .utf8) {
            setTargets = (try? JSONDecoder().decode([TemplateSetTarget].self, from: data)) ?? []
        }

        return TemplateExercise(
            id: entity.id,
            exercise: exercise,
            order: entity.order,
            supersetGroup: entity.supersetGroup,
            notes: entity.notes,
            restTimerSeconds: entity.restTimerSeconds,
            targetSets: entity.targetSets,
            targetReps: entity.targetReps,
            targetWeight: entity.targetWeight,
            targetDurationSeconds: entity.targetDurationSeconds,
            targetDistanceMeters: entity.targetDistanceMeters,
            setTargets: setTargets,
            isWarmUp: entity.isWarmUp
        )
    }

    private static func encodeSetTargets(_ targets: [TemplateSetTarget]) -> String? {
        guard !targets.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(targets) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Converts a TemplateExercise (domain model) to a TemplateExerciseEntity
    public static func toEntity(_ domain: TemplateExercise) -> TemplateExerciseEntity {
        TemplateExerciseEntity(
            id: domain.id,
            exerciseId: domain.exercise.id,
            exerciseName: domain.exercise.name,
            primaryMuscleGroup: domain.exercise.primaryMuscleGroup.rawValue,
            secondaryMuscleGroups: domain.exercise.secondaryMuscleGroups.map { $0.rawValue },
            category: domain.exercise.category.rawValue,
            exerciseType: domain.exercise.exerciseType.rawValue,
            instructions: domain.exercise.instructions,
            isCustom: domain.exercise.isCustom,
            isArchived: domain.exercise.isArchived,
            bodyweightFactor: domain.exercise.bodyweightFactor,
            equipmentBrand: domain.exercise.equipmentBrand,
            loadingType: domain.exercise.loadingType?.rawValue,
            order: domain.order,
            supersetGroup: domain.supersetGroup,
            notes: domain.notes,
            restTimerSeconds: domain.restTimerSeconds,
            targetSets: domain.targetSets,
            targetReps: domain.targetReps,
            targetWeight: domain.targetWeight,
            targetDurationSeconds: domain.targetDurationSeconds,
            targetDistanceMeters: domain.targetDistanceMeters,
            setTargetsJSON: encodeSetTargets(domain.setTargets),
            isWarmUp: domain.isWarmUp
        )
    }

    /// Updates an existing TemplateExerciseEntity with values from a TemplateExercise domain model
    public static func updateEntity(_ entity: TemplateExerciseEntity, from domain: TemplateExercise) {
        entity.exerciseId = domain.exercise.id
        entity.exerciseName = domain.exercise.name
        entity.primaryMuscleGroup = domain.exercise.primaryMuscleGroup.rawValue
        entity.secondaryMuscleGroups = domain.exercise.secondaryMuscleGroups.map { $0.rawValue }
        entity.category = domain.exercise.category.rawValue
        entity.exerciseType = domain.exercise.exerciseType.rawValue
        entity.instructions = domain.exercise.instructions
        entity.isCustom = domain.exercise.isCustom
        entity.isArchived = domain.exercise.isArchived
        entity.bodyweightFactor = domain.exercise.bodyweightFactor
        entity.equipmentBrand = domain.exercise.equipmentBrand
        entity.loadingType = domain.exercise.loadingType?.rawValue
        entity.order = domain.order
        entity.supersetGroup = domain.supersetGroup
        entity.notes = domain.notes
        entity.restTimerSeconds = domain.restTimerSeconds
        entity.targetSets = domain.targetSets
        entity.targetReps = domain.targetReps
        entity.targetWeight = domain.targetWeight
        entity.targetDurationSeconds = domain.targetDurationSeconds
        entity.targetDistanceMeters = domain.targetDistanceMeters
        entity.setTargetsJSON = encodeSetTargets(domain.setTargets)
        entity.isWarmUp = domain.isWarmUp
    }
}
#endif
