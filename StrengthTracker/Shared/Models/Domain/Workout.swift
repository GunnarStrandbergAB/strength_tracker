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

    /// Body-weight-aware volume: substitutes `bodyWeightKg` for bodyweight exercises with nil weight.
    public func totalVolume(bodyWeightKg: Double) -> Double {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets
                .filter(\.isCompleted)
                .filter { $0.setType != .warmup }
                .reduce(0) { sum, set in
                    let w = set.weight ?? (exercise.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0)
                    return sum + w * Double(set.reps ?? 0)
                }
        }
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
