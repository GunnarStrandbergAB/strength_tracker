import Foundation

public struct WorkoutTemplate: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var notes: String?
    public var sortOrder: Int
    public var lastUsedAt: Date?
    public var timesUsed: Int
    public var exercises: [TemplateExercise]

    public init(id: UUID, name: String, notes: String?, sortOrder: Int, lastUsedAt: Date?, timesUsed: Int, exercises: [TemplateExercise]) {
        self.id = id
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.lastUsedAt = lastUsedAt
        self.timesUsed = timesUsed
        self.exercises = exercises
    }
}

public struct TemplateExercise: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var exercise: Exercise
    public var order: Int
    public var supersetGroup: Int?
    public var notes: String?
    public var restTimerSeconds: Int?
    public var targetSets: Int
    public var targetReps: Int?
    public var targetWeight: Double?
    public var targetDurationSeconds: Int?
    public var targetDistanceMeters: Double?

    public init(id: UUID, exercise: Exercise, order: Int, supersetGroup: Int?, notes: String?, restTimerSeconds: Int?, targetSets: Int, targetReps: Int?, targetWeight: Double?, targetDurationSeconds: Int?, targetDistanceMeters: Double?) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.supersetGroup = supersetGroup
        self.notes = notes
        self.restTimerSeconds = restTimerSeconds
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
    }
}

public struct TemplateFolder: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var sortOrder: Int

    public init(id: UUID, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}
