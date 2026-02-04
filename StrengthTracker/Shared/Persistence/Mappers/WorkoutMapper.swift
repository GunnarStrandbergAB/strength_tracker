#if canImport(SwiftData)
import Foundation

enum WorkoutMapper {
    /// Converts a WorkoutEntity (SwiftData) to a Workout (domain model)
    static func toDomain(_ entity: WorkoutEntity) -> Workout {
        Workout(
            id: entity.id,
            name: entity.name,
            startedAt: entity.startedAt,
            completedAt: entity.completedAt,
            notes: entity.notes,
            templateId: entity.templateId,
            exercises: entity.exercises.map { WorkoutExerciseMapper.toDomain($0) }
        )
    }

    /// Converts a Workout (domain model) to a WorkoutEntity (SwiftData)
    static func toEntity(_ domain: Workout) -> WorkoutEntity {
        let entity = WorkoutEntity(
            id: domain.id,
            name: domain.name,
            startedAt: domain.startedAt,
            completedAt: domain.completedAt,
            notes: domain.notes,
            templateId: domain.templateId
        )
        entity.exercises = domain.exercises.map { WorkoutExerciseMapper.toEntity($0) }
        return entity
    }

    /// Updates an existing WorkoutEntity with values from a Workout domain model
    static func updateEntity(_ entity: WorkoutEntity, from domain: Workout) {
        entity.name = domain.name
        entity.startedAt = domain.startedAt
        entity.completedAt = domain.completedAt
        entity.notes = domain.notes
        entity.templateId = domain.templateId

        // Update exercises (replace all)
        entity.exercises = domain.exercises.map { WorkoutExerciseMapper.toEntity($0) }
    }
}

enum WorkoutExerciseMapper {
    /// Converts a WorkoutExerciseEntity to a WorkoutExercise (domain model)
    static func toDomain(_ entity: WorkoutExerciseEntity) -> WorkoutExercise {
        WorkoutExercise(
            id: entity.id,
            exercise: ExerciseMapper.toDomain(entity.exercise),
            order: entity.order,
            supersetGroup: entity.supersetGroup,
            notes: entity.notes,
            restTimerSeconds: entity.restTimerSeconds,
            sets: entity.sets.map { ExerciseSetMapper.toDomain($0) }
        )
    }

    /// Converts a WorkoutExercise (domain model) to a WorkoutExerciseEntity
    static func toEntity(_ domain: WorkoutExercise) -> WorkoutExerciseEntity {
        let entity = WorkoutExerciseEntity(
            id: domain.id,
            exercise: ExerciseMapper.toEntity(domain.exercise),
            order: domain.order,
            supersetGroup: domain.supersetGroup,
            notes: domain.notes,
            restTimerSeconds: domain.restTimerSeconds
        )
        entity.sets = domain.sets.map { ExerciseSetMapper.toEntity($0) }
        return entity
    }

    /// Updates an existing WorkoutExerciseEntity with values from a WorkoutExercise domain model
    static func updateEntity(_ entity: WorkoutExerciseEntity, from domain: WorkoutExercise) {
        ExerciseMapper.updateEntity(entity.exercise, from: domain.exercise)
        entity.order = domain.order
        entity.supersetGroup = domain.supersetGroup
        entity.notes = domain.notes
        entity.restTimerSeconds = domain.restTimerSeconds

        // Update sets (replace all)
        entity.sets = domain.sets.map { ExerciseSetMapper.toEntity($0) }
    }
}

enum ExerciseSetMapper {
    /// Converts an ExerciseSetEntity to an ExerciseSet (domain model)
    static func toDomain(_ entity: ExerciseSetEntity) -> ExerciseSet {
        ExerciseSet(
            id: entity.id,
            order: entity.order,
            setType: SetType(rawValue: entity.setType) ?? .normal,
            weight: entity.weight,
            reps: entity.reps,
            durationSeconds: entity.durationSeconds,
            distanceMeters: entity.distanceMeters,
            rpe: entity.rpe,
            isCompleted: entity.isCompleted,
            isPersonalRecord: entity.isPersonalRecord,
            completedAt: entity.completedAt
        )
    }

    /// Converts an ExerciseSet (domain model) to an ExerciseSetEntity
    static func toEntity(_ domain: ExerciseSet) -> ExerciseSetEntity {
        ExerciseSetEntity(
            id: domain.id,
            order: domain.order,
            setType: domain.setType.rawValue,
            weight: domain.weight,
            reps: domain.reps,
            durationSeconds: domain.durationSeconds,
            distanceMeters: domain.distanceMeters,
            rpe: domain.rpe,
            isCompleted: domain.isCompleted,
            isPersonalRecord: domain.isPersonalRecord,
            completedAt: domain.completedAt
        )
    }

    /// Updates an existing ExerciseSetEntity with values from an ExerciseSet domain model
    static func updateEntity(_ entity: ExerciseSetEntity, from domain: ExerciseSet) {
        entity.order = domain.order
        entity.setType = domain.setType.rawValue
        entity.weight = domain.weight
        entity.reps = domain.reps
        entity.durationSeconds = domain.durationSeconds
        entity.distanceMeters = domain.distanceMeters
        entity.rpe = domain.rpe
        entity.isCompleted = domain.isCompleted
        entity.isPersonalRecord = domain.isPersonalRecord
        entity.completedAt = domain.completedAt
    }
}
#endif
