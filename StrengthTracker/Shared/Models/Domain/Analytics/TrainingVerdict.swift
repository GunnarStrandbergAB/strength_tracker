import Foundation

/// The one training-direction call the whole app agrees on: should the user
/// deload, hold loads steady, or keep progressing? Computed once per insights
/// generation by `TrainingAdvisor`; every surface (highlights, debrief, digest,
/// weight suggestions, pre-workout card, widget, AI tools, plan engine) reads
/// this instead of re-deriving its own answer from raw signals.
public struct TrainingVerdict: Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        case deload
        case hold
        case progress
    }

    public let kind: Kind
    /// 0–1, carried over from the deload recommendation (0 for hold/progress
    /// verdicts that were not driven by fatigue).
    public let urgency: Double
    /// Human-readable reasons, most important first.
    public let reasons: [String]
    /// Fatigue signals behind the call (empty for a plain progress verdict).
    public let signals: [DeloadSignal]
    /// The single action sentence every surface shows.
    public let action: String
    /// When this kind first became the verdict (hysteresis keeps it stable).
    public let since: Date
    public let computedAt: Date
    /// True while the latest completed workout is a recent deload session.
    public let isActiveDeload: Bool

    public init(
        kind: Kind,
        urgency: Double,
        reasons: [String],
        signals: [DeloadSignal],
        action: String,
        since: Date,
        computedAt: Date,
        isActiveDeload: Bool
    ) {
        self.kind = kind
        self.urgency = urgency
        self.reasons = reasons
        self.signals = signals
        self.action = action
        self.since = since
        self.computedAt = computedAt
        self.isActiveDeload = isActiveDeload
    }

    public var headline: String {
        if isActiveDeload { return "Deload In Progress" }
        switch kind {
        case .deload: return "Deload Recommended"
        case .hold: return "Hold Steady"
        case .progress: return "Clear to Progress"
        }
    }

    /// Whether a load increase (APRE "Increase Weight", extrapolated weight
    /// suggestions, "room to push" copy) contradicts this verdict.
    public var discouragesLoadIncrease: Bool { kind != .progress }
}
