import Foundation

struct Exercise: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var name: String
    var primaryMuscleGroup: MuscleGroup
    var secondaryMuscleGroups: [MuscleGroup]
    var category: ExerciseCategory
    var exerciseType: ExerciseType
    var instructions: String?
    var isCustom: Bool
    var isArchived: Bool
}
