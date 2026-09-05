import Foundation

/// A single coaching insight surfaced to the user at the right moment.
public struct CoachingInsight: Identifiable, Sendable {
    public let id: UUID
    public let priority: Int              // lower = more important
    public let title: String
    public let detail: String
    public let icon: String               // SF Symbol name
    public let color: CoachingColor
    public let source: InsightSource

    public init(
        id: UUID = UUID(),
        priority: Int,
        title: String,
        detail: String,
        icon: String,
        color: CoachingColor,
        source: InsightSource
    ) {
        self.id = id
        self.priority = priority
        self.title = title
        self.detail = detail
        self.icon = icon
        self.color = color
        self.source = source
    }
}

/// Color category for coaching insights, mapped to design system colors in views.
public enum CoachingColor: String, Sendable {
    case primary      // STColors.primary (gold)
    case success      // STColors.success (green)
    case warning      // orange / caution
    case danger       // STColors.danger (red)
    case info         // STColors.textSecondary (neutral)
}

/// Per-exercise coaching data cached in WorkoutViewModel for inline display.
public struct ExerciseCoachingData: Sendable {
    public let suggestions: [Int: WeightSuggestion]  // setIndex → suggestion
    public let effortCreepWarning: EffortCreepWarning?
    /// "Chest is still recovering, ready Thursday" — only when the group is
    /// fatigued and was not just trained.
    public let recoveryNote: String?

    public init(
        suggestions: [Int: WeightSuggestion] = [:],
        effortCreepWarning: EffortCreepWarning? = nil,
        recoveryNote: String? = nil
    ) {
        self.suggestions = suggestions
        self.effortCreepWarning = effortCreepWarning
        self.recoveryNote = recoveryNote
    }
}


/// Where this coaching insight was derived from.
public enum InsightSource: String, Sendable {
    case personalRecord
    case qualityScore
    case effortCreep
    case overloadTrend
    case volumeDelta
    case acwr
    case recovery
    case sessionComparison
    case adherence
    case plateau
    case muscleNeglect
    case trajectory
}
