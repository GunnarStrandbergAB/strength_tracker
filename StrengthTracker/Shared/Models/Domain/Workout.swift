import Foundation

public struct Workout: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var startedAt: Date
    public var completedAt: Date?
    public var notes: String?
    public var templateId: UUID?
    public var healthKitWorkoutId: UUID?
    public var exercises: [WorkoutExercise]

    public var isInProgress: Bool { completedAt == nil }

    public var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    public var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.exerciseVolume }
    }

    public init(id: UUID, name: String, startedAt: Date, completedAt: Date?, notes: String?, templateId: UUID?, healthKitWorkoutId: UUID? = nil, exercises: [WorkoutExercise]) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.templateId = templateId
        self.healthKitWorkoutId = healthKitWorkoutId
        self.exercises = exercises
    }
}
