import Foundation

public struct MuscleNeglectWarning: Sendable {
    public let muscleGroup: String
    public let weeksDecline: Int
    public let currentWeeklySets: Double
    public let baselineWeeklySets: Double
    public let percentDecline: Double
    public let message: String

    public init(
        muscleGroup: String,
        weeksDecline: Int,
        currentWeeklySets: Double,
        baselineWeeklySets: Double,
        percentDecline: Double,
        message: String
    ) {
        self.muscleGroup = muscleGroup
        self.weeksDecline = weeksDecline
        self.currentWeeklySets = currentWeeklySets
        self.baselineWeeklySets = baselineWeeklySets
        self.percentDecline = percentDecline
        self.message = message
    }
}
