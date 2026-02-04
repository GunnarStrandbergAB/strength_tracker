#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
final class ExerciseEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var primaryMuscleGroup: String
    var secondaryMuscleGroups: [String]
    var category: String
    var exerciseType: String
    var instructions: String?
    var isCustom: Bool
    var isArchived: Bool

    init(
        id: UUID,
        name: String,
        primaryMuscleGroup: String,
        secondaryMuscleGroups: [String],
        category: String,
        exerciseType: String,
        instructions: String?,
        isCustom: Bool,
        isArchived: Bool
    ) {
        self.id = id
        self.name = name
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.category = category
        self.exerciseType = exerciseType
        self.instructions = instructions
        self.isCustom = isCustom
        self.isArchived = isArchived
    }
}
#endif
