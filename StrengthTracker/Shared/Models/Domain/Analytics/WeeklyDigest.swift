import Foundation

public struct WeeklyDigest: Sendable {
    public let weekStart: Date
    public let topInsight: CoachingInsight
    public let workoutsThisWeek: Int
    public let workoutsLastWeek: Int
    public let volumeDeltaPercent: Double
    public let qualityTrend: Double
    public let prsThisWeek: Int
    /// PRs set during the last complete week (the week the digest compares).
    public let prsLastWeek: Int

    public init(
        weekStart: Date,
        topInsight: CoachingInsight,
        workoutsThisWeek: Int,
        workoutsLastWeek: Int,
        volumeDeltaPercent: Double,
        qualityTrend: Double,
        prsThisWeek: Int,
        prsLastWeek: Int = 0
    ) {
        self.weekStart = weekStart
        self.topInsight = topInsight
        self.workoutsThisWeek = workoutsThisWeek
        self.workoutsLastWeek = workoutsLastWeek
        self.volumeDeltaPercent = volumeDeltaPercent
        self.qualityTrend = qualityTrend
        self.prsThisWeek = prsThisWeek
        self.prsLastWeek = prsLastWeek
    }
}
