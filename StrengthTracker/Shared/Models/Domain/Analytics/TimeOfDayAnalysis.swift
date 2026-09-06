import Foundation

public struct TimeOfDayAnalysis: Sendable {
    public let bestWindow: String
    public let bestAvgQuality: Double
    public let worstWindow: String
    public let worstAvgQuality: Double
    public let message: String
    public let bestCount: Int
    public let worstCount: Int
    public let windowStart: Date?
    public let windowEnd: Date?

    public init(bestWindow: String, bestAvgQuality: Double, worstWindow: String, worstAvgQuality: Double, message: String, bestCount: Int = 0, worstCount: Int = 0, windowStart: Date? = nil, windowEnd: Date? = nil) {
        self.bestWindow = bestWindow
        self.bestAvgQuality = bestAvgQuality
        self.worstWindow = worstWindow
        self.worstAvgQuality = worstAvgQuality
        self.message = message
        self.bestCount = bestCount
        self.worstCount = worstCount
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}
