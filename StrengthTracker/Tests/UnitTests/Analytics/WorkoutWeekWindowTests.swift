import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("WorkoutWeekWindow")
struct WorkoutWeekWindowTests {

    /// A fixed calendar so week boundaries don't depend on the machine's locale/zone.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func workout(start: Date, durationHours: Double = 1) -> Workout {
        AnalyticsTestHelpers.makeWorkout(startedAt: start, completedAt: start.addingTimeInterval(durationHours * 3600))
    }

    @Test("A session started Sunday 23:30 and finished Monday belongs to Sunday's week")
    func sundayNightSession() {
        // 2026-09-06 is a Sunday; 2026-09-07 a Monday.
        let sunday = workout(start: date(2026, 9, 6, 23, 30))
        let split = WorkoutWeekWindow.split([sunday], now: date(2026, 9, 8), calendar: calendar)
        #expect(split.current.isEmpty)
        #expect(split.previous.count == 1)
    }

    @Test("Monday 00:00 is the first moment of the new week")
    func mondayBoundary() {
        let lateSunday = workout(start: date(2026, 9, 6, 23, 59))
        let earlyMonday = workout(start: date(2026, 9, 7, 0, 0))
        let split = WorkoutWeekWindow.split([lateSunday, earlyMonday], now: date(2026, 9, 9), calendar: calendar)
        #expect(split.current.count == 1)
        #expect(split.previous.count == 1)
    }

    @Test("Incomplete workouts never count")
    func incompleteExcluded() {
        var active = workout(start: date(2026, 9, 8))
        active.completedAt = nil
        let split = WorkoutWeekWindow.split([active], now: date(2026, 9, 9), calendar: calendar)
        #expect(split.current.isEmpty)
    }

    @Test("Weekly counts span a year boundary without colliding week numbers")
    func yearBoundaryCounts() {
        // Week of 2025-12-29 (ISO week 1 of 2026) and week of 2026-01-05.
        let workouts = [
            workout(start: date(2025, 12, 30)),
            workout(start: date(2026, 1, 1)),
            workout(start: date(2026, 1, 6))
        ]
        let counts = WorkoutWeekWindow.weeklyCounts(workouts, weeks: 3, now: date(2026, 1, 7), calendar: calendar)
        #expect(counts.map(\.count) == [0, 2, 1])
    }

    @Test("Streak counts consecutive trained weeks and survives an open current week")
    func streaks() {
        let workouts = [
            workout(start: date(2026, 8, 18)),   // week of Aug 17
            workout(start: date(2026, 8, 26)),   // week of Aug 24
            workout(start: date(2026, 9, 2))     // week of Aug 31
        ]
        // Now = Tuesday Sep 8, current week (Sep 7) has no session yet → streak still 3.
        #expect(WorkoutWeekWindow.consecutiveWeeksTrained(workouts, now: date(2026, 9, 8), calendar: calendar) == 3)
        // A session this week extends it to 4.
        let extended = workouts + [workout(start: date(2026, 9, 8))]
        #expect(WorkoutWeekWindow.consecutiveWeeksTrained(extended, now: date(2026, 9, 8), calendar: calendar) == 4)
        // Two weeks of silence break it.
        #expect(WorkoutWeekWindow.consecutiveWeeksTrained(workouts, now: date(2026, 9, 22), calendar: calendar) == 0)
        // Longest run in history is unaffected by "now".
        #expect(WorkoutWeekWindow.longestWeeklyStreak(workouts, calendar: calendar) == 3)
    }
}
