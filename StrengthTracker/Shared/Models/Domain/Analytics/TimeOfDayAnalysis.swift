import Foundation

public struct TimeOfDayAnalysis: Sendable {
    public let bestWindow: String
    public let bestAvgQuality: Double
    public let worstWindow: String
    public let worstAvgQuality: Double
    public let message: String

    public init(bestWindow: String, bestAvgQuality: Double, worstWindow: String, worstAvgQuality: Double, message: String) {
        self.bestWindow = bestWindow
        self.bestAvgQuality = bestAvgQuality
        self.worstWindow = worstWindow
        self.worstAvgQuality = worstAvgQuality
        self.message = message
    }
}
