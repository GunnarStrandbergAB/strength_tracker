#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
final class WorkoutEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var notes: String?
    var templateId: UUID?

    @Relationship(deleteRule: .cascade)
    var exercises: [WorkoutExerciseEntity]

    init(
        id: UUID,
        name: String,
        startedAt: Date,
        completedAt: Date? = nil,
        notes: String? = nil,
        templateId: UUID? = nil,
        exercises: [WorkoutExerciseEntity] = []
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.templateId = templateId
        self.exercises = exercises
    }
}
#endif
