import Foundation

/// Post-workout quality score based on volume, intensity, balance, and consistency.
public struct WorkoutQualityScore: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let workoutId: UUID
    public let overallScore: Double
    public let volumeScore: Double
    public let intensityScore: Double
    public let balanceScore: Double
    public let consistencyScore: Double
    public let scoredAt: Date

    public init(
        id: UUID = UUID(),
        workoutId: UUID,
        overallScore: Double,
        volumeScore: Double,
        intensityScore: Double,
        balanceScore: Double,
        consistencyScore: Double,
        scoredAt: Date = Date()
    ) {
        self.id = id
        self.workoutId = workoutId
        self.overallScore = overallScore
        self.volumeScore = volumeScore
        self.intensityScore = intensityScore
        self.balanceScore = balanceScore
        self.consistencyScore = consistencyScore
        self.scoredAt = scoredAt
    }
}
