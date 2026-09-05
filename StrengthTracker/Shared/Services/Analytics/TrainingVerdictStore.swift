import Foundation

/// Persisted advisor state so the verdict stays stable across launches
/// (hysteresis needs to know when a deload verdict started and how many
/// clear days have been seen since).
public struct TrainingVerdictState: Codable, Sendable, Hashable {
    public var verdict: TrainingVerdict
    /// Start-of-day dates on which a non-deload evaluation was observed while a
    /// deload verdict was standing. Two distinct days release the verdict.
    public var clearDays: [Date]

    public init(verdict: TrainingVerdict, clearDays: [Date] = []) {
        self.verdict = verdict
        self.clearDays = clearDays
    }
}

public protocol TrainingVerdictStoring: AnyObject, Sendable {
    func load() -> TrainingVerdictState?
    func save(_ state: TrainingVerdictState?)
}

/// JSON in UserDefaults (standard suite by default).
public final class UserDefaultsTrainingVerdictStore: TrainingVerdictStoring, @unchecked Sendable {
    public static let key = "training_verdict_state_v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> TrainingVerdictState? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(TrainingVerdictState.self, from: data)
    }

    public func save(_ state: TrainingVerdictState?) {
        guard let state, let data = try? JSONEncoder().encode(state) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

public final class InMemoryTrainingVerdictStore: TrainingVerdictStoring, @unchecked Sendable {
    private var state: TrainingVerdictState?
    public init(state: TrainingVerdictState? = nil) { self.state = state }
    public func load() -> TrainingVerdictState? { state }
    public func save(_ state: TrainingVerdictState?) { self.state = state }
}
