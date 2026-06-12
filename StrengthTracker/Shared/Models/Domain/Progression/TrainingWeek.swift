import Foundation

/// A Monday-anchored calendar-week bucket of programmed sessions within a block.
///
/// Critical design note: programming (intensity/deload) is generated per microcycle and
/// stored on each session; weeks are derived calendar buckets of those dated sessions
/// (see `CalendarWeekBucketer`). A week's `isDeload` is true only when ALL of its
/// sessions are deload sessions — deload is a per-session truth.
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

    /// All sessions completed or skipped — the week no longer expects user action.
    public var allSessionsClosed: Bool {
        !sessions.isEmpty && sessions.allSatisfy { $0.isClosed }
    }

    /// True when any session in this week is a deload session (week may be a partial deload).
    public var containsDeloadSessions: Bool {
        sessions.contains { $0.isDeload }
    }

    /// Monday-anchored start of the calendar week containing this week's earliest session.
    public var weekStartDate: Date? {
        sessions.compactMap(\.scheduledDate).min().map { CalendarWeekBucketer.weekStart(of: $0) }
    }

    /// Span from the earliest to the latest scheduled session date in this week.
    public var dateRange: ClosedRange<Date>? {
        let dates = sessions.compactMap(\.scheduledDate)
        guard let min = dates.min(), let max = dates.max() else { return nil }
        return min...max
    }

    public var adherenceRate: Double {
        let today = Calendar.current.startOfDay(for: Date())
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let elapsed = sessions.filter { session in
            session.isSkipped || (session.scheduledDate ?? .distantPast) < endOfToday
        }
        guard !elapsed.isEmpty else { return 0 }
        return Double(completedSessions) / Double(elapsed.count)
    }
}
