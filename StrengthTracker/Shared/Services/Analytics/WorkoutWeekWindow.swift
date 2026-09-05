import Foundation

/// The ONE definition of "this week" for workouts: Monday-start calendar weeks
/// (`Calendar.mondayStart`), bucketed by `Workout.trainingDate` (= `startedAt`),
/// completed workouts only. Dashboard, widgets, digest, adherence and streaks all
/// go through here so their counts can never disagree.
public struct WorkoutWeekWindow: Sendable {
    public let current: [Workout]
    public let previous: [Workout]
    public let prior: [Workout]
    public let currentWeekStart: Date
    public let previousWeekStart: Date

    /// Splits completed workouts into the current, previous and prior weeks.
    public static func split(_ workouts: [Workout], now: Date = Date(), calendar: Calendar = .mondayStart) -> WorkoutWeekWindow {
        let currentStart = calendar.weekStart(for: now)
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentStart) ?? currentStart
        let priorStart = calendar.date(byAdding: .weekOfYear, value: -2, to: currentStart) ?? previousStart
        let completed = workouts.filter { $0.completedAt != nil }
        return WorkoutWeekWindow(
            current: completed.filter { $0.trainingDate >= currentStart },
            previous: completed.filter { $0.trainingDate >= previousStart && $0.trainingDate < currentStart },
            prior: completed.filter { $0.trainingDate >= priorStart && $0.trainingDate < previousStart },
            currentWeekStart: currentStart,
            previousWeekStart: previousStart
        )
    }

    /// Week-start dates (Monday) that hold at least one completed workout.
    public static func trainedWeekStarts(_ workouts: [Workout], calendar: Calendar = .mondayStart) -> Set<Date> {
        Set(workouts.filter { $0.completedAt != nil }.map { calendar.weekStart(for: $0.trainingDate) })
    }

    /// Consecutive Monday-start weeks (ending with the current week, or the
    /// previous one if the current week has no session yet) that each hold at
    /// least one completed workout. Lifters train a few times a week, so weeks —
    /// not days — are the unit that means anything.
    public static func consecutiveWeeksTrained(_ workouts: [Workout], now: Date = Date(), calendar: Calendar = .mondayStart) -> Int {
        let trained = trainedWeekStarts(workouts, calendar: calendar)
        guard !trained.isEmpty else { return 0 }
        var cursor = calendar.weekStart(for: now)
        if !trained.contains(cursor) {
            // The current week is still open; a streak survives until it ends.
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        var streak = 0
        while trained.contains(cursor) {
            streak += 1
            guard let earlier = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = earlier
        }
        return streak
    }

    /// Longest run of consecutive trained weeks anywhere in history.
    public static func longestWeeklyStreak(_ workouts: [Workout], calendar: Calendar = .mondayStart) -> Int {
        let trained = trainedWeekStarts(workouts, calendar: calendar).sorted()
        var best = 0, run = 0
        var previous: Date?
        for start in trained {
            if let previous, let expected = calendar.date(byAdding: .weekOfYear, value: 1, to: previous), expected == start {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = start
        }
        return best
    }

    /// Workouts per Monday-start week over the last `weeks` weeks (including the
    /// current one), keyed by week start. Weeks without training are present with 0.
    public static func weeklyCounts(_ workouts: [Workout], weeks: Int, now: Date = Date(), calendar: Calendar = .mondayStart) -> [(weekStart: Date, count: Int)] {
        let currentStart = calendar.weekStart(for: now)
        var counts: [Date: Int] = [:]
        for offset in 0..<max(weeks, 1) {
            if let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart) {
                counts[start] = 0
            }
        }
        for workout in workouts where workout.completedAt != nil {
            let start = calendar.weekStart(for: workout.trainingDate)
            if counts[start] != nil { counts[start, default: 0] += 1 }
        }
        return counts.keys.sorted().map { ($0, counts[$0] ?? 0) }
    }
}
