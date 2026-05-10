import Foundation

public struct Workout: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var startedAt: Date
    public var completedAt: Date?
    public var notes: String?
    public var templateId: UUID?
    public var healthKitWorkoutId: UUID?
    public var isDeload: Bool
    public var plannedSessionId: UUID?
    public var plannedPlanId: UUID?
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

    public init(id: UUID, name: String, startedAt: Date, completedAt: Date?, notes: String?, templateId: UUID?, healthKitWorkoutId: UUID? = nil, isDeload: Bool = false, plannedSessionId: UUID? = nil, plannedPlanId: UUID? = nil, exercises: [WorkoutExercise]) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.notes = notes
        self.templateId = templateId
        self.healthKitWorkoutId = healthKitWorkoutId
        self.isDeload = isDeload
        self.plannedSessionId = plannedSessionId
        self.plannedPlanId = plannedPlanId
        self.exercises = exercises
    }

    // Custom decoding for backward compatibility — existing JSON without isDeload decodes as false
    private enum CodingKeys: String, CodingKey {
        case id, name, startedAt, completedAt, notes, templateId, healthKitWorkoutId, isDeload, plannedSessionId, plannedPlanId, exercises
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        templateId = try container.decodeIfPresent(UUID.self, forKey: .templateId)
        healthKitWorkoutId = try container.decodeIfPresent(UUID.self, forKey: .healthKitWorkoutId)
        isDeload = try container.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
        plannedSessionId = try container.decodeIfPresent(UUID.self, forKey: .plannedSessionId)
        plannedPlanId = try container.decodeIfPresent(UUID.self, forKey: .plannedPlanId)
        exercises = try container.decode([WorkoutExercise].self, forKey: .exercises)
    }
}
