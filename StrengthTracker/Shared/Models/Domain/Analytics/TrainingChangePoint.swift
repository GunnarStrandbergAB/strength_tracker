import Foundation

public struct TrainingChangePoint: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let workoutIndex: Int
    public let description: String
    public let keyDimensionShifts: [DimensionDrift]

    public init(id: UUID = UUID(), date: Date, workoutIndex: Int, description: String, keyDimensionShifts: [DimensionDrift]) {
        self.id = id
        self.date = date
        self.workoutIndex = workoutIndex
        self.description = description
        self.keyDimensionShifts = keyDimensionShifts
    }
}

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
