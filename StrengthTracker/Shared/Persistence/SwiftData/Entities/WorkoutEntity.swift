#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class WorkoutEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var startedAt: Date
    public var completedAt: Date?
    public var notes: String?
    public var templateId: UUID?
    public var healthKitWorkoutId: UUID?
    public var isDeload: Bool = false

    @Relationship(deleteRule: .cascade)
    public var exercises: [WorkoutExerciseEntity]

    public init(
        id: UUID,
        name: String,
        startedAt: Date,
        completedAt: Date? = nil,
        notes: String? = nil,
        templateId: UUID? = nil,
        healthKitWorkoutId: UUID? = nil,
        isDeload: Bool = false,
        exercises: [WorkoutExerciseEntity] = []
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.templateId = templateId
        self.healthKitWorkoutId = healthKitWorkoutId
        self.isDeload = isDeload
        self.exercises = exercises
    }
}
#endif
