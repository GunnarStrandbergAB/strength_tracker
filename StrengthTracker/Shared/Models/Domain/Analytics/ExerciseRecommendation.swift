import Foundation

/// A recommended exercise based on training history and pattern analysis.
public struct ExerciseRecommendation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let exerciseId: UUID
    public let exerciseName: String
    public let reason: RecommendationReason
    public let confidence: Double
    public let basedOnWorkoutCount: Int
    public let targetMuscleGroup: String?

    public init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String,
        reason: RecommendationReason,
        confidence: Double,
        basedOnWorkoutCount: Int,
        targetMuscleGroup: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.reason = reason
        self.confidence = confidence
        self.basedOnWorkoutCount = basedOnWorkoutCount
        self.targetMuscleGroup = targetMuscleGroup
    }
}

/// The reason an exercise was recommended.
public enum RecommendationReason: String, Codable, Sendable {
    case similarToFavorites
    case fillsMuscleGap
    case plateauBreaker
    case recoveryAppropriate
}
