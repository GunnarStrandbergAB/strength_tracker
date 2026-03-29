import Foundation

public struct AdherenceAnalysis: Sendable {
    public let weeklyFrequency: Double
    public let frequencyTrend: TrendStatus
    public let mostCommonDays: [Int]       // 1=Mon..7=Sun
    public let averageGapDays: Double
    public let currentGapDays: Int
    public let longestStreak: Int
    public let currentStreak: Int
    public let dropoutRisk: DropoutRisk
    public let expectedNextDate: Date?
    public let scheduleSummary: String

    public init(
        weeklyFrequency: Double,
        frequencyTrend: TrendStatus,
        mostCommonDays: [Int],
        averageGapDays: Double,
        currentGapDays: Int,
        longestStreak: Int,
        currentStreak: Int,
        dropoutRisk: DropoutRisk,
        expectedNextDate: Date?,
        scheduleSummary: String
    ) {
        self.weeklyFrequency = weeklyFrequency
        self.frequencyTrend = frequencyTrend
        self.mostCommonDays = mostCommonDays
        self.averageGapDays = averageGapDays
        self.currentGapDays = currentGapDays
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
        self.dropoutRisk = dropoutRisk
        self.expectedNextDate = expectedNextDate
        self.scheduleSummary = scheduleSummary
    }
}

public enum DropoutRisk: String, Sendable, Codable {
    case low, moderate, high
}
