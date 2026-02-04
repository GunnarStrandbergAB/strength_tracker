#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
final class WorkoutTemplateEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String?
    var sortOrder: Int
    var lastUsedAt: Date?
    var timesUsed: Int

    @Relationship(deleteRule: .cascade)
    var exercises: [TemplateExerciseEntity]

    init(
        id: UUID,
        name: String,
        notes: String? = nil,
        sortOrder: Int,
        lastUsedAt: Date? = nil,
        timesUsed: Int,
        exercises: [TemplateExerciseEntity] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.lastUsedAt = lastUsedAt
        self.timesUsed = timesUsed
        self.exercises = exercises
    }
}

@Model
final class TemplateExerciseEntity {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var primaryMuscleGroup: String
    var secondaryMuscleGroups: [String]
    var category: String
    var exerciseType: String
    var instructions: String?
    var isCustom: Bool
    var isArchived: Bool
    var order: Int
    var supersetGroup: Int?
    var notes: String?
    var restTimerSeconds: Int?
    var targetSets: Int
    var targetReps: Int?
    var targetWeight: Double?
    var targetDurationSeconds: Int?
    var targetDistanceMeters: Double?

    @Relationship(deleteRule: .nullify, inverse: \WorkoutTemplateEntity.exercises)
    var template: WorkoutTemplateEntity?

    init(
        id: UUID,
        exerciseId: UUID,
        exerciseName: String,
        primaryMuscleGroup: String,
        secondaryMuscleGroups: [String],
        category: String,
        exerciseType: String,
        instructions: String?,
        isCustom: Bool,
        isArchived: Bool,
        order: Int,
        supersetGroup: Int? = nil,
        notes: String? = nil,
        restTimerSeconds: Int? = nil,
        targetSets: Int,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetDurationSeconds: Int? = nil,
        targetDistanceMeters: Double? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.category = category
        self.exerciseType = exerciseType
        self.instructions = instructions
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.order = order
        self.supersetGroup = supersetGroup
        self.notes = notes
        self.restTimerSeconds = restTimerSeconds
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
    }
}

@Model
final class TemplateFolderEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int

    init(
        id: UUID,
        name: String,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}
#endif
