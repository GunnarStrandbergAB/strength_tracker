#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class ExerciseSetEntity {
    @Attribute(.unique) public var id: UUID
    public var order: Int
    public var setType: String
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?
    public var isCompleted: Bool
    public var isPersonalRecord: Bool
    public var completedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExerciseEntity.sets)
    public var workoutExercise: WorkoutExerciseEntity?

    public init(
        id: UUID,
        order: Int,
        setType: String,
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rpe: Double? = nil,
        isCompleted: Bool,
        isPersonalRecord: Bool,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.setType = setType
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.isPersonalRecord = isPersonalRecord
        self.completedAt = completedAt
    }
}
#endif
