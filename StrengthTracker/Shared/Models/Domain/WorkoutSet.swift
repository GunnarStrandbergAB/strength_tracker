import Foundation

public struct ExerciseSet: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var order: Int
    public var setType: SetType
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?
    public var isCompleted: Bool
    public var isPersonalRecord: Bool
    public var completedAt: Date?

    public var setVolume: Double {
        guard isCompleted, setType != .warmup else { return 0 }
        return (weight ?? 0) * Double(reps ?? 0)
    }

    public init(id: UUID, order: Int, setType: SetType, weight: Double?, reps: Int?, durationSeconds: Int?, distanceMeters: Double?, rpe: Double?, isCompleted: Bool, isPersonalRecord: Bool, completedAt: Date?) {
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

public struct WorkoutExercise: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var exercise: Exercise
    public var order: Int
    public var supersetGroup: Int?
    public var notes: String?
    public var restTimerSeconds: Int?
    public var sets: [ExerciseSet]

    public var exerciseVolume: Double {
        sets.reduce(0) { $0 + $1.setVolume }
    }

    public init(id: UUID, exercise: Exercise, order: Int, supersetGroup: Int?, notes: String?, restTimerSeconds: Int?, sets: [ExerciseSet]) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.supersetGroup = supersetGroup
        self.notes = notes
        self.restTimerSeconds = restTimerSeconds
        self.sets = sets
    }
}
