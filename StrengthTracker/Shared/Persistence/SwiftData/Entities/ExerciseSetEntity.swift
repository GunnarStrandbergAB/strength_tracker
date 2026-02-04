#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
final class ExerciseSetEntity {
    @Attribute(.unique) var id: UUID
    var order: Int
    var setType: String
    var weight: Double?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var rpe: Double?
    var isCompleted: Bool
    var isPersonalRecord: Bool
    var completedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExerciseEntity.sets)
    var workoutExercise: WorkoutExerciseEntity?

    init(
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
