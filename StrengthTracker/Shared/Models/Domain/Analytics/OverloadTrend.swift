import Foundation

/// Progressive overload tracking for a single exercise.
public struct OverloadTrend: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let exerciseId: UUID
    public let exerciseName: String
    public let weeklyE1RMs: [WeeklyE1RM]
    public let slopePerWeek: Double
    public let trendStatus: TrendStatus
    public let overloadIndex: Double

    public init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String,
        weeklyE1RMs: [WeeklyE1RM],
        slopePerWeek: Double,
        trendStatus: TrendStatus,
        overloadIndex: Double
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.weeklyE1RMs = weeklyE1RMs
        self.slopePerWeek = slopePerWeek
        self.trendStatus = trendStatus
        self.overloadIndex = overloadIndex
    }
}

/// Best e1RM value for a calendar week.
public struct WeeklyE1RM: Hashable, Sendable, Codable {
    public let weekStart: Date
    public let e1rm: Double

    public init(weekStart: Date, e1rm: Double) {
        self.weekStart = weekStart
        self.e1rm = e1rm
    }
}

/// Progressive overload trend classification.
public enum TrendStatus: String, Codable, Sendable {
    case progressing  // slope > 0.5 kg/wk
    case plateau      // -0.5 to 0.5 kg/wk
    case regressing   // slope < -0.5 kg/wk
}
