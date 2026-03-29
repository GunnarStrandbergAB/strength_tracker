import Foundation

public struct ArchetypePrediction: Sendable {
    public let predictedLabel: String
    public let confidence: Double
    public let alternatives: [(label: String, probability: Double)]

    public init(predictedLabel: String, confidence: Double, alternatives: [(label: String, probability: Double)]) {
        self.predictedLabel = predictedLabel
        self.confidence = confidence
        self.alternatives = alternatives
    }
}

public struct WorkoutSuggestion: Sendable {
    public let suggestedArchetype: String
    public let reason: String
    public let overdueArchetype: String?
    public let overdueMessage: String?

    public init(suggestedArchetype: String, reason: String, overdueArchetype: String? = nil, overdueMessage: String? = nil) {
        self.suggestedArchetype = suggestedArchetype
        self.reason = reason
        self.overdueArchetype = overdueArchetype
        self.overdueMessage = overdueMessage
    }
}
