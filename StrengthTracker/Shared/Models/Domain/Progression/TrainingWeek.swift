import Foundation

/// A microcycle within a block.
///
/// Critical design note: Weeks are NOT pinned to calendar dates.
/// Progression is driven by session completion count, not by the calendar advancing.
public struct TrainingWeek: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var weekNumber: Int
    public var absoluteWeekNumber: Int
    public var sessions: [PlannedSession]
    public var isDeload: Bool
    public var isCompleted: Bool
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        weekNumber: Int,
        absoluteWeekNumber: Int,
        sessions: [PlannedSession] = [],
        isDeload: Bool = false,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.absoluteWeekNumber = absoluteWeekNumber
        self.sessions = sessions
        self.isDeload = isDeload
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    public var completedSessions: Int {
        sessions.filter { $0.completedWorkoutId != nil }.count
    }

    public var allSessionsCompleted: Bool {
        !sessions.isEmpty && sessions.allSatisfy { $0.isCompleted }
    }

    public var adherenceRate: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(completedSessions) / Double(sessions.count)
    }
}
