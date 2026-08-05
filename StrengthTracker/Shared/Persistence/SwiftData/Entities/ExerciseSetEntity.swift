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
    public var rir: Double?
    public var isCompleted: Bool
    public var isPersonalRecord: Bool
    // Inline default (not just an init default) so SwiftData lightweight migration
    // can backfill existing rows.
    public var isFailure: Bool = false
    public var completedAt: Date?
    /// JSON-encoded [DropSetEntry]; nil when the set has no drop segments.
    public var dropSetsJSON: String?

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
        rir: Double? = nil,
        isCompleted: Bool,
        isPersonalRecord: Bool,
        isFailure: Bool = false,
        completedAt: Date? = nil,
        dropSetsJSON: String? = nil
    ) {
        self.id = id
        self.order = order
        self.setType = setType
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rpe = rpe
        self.rir = rir
        self.isCompleted = isCompleted
        self.isPersonalRecord = isPersonalRecord
        self.isFailure = isFailure
        self.completedAt = completedAt
        self.dropSetsJSON = dropSetsJSON
    }
}
#endif
