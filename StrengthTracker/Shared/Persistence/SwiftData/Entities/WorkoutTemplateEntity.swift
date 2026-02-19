#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class WorkoutTemplateEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var notes: String?
    public var sortOrder: Int
    public var lastUsedAt: Date?
    public var timesUsed: Int
    public var isCustom: Bool = true

    @Relationship(deleteRule: .cascade)
    public var exercises: [TemplateExerciseEntity]

    public init(
        id: UUID,
        name: String,
        notes: String? = nil,
        sortOrder: Int,
        lastUsedAt: Date? = nil,
        timesUsed: Int,
        isCustom: Bool = true,
        exercises: [TemplateExerciseEntity] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.lastUsedAt = lastUsedAt
        self.timesUsed = timesUsed
        self.isCustom = isCustom
        self.exercises = exercises
    }
}

@Model
public final class TemplateExerciseEntity {
    @Attribute(.unique) public var id: UUID
    public var exerciseId: UUID
    public var exerciseName: String
    public var primaryMuscleGroup: String
    public var secondaryMuscleGroups: [String]
    public var category: String
    public var exerciseType: String
    public var instructions: String?
    public var isCustom: Bool
    public var isArchived: Bool
    public var order: Int
    public var supersetGroup: Int?
    public var notes: String?
    public var restTimerSeconds: Int?
    public var targetSets: Int
    public var targetReps: Int?
    public var targetWeight: Double?
    public var targetDurationSeconds: Int?
    public var targetDistanceMeters: Double?
    public var setTargetsJSON: String?
    public var isWarmUp: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \WorkoutTemplateEntity.exercises)
    public var template: WorkoutTemplateEntity?

    public init(
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
        targetDistanceMeters: Double? = nil,
        setTargetsJSON: String? = nil,
        isWarmUp: Bool = false
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
        self.setTargetsJSON = setTargetsJSON
        self.isWarmUp = isWarmUp
    }
}

@Model
public final class TemplateFolderEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortOrder: Int

    public init(
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
