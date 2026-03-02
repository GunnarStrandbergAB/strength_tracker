import Foundation

/// Protocol for generating natural-language insight text from computed analytics data.
public protocol InsightTextGenerating: Sendable {
    /// Generate prioritized highlights from all computed analytics outputs.
    @MainActor
    func generateHighlights(
        trainingLoad: TrainingLoad?,
        overloadTrends: [OverloadTrend],
        deloadRecommendation: DeloadRecommendation?,
        trainingDrift: TrainingDrift?,
        trainingPhase: TrainingPhaseDetection?,
        recoveryPatterns: [RecoveryPattern],
        optimalVolumes: [OptimalVolumeRange]
    ) async -> [AnalyticsHighlight]

    /// Generate a summary comparing two training blocks.
    @MainActor
    func generateBlockSummary(dimensionDeltas: [DimensionDrift]) async -> String

    /// Explain training drift in user-friendly terms.
    @MainActor
    func generateDriftExplanation(drift: TrainingDrift) async -> String
}
