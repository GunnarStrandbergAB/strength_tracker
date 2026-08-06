#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class ExerciseEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var primaryMuscleGroup: String
    public var secondaryMuscleGroups: [String]
    public var category: String
    public var exerciseType: String
    public var instructions: String?
    public var isCustom: Bool
    public var isArchived: Bool
    public var bodyweightFactor: Double?

    public init(
        id: UUID,
        name: String,
        primaryMuscleGroup: String,
        secondaryMuscleGroups: [String],
        category: String,
        exerciseType: String,
        instructions: String?,
        isCustom: Bool,
        isArchived: Bool,
        bodyweightFactor: Double? = nil
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
        self.bodyweightFactor = bodyweightFactor
    }
}
#endif
