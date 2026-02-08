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
            exercises: entity.exercises.map { TemplateExerciseMapper.toDomain($0) }
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
            timesUsed: domain.timesUsed
        )
        entity.exercises = domain.exercises.map { TemplateExerciseMapper.toEntity($0) }
        return entity
    }

    /// Updates an existing WorkoutTemplateEntity with values from a WorkoutTemplate domain model
    public static func updateEntity(_ entity: WorkoutTemplateEntity, from domain: WorkoutTemplate) {
        entity.name = domain.name
        entity.notes = domain.notes
        entity.sortOrder = domain.sortOrder
        entity.lastUsedAt = domain.lastUsedAt
        entity.timesUsed = domain.timesUsed

        // Update exercises (replace all)
        entity.exercises = domain.exercises.map { TemplateExerciseMapper.toEntity($0) }
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
            isArchived: entity.isArchived
        )

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
            targetDistanceMeters: entity.targetDistanceMeters
        )
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
            order: domain.order,
            supersetGroup: domain.supersetGroup,
            notes: domain.notes,
            restTimerSeconds: domain.restTimerSeconds,
            targetSets: domain.targetSets,
            targetReps: domain.targetReps,
            targetWeight: domain.targetWeight,
            targetDurationSeconds: domain.targetDurationSeconds,
            targetDistanceMeters: domain.targetDistanceMeters
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
        entity.order = domain.order
        entity.supersetGroup = domain.supersetGroup
        entity.notes = domain.notes
        entity.restTimerSeconds = domain.restTimerSeconds
        entity.targetSets = domain.targetSets
        entity.targetReps = domain.targetReps
        entity.targetWeight = domain.targetWeight
        entity.targetDurationSeconds = domain.targetDurationSeconds
        entity.targetDistanceMeters = domain.targetDistanceMeters
    }
}
#endif
