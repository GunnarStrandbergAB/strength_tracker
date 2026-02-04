#if canImport(SwiftData)
import Foundation

enum TemplateMapper {
    /// Converts a WorkoutTemplateEntity (SwiftData) to a WorkoutTemplate (domain model)
    static func toDomain(_ entity: WorkoutTemplateEntity) -> WorkoutTemplate {
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
    static func toEntity(_ domain: WorkoutTemplate) -> WorkoutTemplateEntity {
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
    static func updateEntity(_ entity: WorkoutTemplateEntity, from domain: WorkoutTemplate) {
        entity.name = domain.name
        entity.notes = domain.notes
        entity.sortOrder = domain.sortOrder
        entity.lastUsedAt = domain.lastUsedAt
        entity.timesUsed = domain.timesUsed

        // Update exercises (replace all)
        entity.exercises = domain.exercises.map { TemplateExerciseMapper.toEntity($0) }
    }
}

enum TemplateExerciseMapper {
    /// Converts a TemplateExerciseEntity to a TemplateExercise (domain model)
    static func toDomain(_ entity: TemplateExerciseEntity) -> TemplateExercise {
        TemplateExercise(
            id: entity.id,
            exercise: ExerciseMapper.toDomain(entity.exercise),
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
    static func toEntity(_ domain: TemplateExercise) -> TemplateExerciseEntity {
        TemplateExerciseEntity(
            id: domain.id,
            exercise: ExerciseMapper.toEntity(domain.exercise),
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
    static func updateEntity(_ entity: TemplateExerciseEntity, from domain: TemplateExercise) {
        ExerciseMapper.updateEntity(entity.exercise, from: domain.exercise)
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
