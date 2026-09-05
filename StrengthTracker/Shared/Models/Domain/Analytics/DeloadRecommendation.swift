import Foundation

/// Recommendation to take a deload week based on accumulated fatigue signals.
public struct DeloadRecommendation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let urgencyScore: Double  // 0-1
    public let triggers: [DeloadSignal]
    public let weeksSinceLastDeload: Int
    public let suggestedAction: String

    public init(
        id: UUID = UUID(),
        urgencyScore: Double,
        triggers: [DeloadSignal],
        weeksSinceLastDeload: Int,
        suggestedAction: String
    ) {
        self.id = id
        self.urgencyScore = urgencyScore
        self.triggers = triggers
        self.weeksSinceLastDeload = weeksSinceLastDeload
        self.suggestedAction = suggestedAction
    }

    /// Triggers that can justify a deload on their own (everything but `overdue`).
    public var primaryTriggers: [DeloadSignal] {
        triggers.filter(\.isPrimary)
    }
}

/// Individual signals that contribute to a deload recommendation.
public enum DeloadSignal: String, Codable, Sendable {
    case effortCreep          // effort ratio or RPE rising over ≥3 sessions spanning ≥7 days
    case performanceDecline   // e1RM regressing in ≥2 exercises and ≥40% of tracked lifts
    case overdue              // many calendar weeks without a lighter/untrained week
    case highACWR             // ACWR ≥ 1.4

    /// `overdue` is a modifier: it only adds urgency when a primary trigger is
    /// present, or fires on its own after a very long stretch with rising load.
    public var isPrimary: Bool { self != .overdue }

    public var displayName: String {
        switch self {
        case .effortCreep: return "Effort creeping up"
        case .performanceDecline: return "Performance declining"
        case .overdue: return "Long time since a lighter week"
        case .highACWR: return "Load spiking above baseline"
        }
    }
}
