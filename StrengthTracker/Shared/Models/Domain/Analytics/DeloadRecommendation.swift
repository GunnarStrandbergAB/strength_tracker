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
}

/// Individual signals that contribute to a deload recommendation.
public enum DeloadSignal: String, Codable, Sendable {
    case intensityCreep       // effort ratio increasing over 3+ sessions
    case performanceDecline   // e1RM dropping in 40%+ exercises
    case overdue              // >6 weeks since volume dropped <60%
    case highACWR             // ACWR > 1.4 sustained 2+ weeks
}
