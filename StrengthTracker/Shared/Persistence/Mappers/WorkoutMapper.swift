#if canImport(SwiftData)
import Foundation

public enum WorkoutMapper {
    /// Converts a WorkoutEntity (SwiftData) to a Workout (domain model)
    public static func toDomain(_ entity: WorkoutEntity) -> Workout {
        Workout(
            id: entity.id,
            name: entity.name,
            startedAt: entity.startedAt,
            completedAt: entity.completedAt,
            notes: entity.notes,
            templateId: entity.templateId,
            healthKitWorkoutId: entity.healthKitWorkoutId,
            exercises: entity.exercises.sorted(by: { $0.order < $1.order }).map { WorkoutExerciseMapper.toDomain($0) }
        )
    }

    /// Converts a Workout (domain model) to a WorkoutEntity (SwiftData)
    public static func toEntity(_ domain: Workout) -> WorkoutEntity {
        let entity = WorkoutEntity(
            id: domain.id,
            name: domain.name,
            startedAt: domain.startedAt,
            completedAt: domain.completedAt,
            notes: domain.notes,
            templateId: domain.templateId,
            healthKitWorkoutId: domain.healthKitWorkoutId
        )
        entity.exercises = domain.exercises.map { WorkoutExerciseMapper.toEntity($0) }
        return entity
    }

    /// Updates an existing WorkoutEntity with values from a Workout domain model
    public static func updateEntity(_ entity: WorkoutEntity, from domain: Workout) {
        entity.name = domain.name
        entity.startedAt = domain.startedAt
        entity.completedAt = domain.completedAt
        entity.notes = domain.notes
        entity.templateId = domain.templateId
        entity.healthKitWorkoutId = domain.healthKitWorkoutId

        // Update exercises in-place to preserve SwiftData relationships
        let existingById = Dictionary(uniqueKeysWithValues: entity.exercises.map { ($0.id, $0) })
        let domainIds = Set(domain.exercises.map(\.id))

        // Delete removed exercises
        for existing in entity.exercises where !domainIds.contains(existing.id) {
            entity.exercises.removeAll { $0.id == existing.id }
        }

        // Update existing or add new
        var updatedExercises: [WorkoutExerciseEntity] = []
        for domainExercise in domain.exercises {
            if let existing = existingById[domainExercise.id] {
                WorkoutExerciseMapper.updateEntity(existing, from: domainExercise)
                updatedExercises.append(existing)
            } else {
                let newEntity = WorkoutExerciseMapper.toEntity(domainExercise)
                updatedExercises.append(newEntity)
            }
        }
        entity.exercises = updatedExercises
    }
}

public enum WorkoutExerciseMapper {
    /// Converts a WorkoutExerciseEntity to a WorkoutExercise (domain model)
    public static func toDomain(_ entity: WorkoutExerciseEntity) -> WorkoutExercise {
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

        return WorkoutExercise(
            id: entity.id,
            exercise: exercise,
            order: entity.order,
            supersetGroup: entity.supersetGroup,
            notes: entity.notes,
            restTimerSeconds: entity.restTimerSeconds,
            sets: entity.sets.sorted(by: { $0.order < $1.order }).map { ExerciseSetMapper.toDomain($0) }
        )
    }

    /// Converts a WorkoutExercise (domain model) to a WorkoutExerciseEntity
    public static func toEntity(_ domain: WorkoutExercise) -> WorkoutExerciseEntity {
        let entity = WorkoutExerciseEntity(
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
            restTimerSeconds: domain.restTimerSeconds
        )
        entity.sets = domain.sets.map { ExerciseSetMapper.toEntity($0) }
        return entity
    }

    /// Updates an existing WorkoutExerciseEntity with values from a WorkoutExercise domain model
    public static func updateEntity(_ entity: WorkoutExerciseEntity, from domain: WorkoutExercise) {
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

        // Update sets in-place to preserve SwiftData relationships
        let existingById = Dictionary(uniqueKeysWithValues: entity.sets.map { ($0.id, $0) })
        let domainIds = Set(domain.sets.map(\.id))

        // Delete removed sets
        for existing in entity.sets where !domainIds.contains(existing.id) {
            entity.sets.removeAll { $0.id == existing.id }
        }

        // Update existing or add new
        var updatedSets: [ExerciseSetEntity] = []
        for domainSet in domain.sets {
            if let existing = existingById[domainSet.id] {
                ExerciseSetMapper.updateEntity(existing, from: domainSet)
                updatedSets.append(existing)
            } else {
                let newEntity = ExerciseSetMapper.toEntity(domainSet)
                updatedSets.append(newEntity)
            }
        }
        entity.sets = updatedSets
    }
}

public enum ExerciseSetMapper {
    /// Converts an ExerciseSetEntity to an ExerciseSet (domain model)
    public static func toDomain(_ entity: ExerciseSetEntity) -> ExerciseSet {
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
    public static func toEntity(_ domain: ExerciseSet) -> ExerciseSetEntity {
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
    public static func updateEntity(_ entity: ExerciseSetEntity, from domain: ExerciseSet) {
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
