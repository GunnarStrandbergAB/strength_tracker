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
    public let provisionalReasons: [String]?
    public let baselineNotes: [String]?
    public let scoredModelVersion: Int?
    public var isProvisional: Bool { !(provisionalReasons ?? []).isEmpty }
    public static let modelVersion = 2

    public init(
        id: UUID = UUID(),
        workoutId: UUID,
        overallScore: Double,
        volumeScore: Double,
        intensityScore: Double,
        balanceScore: Double,
        consistencyScore: Double,
        scoredAt: Date = Date(),
        provisionalReasons: [String]? = nil, baselineNotes: [String]? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.overallScore = overallScore
        self.volumeScore = volumeScore
        self.intensityScore = intensityScore
        self.balanceScore = balanceScore
        self.consistencyScore = consistencyScore
        self.scoredAt = scoredAt
        self.provisionalReasons = provisionalReasons
        self.baselineNotes = baselineNotes
        self.scoredModelVersion = Self.modelVersion
    }
}

/// Aggregate quality score across multiple workouts, smoothed via EWMA.
public struct AggregateQualityScore: Sendable {
    /// 0-100 EWMA-smoothed overall quality
    public let ewmaOverall: Double
    /// 0-100 EWMA-smoothed volume pillar
    public let ewmaVolume: Double
    /// 0-100 EWMA-smoothed intensity pillar
    public let ewmaIntensity: Double
    /// 0-100 EWMA-smoothed balance pillar
    public let ewmaBalance: Double
    /// 0-100 EWMA-smoothed consistency pillar
    public let ewmaConsistency: Double
    /// Score-point change vs EWMA ~4 weeks ago
    public let trendVsPrior: Double
    /// 0-1 where current EWMA sits in user's EWMA history
    public let percentileRank: Double
    /// Number of workouts included in the calculation
    public let workoutsIncluded: Int
    /// When this aggregate was computed
    public let computedAt: Date
    public var provisional: Bool = false
    public var sessionsScored: Int = 0
}
