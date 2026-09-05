import Foundation

/// Aggregate root for analytics read projections.
/// Groups all computed insights for a single analytics load,
/// ensuring consistent state (all insights from the same data snapshot).
/// Not Codable: this is a read-side aggregate assembled from service calls, not persisted.
public struct WorkoutInsights: Sendable {
    public let generatedAt: Date
    public let workoutCount: Int
    public let plateaus: [PlateauAnalysis]
    public let muscleBalance: MuscleBalance?
    public let recommendations: [ExerciseRecommendation]
    public let recoveryPatterns: [RecoveryPattern]
    public let optimalVolumes: [OptimalVolumeRange]

    // Advanced Insights (50+ workouts)
    public let trainingLoad: TrainingLoad?
    public let overloadTrends: [OverloadTrend]
    public let deloadRecommendation: DeloadRecommendation?
    public let trainingDrift: TrainingDrift?
    public let trainingPhase: TrainingPhaseDetection?
    public let blockComparison: BlockComparison?
    public let anomalies: [WorkoutAnomaly]
    public let highlights: [AnalyticsHighlight]
    public let archetypes: [WorkoutArchetype]
    public let trainingFingerprint: TrainingFingerprint?
    public let timeOfDayAnalysis: TimeOfDayAnalysis?
    /// The shared deload / hold / progress call (nil below the advanced-insights gate).
    public let verdict: TrainingVerdict?

    public var isActiveDeload: Bool { verdict?.isActiveDeload ?? false }

    public init(
        generatedAt: Date,
        workoutCount: Int,
        plateaus: [PlateauAnalysis],
        muscleBalance: MuscleBalance?,
        recommendations: [ExerciseRecommendation],
        recoveryPatterns: [RecoveryPattern],
        optimalVolumes: [OptimalVolumeRange],
        trainingLoad: TrainingLoad? = nil,
        overloadTrends: [OverloadTrend] = [],
        deloadRecommendation: DeloadRecommendation? = nil,
        trainingDrift: TrainingDrift? = nil,
        trainingPhase: TrainingPhaseDetection? = nil,
        blockComparison: BlockComparison? = nil,
        anomalies: [WorkoutAnomaly] = [],
        highlights: [AnalyticsHighlight] = [],
        archetypes: [WorkoutArchetype] = [],
        trainingFingerprint: TrainingFingerprint? = nil,
        timeOfDayAnalysis: TimeOfDayAnalysis? = nil,
        verdict: TrainingVerdict? = nil
    ) {
        self.generatedAt = generatedAt
        self.workoutCount = workoutCount
        self.plateaus = plateaus
        self.muscleBalance = muscleBalance
        self.recommendations = recommendations
        self.recoveryPatterns = recoveryPatterns
        self.optimalVolumes = optimalVolumes
        self.trainingLoad = trainingLoad
        self.overloadTrends = overloadTrends
        self.deloadRecommendation = deloadRecommendation
        self.trainingDrift = trainingDrift
        self.trainingPhase = trainingPhase
        self.blockComparison = blockComparison
        self.anomalies = anomalies
        self.highlights = highlights
        self.archetypes = archetypes
        self.trainingFingerprint = trainingFingerprint
        self.timeOfDayAnalysis = timeOfDayAnalysis
        self.verdict = verdict
    }

    /// Empty insights for initial state before data loads.
    public static let empty = WorkoutInsights(
        generatedAt: Date(),
        workoutCount: 0,
        plateaus: [],
        muscleBalance: nil,
        recommendations: [],
        recoveryPatterns: [],
        optimalVolumes: []
    )
}
