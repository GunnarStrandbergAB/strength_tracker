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
    /// Free-text equipment brand/model for machine-like exercises
    /// (e.g. "Hammer Strength") — the same movement on different machines can
    /// take very different loads, so variants are tracked as separate exercises.
    public var equipmentBrand: String?
    /// How the machine is loaded; nil when unspecified or not a machine.
    public var loadingType: LoadingType?

    public init(id: UUID, name: String, primaryMuscleGroup: MuscleGroup, secondaryMuscleGroups: [MuscleGroup], category: ExerciseCategory, exerciseType: ExerciseType, instructions: String?, isCustom: Bool, isArchived: Bool, bodyweightFactor: Double? = nil, equipmentBrand: String? = nil, loadingType: LoadingType? = nil) {
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
        self.equipmentBrand = equipmentBrand
        self.loadingType = loadingType
    }

    /// Copy of this exercise as a new independent custom variant — new identity,
    /// its own PR/suggestion history. Used to model a gym's specific machine.
    public func duplicatedAsVariant(id: UUID = UUID()) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: secondaryMuscleGroups,
            category: category,
            exerciseType: exerciseType,
            instructions: instructions,
            isCustom: true,
            isArchived: false,
            bodyweightFactor: bodyweightFactor,
            equipmentBrand: equipmentBrand,
            loadingType: loadingType
        )
    }
}
