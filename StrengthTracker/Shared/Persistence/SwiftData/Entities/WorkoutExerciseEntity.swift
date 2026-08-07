#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class WorkoutExerciseEntity {
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
    public var bodyweightFactor: Double?
    public var order: Int
    public var supersetGroup: Int?
    public var notes: String?
    public var restTimerSeconds: Int?

    @Relationship(deleteRule: .cascade)
    public var sets: [ExerciseSetEntity]

    @Relationship(deleteRule: .nullify, inverse: \WorkoutEntity.exercises)
    public var workout: WorkoutEntity?

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
        bodyweightFactor: Double? = nil,
        order: Int,
        supersetGroup: Int? = nil,
        notes: String? = nil,
        restTimerSeconds: Int? = nil,
        sets: [ExerciseSetEntity] = []
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
        self.bodyweightFactor = bodyweightFactor
        self.order = order
        self.supersetGroup = supersetGroup
        self.notes = notes
        self.restTimerSeconds = restTimerSeconds
        self.sets = sets
    }
}
#endif
