import Foundation

public struct TrainingFingerprint: Sendable {
    public let archetypeDistribution: [String: Double]
    public let entropy: Double
    public let stabilityScore: Double
    public let varietyTrend: TrendStatus
    public let consecutiveSimilarity: Double

    public init(
        archetypeDistribution: [String: Double],
        entropy: Double,
        stabilityScore: Double,
        varietyTrend: TrendStatus,
        consecutiveSimilarity: Double
    ) {
        self.archetypeDistribution = archetypeDistribution
        self.entropy = entropy
        self.stabilityScore = stabilityScore
        self.varietyTrend = varietyTrend
        self.consecutiveSimilarity = consecutiveSimilarity
    }
}
