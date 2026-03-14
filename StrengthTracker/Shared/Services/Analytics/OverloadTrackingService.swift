import Foundation

/// Tracks progressive overload by analyzing per-exercise e1RM trends over time.
/// Stateless: takes workouts as parameter.
public enum OverloadTrackingService {

    /// Compute overload trends for all exercises with sufficient history (4+ weeks).
    public static func computeOverloadTrends(workouts: [Workout]) -> [OverloadTrend] {
        let completed = workouts.filter { $0.completedAt != nil }
        guard !completed.isEmpty else { return [] }

        // Group best e1RM per exercise per calendar week
        let calendar = Calendar.mondayStart
        var exerciseWeeklyE1RMs: [UUID: [(weekStart: Date, e1rm: Double)]] = [:]
        var exerciseNames: [UUID: String] = [:]

        for workout in completed {
            let workoutDate = workout.completedAt ?? workout.startedAt
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: workoutDate)?.start ?? workoutDate

            for we in workout.exercises {
                exerciseNames[we.exercise.id] = we.exercise.name
                var bestE1RM = 0.0
                for set in we.sets {
                    guard set.isCompleted, set.setType != .warmup,
                          let weight = set.weight, weight > 0,
                          let reps = set.reps, reps > 0 else { continue }
                    let e1rm = AnalyticsCalculations.calculateOneRM(weight: weight, reps: min(reps, 15))
                    bestE1RM = max(bestE1RM, e1rm)
                }
                guard bestE1RM > 0 else { continue }

                var entries = exerciseWeeklyE1RMs[we.exercise.id] ?? []
                if let existing = entries.firstIndex(where: { calendar.isDate($0.weekStart, equalTo: weekStart, toGranularity: .weekOfYear) }) {
                    entries[existing] = (weekStart, max(entries[existing].e1rm, bestE1RM))
                } else {
                    entries.append((weekStart, bestE1RM))
                }
                exerciseWeeklyE1RMs[we.exercise.id] = entries
            }
        }

        // Build trends for exercises with 4+ weeks of data
        var trends: [OverloadTrend] = []
        for (exerciseId, entries) in exerciseWeeklyE1RMs {
            guard entries.count >= 4 else { continue }

            let sorted = entries.sorted { $0.weekStart < $1.weekStart }
            let xs = sorted.enumerated().map { Double($0.offset) }
            let ys = sorted.map { $0.e1rm }

            guard let regression = AnalyticsCalculations.linearRegression(xs: xs, ys: ys) else { continue }

            let status: TrendStatus
            if regression.slope > 0.5 {
                status = .progressing
            } else if regression.slope < -0.5 {
                status = .regressing
            } else {
                status = .plateau
            }

            let weeklyE1RMs = sorted.map { WeeklyE1RM(weekStart: $0.weekStart, e1rm: $0.e1rm) }
            let overloadIndex = regression.rSquared * (regression.slope > 0 ? 1.0 : -1.0)

            trends.append(OverloadTrend(
                exerciseId: exerciseId,
                exerciseName: exerciseNames[exerciseId] ?? "Unknown",
                weeklyE1RMs: weeklyE1RMs,
                slopePerWeek: regression.slope,
                trendStatus: status,
                overloadIndex: overloadIndex
            ))
        }

        return trends.sorted { abs($0.slopePerWeek) > abs($1.slopePerWeek) }
    }
}
