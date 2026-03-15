import Foundation

public struct WorkoutTemplate: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var notes: String?
    public var sortOrder: Int
    public var lastUsedAt: Date?
    public var timesUsed: Int
    public var exercises: [TemplateExercise]
    public var isCustom: Bool

    public init(id: UUID, name: String, notes: String?, sortOrder: Int, lastUsedAt: Date?, timesUsed: Int, exercises: [TemplateExercise], isCustom: Bool = true) {
        self.id = id
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.lastUsedAt = lastUsedAt
        self.timesUsed = timesUsed
        self.exercises = exercises
        self.isCustom = isCustom
    }
}

public struct TemplateSetTarget: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var order: Int
    public var targetReps: Int?
    public var targetWeight: Double?
    public var targetDurationSeconds: Int?
    public var targetDistanceMeters: Double?
    public var setType: SetType

    public init(id: UUID = UUID(), order: Int, targetReps: Int? = nil, targetWeight: Double? = nil, targetDurationSeconds: Int? = nil, targetDistanceMeters: Double? = nil, setType: SetType = .normal) {
        self.id = id
        self.order = order
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
        self.setType = setType
    }

    // Custom decoding for backward compatibility — existing JSON without setType decodes as .normal
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        targetReps = try container.decodeIfPresent(Int.self, forKey: .targetReps)
        targetWeight = try container.decodeIfPresent(Double.self, forKey: .targetWeight)
        targetDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .targetDurationSeconds)
        targetDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .targetDistanceMeters)
        setType = try container.decodeIfPresent(SetType.self, forKey: .setType) ?? .normal
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
    public var setTargets: [TemplateSetTarget]
    public var isWarmUp: Bool

    public init(id: UUID, exercise: Exercise, order: Int, supersetGroup: Int?, notes: String?, restTimerSeconds: Int?, targetSets: Int, targetReps: Int?, targetWeight: Double?, targetDurationSeconds: Int?, targetDistanceMeters: Double?, setTargets: [TemplateSetTarget] = [], isWarmUp: Bool = false) {
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
        self.setTargets = setTargets
        self.isWarmUp = isWarmUp
    }

    /// Returns a deloaded copy: halved sets (min 2), halved weight, cleared per-set targets.
    public func deloaded() -> TemplateExercise {
        TemplateExercise(
            id: id,
            exercise: exercise,
            order: order,
            supersetGroup: supersetGroup,
            notes: notes,
            restTimerSeconds: restTimerSeconds,
            targetSets: max(2, targetSets / 2),
            targetReps: targetReps,
            targetWeight: targetWeight.map { ($0 * 0.5).rounded(toNearest: 2.5) },
            targetDurationSeconds: targetDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            setTargets: [],
            isWarmUp: isWarmUp
        )
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
