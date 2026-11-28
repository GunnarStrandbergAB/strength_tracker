import Foundation

/// How one plan exercise gets harder over time. A `PlanExercise` without a rule
/// follows the plan's percentage wave instead.
public struct ProgressionRule: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Add a rep until every set reaches the top of the range, then add weight.
        case repsThenWeight
        /// Keep the reps and add weight.
        case fixedSteps

        public var displayName: String {
            switch self {
            case .repsThenWeight: return "Reps, then weight"
            case .fixedSteps: return "Weight steps"
            }
        }
    }

    public var kind: Kind
    public var sets: Int
    public var minReps: Int
    public var maxReps: Int
    /// Weight added per step, in the exercise's logging convention. Zero progresses reps only.
    public var incrementKg: Double
    /// Successful sessions needed before the target moves.
    public var sessionsPerStep: Int
    /// Missed sessions in a row before the weight backs off. Zero never backs off.
    public var missesBeforeBackoff: Int
    public var backoffPercent: Int
    public var startWeightKg: Double
    public var startReps: Int
    public var restSeconds: Int

    public init(kind: Kind, sets: Int, minReps: Int, maxReps: Int, incrementKg: Double,
                sessionsPerStep: Int = 1, missesBeforeBackoff: Int = 0, backoffPercent: Int = 10,
                startWeightKg: Double, startReps: Int? = nil, restSeconds: Int = 120) {
        self.kind = kind
        self.sets = sets
        self.minReps = minReps
        self.maxReps = maxReps
        self.incrementKg = incrementKg
        self.sessionsPerStep = sessionsPerStep
        self.missesBeforeBackoff = missesBeforeBackoff
        self.backoffPercent = backoffPercent
        self.startWeightKg = startWeightKg
        self.startReps = startReps ?? minReps
        self.restSeconds = restSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case kind, sets, minReps, maxReps, incrementKg, sessionsPerStep, missesBeforeBackoff, backoffPercent
        case startWeightKg, startReps, restSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(Kind.self, forKey: .kind)
        sets = try values.decode(Int.self, forKey: .sets)
        maxReps = try values.decode(Int.self, forKey: .maxReps)
        minReps = try values.decodeIfPresent(Int.self, forKey: .minReps) ?? maxReps
        incrementKg = try values.decode(Double.self, forKey: .incrementKg)
        sessionsPerStep = try values.decodeIfPresent(Int.self, forKey: .sessionsPerStep) ?? 1
        missesBeforeBackoff = try values.decodeIfPresent(Int.self, forKey: .missesBeforeBackoff) ?? 0
        backoffPercent = try values.decodeIfPresent(Int.self, forKey: .backoffPercent) ?? 10
        startWeightKg = try values.decode(Double.self, forKey: .startWeightKg)
        startReps = try values.decodeIfPresent(Int.self, forKey: .startReps) ?? minReps
        restSeconds = try values.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 120
    }

    /// The same rule with weight steps on fixed reps collapsed to one rep target and
    /// the start reps inside the range.
    public var normalized: ProgressionRule {
        var rule = self
        if rule.kind == .fixedSteps { rule.minReps = rule.maxReps }
        rule.startReps = min(max(rule.startReps, rule.minReps), rule.maxReps)
        return rule
    }

    public func validate() throws {
        guard (1...20).contains(sets) else { throw PlanEditError("Sets must be 1–20.") }
        guard (1...100).contains(minReps), (1...100).contains(maxReps), minReps <= maxReps else {
            throw PlanEditError("The rep range must be 1–100 with the low end first.")
        }
        guard incrementKg.isFinite, (0...50).contains(incrementKg) else { throw PlanEditError("The weight step must be 0–50 kg.") }
        guard (1...12).contains(sessionsPerStep) else { throw PlanEditError("Sessions per step must be 1–12.") }
        guard (0...10).contains(missesBeforeBackoff), (0...50).contains(backoffPercent) else {
            throw PlanEditError("Back-off must be after 0–10 misses and at most 50%.")
        }
        guard startWeightKg.isFinite, (0...1000).contains(startWeightKg) else { throw PlanEditError("The start weight must be 0–1000 kg.") }
        guard (15...900).contains(restSeconds) else { throw PlanEditError("Rest must be 15–900 seconds.") }
        if kind == .fixedSteps, incrementKg == 0 { throw PlanEditError("Weight steps need a weight step above zero.") }
    }

    /// One sentence a lifter can check against what the plan then does.
    public func summary(unit: WeightUnit) -> String {
        let rule = normalized
        let step = unit.format(rule.incrementKg)
        let after = rule.sessionsPerStep == 1 ? "" : " \(rule.sessionsPerStep) sessions in a row"
        var text: String
        switch rule.kind {
        case .repsThenWeight:
            let range = rule.minReps == rule.maxReps ? "\(rule.maxReps)" : "\(rule.minReps)–\(rule.maxReps)"
            if rule.incrementKg > 0 {
                text = "\(rule.sets) × \(range). Add a rep when every set hits the target\(after); at \(rule.maxReps), add \(step) and restart at \(rule.minReps)."
            } else {
                text = "\(rule.sets) × \(range). Add a rep when every set hits the target\(after), up to \(rule.maxReps)."
            }
        case .fixedSteps:
            text = "\(rule.sets) × \(rule.maxReps). Add \(step) when every set hits \(rule.maxReps)\(after)."
        }
        if rule.missesBeforeBackoff > 0, rule.backoffPercent > 0 {
            text += " After \(rule.missesBeforeBackoff) misses in a row, drop \(rule.backoffPercent)%."
        }
        return text
    }
}

/// How quickly a plan asks for more. Each pace is a preset for the per-exercise rules,
/// which stay editable one by one.
public enum PlanPace: String, Codable, CaseIterable, Sendable {
    case conservative, standard, aggressive

    public var displayName: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .conservative: return "Add a rep, then weight, after hitting each target twice."
        case .standard: return "Add a rep each session; add weight at the top of the rep range."
        case .aggressive: return "Add weight every session at fixed reps; back off after three misses."
        }
    }

    /// Weekly gain in estimated 1RM, as a share of the lift, that this pace suits.
    public static func suited(toWeeklyGain share: Double) -> PlanPace {
        if share >= 0.01 { return .aggressive }
        if share >= 0.0025 { return .standard }
        return .conservative
    }
}

/// Weight and reps asked for in one session.
public struct ProgressionTarget: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }

    public func isAbove(_ other: ProgressionTarget) -> Bool {
        weightKg > other.weightKg + 0.001 || (abs(weightKg - other.weightKg) <= 0.001 && reps > other.reps)
    }
}

/// What was actually done against a planned target, kept on the completed session so
/// the rule can be replayed from the plan alone.
public struct ProgressionOutcome: Codable, Equatable, Sendable {
    /// Weight of the working sets, in the planned exercise's logging convention.
    public var weightKg: Double
    /// Fewest reps in any counted working set.
    public var lowestReps: Int
    /// False when fewer working sets were completed than planned.
    public var completedAllSets: Bool

    public init(weightKg: Double, lowestReps: Int, completedAllSets: Bool) {
        self.weightKg = weightKg
        self.lowestReps = lowestReps
        self.completedAllSets = completedAllSets
    }
}
