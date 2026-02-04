#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
final class WorkoutExerciseEntity {
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

    @Relationship(deleteRule: .cascade)
    var sets: [ExerciseSetEntity]

    @Relationship(deleteRule: .nullify, inverse: \WorkoutEntity.exercises)
    var workout: WorkoutEntity?

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
        self.order = order
        self.supersetGroup = supersetGroup
        self.notes = notes
        self.restTimerSeconds = restTimerSeconds
        self.sets = sets
    }
}
#endif
