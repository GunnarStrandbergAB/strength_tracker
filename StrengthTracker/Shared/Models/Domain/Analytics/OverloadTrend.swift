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
    public let windowStart: Date?
    public let windowEnd: Date?
    public let slopeMargin: Double?
    public let observationCount: Int?
    public let meaningfulSlope: Double?
    public var recentWeeklyE1RMs: [WeeklyE1RM] {
        guard let end = windowEnd ?? weeklyE1RMs.last?.weekStart else { return [] }
        return weeklyE1RMs.filter { $0.weekStart >= (windowStart ?? end.addingTimeInterval(-11 * 7 * 86400)) && $0.weekStart <= end }
    }
    public var percentPerWeek: Double {
        guard let first = recentWeeklyE1RMs.first, first.e1rm > 0 else { return 0 }
        return slopePerWeek / first.e1rm * 100
    }
    public var statusLabel: String {
        switch trendStatus {
        case .progressing: return "Progressing"
        case .regressing: return "Declining"
        case .plateau: return "Maintaining"
        case .uncertain: return "Unclear"
        case .inactive: return "No recent exposure"
        }
    }

    public init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String,
        weeklyE1RMs: [WeeklyE1RM],
        slopePerWeek: Double,
        trendStatus: TrendStatus,
        overloadIndex: Double,
        windowStart: Date? = nil, windowEnd: Date? = nil, slopeMargin: Double? = nil,
        observationCount: Int? = nil, meaningfulSlope: Double? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.weeklyE1RMs = weeklyE1RMs
        self.slopePerWeek = slopePerWeek
        self.trendStatus = trendStatus
        self.overloadIndex = overloadIndex
        self.windowStart = windowStart; self.windowEnd = windowEnd
        self.slopeMargin = slopeMargin; self.observationCount = observationCount; self.meaningfulSlope = meaningfulSlope
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
    case progressing
    case plateau
    case regressing
    case uncertain
    case inactive
}
