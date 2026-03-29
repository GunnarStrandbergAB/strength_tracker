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

    /// Generate highlights from Phase 2/3 analytics when < 19 workouts.
    @MainActor
    func generateEarlyHighlights(
        plateaus: [PlateauAnalysis],
        muscleBalance: MuscleBalance?,
        recommendations: [ExerciseRecommendation],
        workoutCount: Int
    ) async -> [AnalyticsHighlight]

    /// Optionally enhance post-workout coaching bullets with natural language.
    @MainActor
    func enhancePostWorkoutBullets(_ bullets: [CoachingInsight]) async -> [CoachingInsight]
}

// Default empty/pass-through implementations so existing conformers don't break.
public extension InsightTextGenerating {
    @MainActor
    func generateEarlyHighlights(
        plateaus: [PlateauAnalysis],
        muscleBalance: MuscleBalance?,
        recommendations: [ExerciseRecommendation],
        workoutCount: Int
    ) async -> [AnalyticsHighlight] { [] }

    @MainActor
    func enhancePostWorkoutBullets(_ bullets: [CoachingInsight]) async -> [CoachingInsight] { bullets }
}
