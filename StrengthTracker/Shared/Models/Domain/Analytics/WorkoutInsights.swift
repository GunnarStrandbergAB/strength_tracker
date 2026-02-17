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

    public init(
        generatedAt: Date,
        workoutCount: Int,
        plateaus: [PlateauAnalysis],
        muscleBalance: MuscleBalance?,
        recommendations: [ExerciseRecommendation],
        recoveryPatterns: [RecoveryPattern],
        optimalVolumes: [OptimalVolumeRange]
    ) {
        self.generatedAt = generatedAt
        self.workoutCount = workoutCount
        self.plateaus = plateaus
        self.muscleBalance = muscleBalance
        self.recommendations = recommendations
        self.recoveryPatterns = recoveryPatterns
        self.optimalVolumes = optimalVolumes
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
