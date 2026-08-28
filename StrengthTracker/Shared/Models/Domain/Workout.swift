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

    /// Effective-load volume across all exercises. Body weight is required —
    /// bodyweight-rep exercises count bw × factor + extra kg per rep.
    public func totalVolume(bodyWeightKg: Double) -> Double {
        exercises.reduce(0) { $0 + $1.exerciseVolume(bodyWeightKg: bodyWeightKg) }
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

// MARK: - Set Completion

extension Workout {
    /// Toggles a set's completion state in place — the single implementation shared by
    /// the active-workout and history editing flows.
    /// - Parameter date: the timestamp to stamp on completion. Active workouts use the
    ///   default "now"; history/retro edits pass the workout's own window so backdated
    ///   sets carry backdated timestamps (PR dates and analytics derive from them).
    /// - Returns: the new completion state, or nil if the exercise/set was not found.
    @discardableResult
    public mutating func toggleSetCompletion(exerciseId: UUID, setId: UUID, at date: Date = Date()) -> Bool? {
        guard let ei = exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return nil }
        let wasCompleted = exercises[ei].sets[si].isCompleted
        exercises[ei].sets[si].isCompleted = !wasCompleted
        exercises[ei].sets[si].completedAt = wasCompleted ? nil : date
        return !wasCompleted
    }

    /// Completes every incomplete set, stamping the given date — used by retro logging
    /// where all sets happened inside the workout's historical window.
    public mutating func completeAllSets(at date: Date) {
        for ei in exercises.indices {
            for si in exercises[ei].sets.indices where !exercises[ei].sets[si].isCompleted {
                exercises[ei].sets[si].isCompleted = true
                exercises[ei].sets[si].completedAt = date
            }
        }
    }
}

// MARK: - Active Exercise

extension Workout {
    /// The exercise currently "in focus" — the single source of truth shared by the
    /// in-app card highlight, the widget, and the rest-timer context.
    ///
    /// `preferredId` is the exercise the user last interacted with (completed/edited a
    /// set, tapped its card, or just added it). It stays active as long as it exists in
    /// the workout — finishing its last set does NOT move focus (you're resting from
    /// it), and zero-set exercises can hold focus too. Without a preference, falls back
    /// to the first incomplete exercise, or the last exercise when everything is done.
    public func activeExercise(preferredId: UUID?) -> WorkoutExercise? {
        guard !exercises.isEmpty else { return nil }
        if let preferredId, let preferred = exercises.first(where: { $0.id == preferredId }) {
            return preferred
        }
        return exercises.first { $0.sets.contains { !$0.isCompleted } } ?? exercises.last
    }

    /// Next incomplete exercise strictly after the given one in order (wrapping,
    /// excluding it). Nil when the id is unknown or no other exercise has work left.
    public func nextIncompleteExercise(afterId id: UUID?) -> WorkoutExercise? {
        guard let id, let idx = exercises.firstIndex(where: { $0.id == id }) else { return nil }
        func hasIncomplete(_ ex: WorkoutExercise) -> Bool { ex.sets.contains { !$0.isCompleted } }
        return exercises[(idx + 1)...].first(where: hasIncomplete)
            ?? exercises[..<idx].first(where: hasIncomplete)
    }

    /// Exercise holding the most recently completed set — restores the active
    /// exercise after an app relaunch without any extra persistence.
    public var lastInteractedExerciseId: UUID? {
        exercises
            .compactMap { ex in ex.sets.compactMap(\.completedAt).max().map { (ex.id, $0) } }
            .max { $0.1 < $1.1 }?.0
    }
}
