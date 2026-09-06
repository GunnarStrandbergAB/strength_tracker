import Foundation

/// Analysis of muscle group balance and training distribution.
public struct MuscleBalance: Hashable, Sendable, Codable {
    public let analyzedAt: Date
    public let muscleGroupVolumes: [MuscleGroupVolume]
    public let imbalances: [MuscleImbalance]
    public let overallBalanceScore: Double

    public init(
        analyzedAt: Date,
        muscleGroupVolumes: [MuscleGroupVolume],
        imbalances: [MuscleImbalance],
        overallBalanceScore: Double
    ) {
        self.analyzedAt = analyzedAt
        self.muscleGroupVolumes = muscleGroupVolumes
        self.imbalances = imbalances
        self.overallBalanceScore = overallBalanceScore
    }
}

/// Volume data for a single muscle group over a weekly period.
public struct MuscleGroupVolume: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let muscleGroup: String
    public let weeklyVolume: Double
    public let weeklySetCount: Int
    public let trend: VolumeTrend
    public let directWeeklySets: Double?
    public let indirectWeeklySets: Double?

    public init(
        id: UUID = UUID(),
        muscleGroup: String,
        weeklyVolume: Double,
        weeklySetCount: Int,
        trend: VolumeTrend,
        directWeeklySets: Double? = nil, indirectWeeklySets: Double? = nil
    ) {
        self.id = id
        self.muscleGroup = muscleGroup
        self.weeklyVolume = weeklyVolume
        self.weeklySetCount = weeklySetCount
        self.trend = trend
        self.directWeeklySets = directWeeklySets
        self.indirectWeeklySets = indirectWeeklySets
    }
}

/// Trend direction for weekly volume.
public enum VolumeTrend: String, Codable, Sendable {
    case increasing
    case stable
    case decreasing
}

/// An imbalance detected between two muscle groups.
public struct MuscleImbalance: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let primaryGroup: String
    public let comparisonGroup: String
    public let ratio: Double
    public let severity: ImbalanceSeverity

    /// Business rule: recommendation derived from imbalance data.
    /// Computed properties are automatically excluded from Codable synthesis.
    public var recommendation: String {
        let ratioStr = AnalyticsFormatting.ratio(ratio)
        switch severity {
        case .severe:
            return "Significantly reduce \(primaryGroup) volume and increase \(comparisonGroup) by 30-40% (\(ratioStr))."
        case .moderate:
            return "Increase \(comparisonGroup) volume by 20-30% to balance \(primaryGroup) training (\(ratioStr))."
        case .mild:
            return "Consider adding 1-2 more sets for \(comparisonGroup) to improve balance with \(primaryGroup) (\(ratioStr))."
        }
    }

    public init(
        id: UUID = UUID(),
        primaryGroup: String,
        comparisonGroup: String,
        ratio: Double,
        severity: ImbalanceSeverity
    ) {
        self.id = id
        self.primaryGroup = primaryGroup
        self.comparisonGroup = comparisonGroup
        self.ratio = ratio
        self.severity = severity
    }
}

/// Severity level of a muscle imbalance.
public enum ImbalanceSeverity: String, Codable, Sendable {
    case mild
    case moderate
    case severe
}
