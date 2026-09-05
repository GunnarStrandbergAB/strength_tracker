import Foundation

@MainActor
public final class AdherenceAnalysisService: Sendable {
    public init() {}

    public func analyze(workouts: [Workout]) -> AdherenceAnalysis {
        let completed = workouts.filter { $0.completedAt != nil }
            .sorted { $0.trainingDate < $1.trainingDate }

        // Weekly frequency over the last 8 Monday-start weeks, keyed by week-start
        // date (a `.weekOfYear` integer collides across years).
        let calendar = Calendar.mondayStart
        let now = Date()
        let eightWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -8, to: now)!
        let recent = completed.filter { $0.trainingDate >= eightWeeksAgo }

        var weekCounts: [Date: Int] = [:]
        for w in recent {
            weekCounts[calendar.weekStart(for: w.trainingDate), default: 0] += 1
        }
        let weeklyFrequency = weekCounts.isEmpty ? 0 : Double(weekCounts.values.reduce(0, +)) / Double(max(weekCounts.count, 1))

        // Frequency trend via linear regression on weekly counts
        let sortedWeeks = weekCounts.keys.sorted()
        let xs = sortedWeeks.indices.map { Double($0) }
        let ys = sortedWeeks.map { Double(weekCounts[$0] ?? 0) }
        let trend: TrendStatus
        if let reg = AnalyticsCalculations.linearRegression(xs: xs, ys: ys) {
            trend = reg.slope > 0.2 ? .progressing : (reg.slope < -0.2 ? .regressing : .plateau)
        } else {
            trend = .plateau
        }

        // Most common days of week (1=Sun..7=Sat in Calendar, remap to 1=Mon..7=Sun)
        var dayCounts: [Int: Int] = [:]
        for w in completed {
            let weekday = calendar.component(.weekday, from: w.startedAt) // 1=Sun..7=Sat
            let mapped = weekday == 1 ? 7 : weekday - 1 // remap to 1=Mon..7=Sun
            dayCounts[mapped, default: 0] += 1
        }
        let mostCommonDays = dayCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        // Gap analysis (by training date)
        let dates = completed.map(\.trainingDate).sorted()
        var gaps: [Double] = []
        // indices.dropFirst() — `1..<dates.count` traps on an empty history
        for i in dates.indices.dropFirst() {
            gaps.append(dates[i].timeIntervalSince(dates[i - 1]) / 86400)
        }
        let avgGap = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        let currentGap: Int
        if let last = dates.last {
            currentGap = Int(now.timeIntervalSince(last) / 86400)
        } else {
            currentGap = 0
        }

        // Streaks: consecutive Monday-start weeks with 1+ workout (shared definition).
        let maxStreak = WorkoutWeekWindow.longestWeeklyStreak(completed, calendar: calendar)
        let currentStreak = WorkoutWeekWindow.consecutiveWeeksTrained(completed, now: now, calendar: calendar)

        // Dropout risk
        let gapStdDev: Double
        if gaps.count >= 3 {
            let variance = gaps.map { pow($0 - avgGap, 2) }.reduce(0, +) / Double(gaps.count)
            gapStdDev = sqrt(variance)
        } else {
            gapStdDev = avgGap * 0.5
        }

        let dropoutRisk: DropoutRisk
        if Double(currentGap) > avgGap + 2 * gapStdDev && trend == .regressing {
            dropoutRisk = .high
        } else if Double(currentGap) > avgGap + gapStdDev {
            dropoutRisk = .moderate
        } else {
            dropoutRisk = .low
        }

        // Expected next workout
        let expectedNextDate: Date?
        if let nextDay = mostCommonDays.first {
            var comps = DateComponents()
            comps.weekday = nextDay == 7 ? 1 : nextDay + 1 // remap back
            expectedNextDate = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
        } else if avgGap > 0 {
            expectedNextDate = dates.last.map { calendar.date(byAdding: .day, value: Int(avgGap), to: $0) } ?? nil
        } else {
            expectedNextDate = nil
        }

        // Schedule summary
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let commonDayNames = mostCommonDays.prefix(3).map { dayNames[min($0 - 1, 6)] }
        let scheduleSummary: String
        if commonDayNames.isEmpty {
            scheduleSummary = "No regular pattern detected"
        } else {
            scheduleSummary = "You typically train \(commonDayNames.joined(separator: ", "))"
        }

        return AdherenceAnalysis(
            weeklyFrequency: weeklyFrequency,
            frequencyTrend: trend,
            mostCommonDays: mostCommonDays,
            averageGapDays: avgGap,
            currentGapDays: currentGap,
            longestStreak: maxStreak,
            currentStreak: currentStreak,
            dropoutRisk: dropoutRisk,
            expectedNextDate: expectedNextDate,
            scheduleSummary: scheduleSummary
        )
    }
}
