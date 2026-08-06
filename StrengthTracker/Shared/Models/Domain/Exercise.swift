import Foundation

public struct Exercise: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var primaryMuscleGroup: MuscleGroup
    public var secondaryMuscleGroups: [MuscleGroup]
    public var category: ExerciseCategory
    public var exerciseType: ExerciseType
    public var instructions: String?
    public var isCustom: Bool
    public var isArchived: Bool
    /// Fraction of body weight moved per rep for `.bodyweightReps` exercises
    /// (e.g. 0.64 for a push-up). nil for non-bodyweight types and legacy data;
    /// computation sites fall back to 1.0 via `baseLoadPerRep(bodyWeightKg:)`.
    public var bodyweightFactor: Double?

    public init(id: UUID, name: String, primaryMuscleGroup: MuscleGroup, secondaryMuscleGroups: [MuscleGroup], category: ExerciseCategory, exerciseType: ExerciseType, instructions: String?, isCustom: Bool, isArchived: Bool, bodyweightFactor: Double? = nil) {
        self.id = id
        self.name = name
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.category = category
        self.exerciseType = exerciseType
        self.instructions = instructions
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.bodyweightFactor = bodyweightFactor
    }
}
