import Foundation

/// Tracks progressive overload by analyzing per-exercise e1RM trends over time.
/// Stateless: takes workouts as parameter.
public enum OverloadTrackingService {

    /// Compute overload trends for all exercises with sufficient history (4+ weeks).
    public static func computeOverloadTrends(workouts: [Workout], bodyWeightKg: Double, now: Date = Date(), windowWeeks: Int = 12) -> [OverloadTrend] {
        let completed = workouts.filter { $0.completedAt != nil && !$0.isDeload && $0.trainingDate <= now }
        guard !completed.isEmpty else { return [] }

        // Group best e1RM per exercise per calendar week
        let calendar = Calendar.mondayStart
        var exerciseWeeklyE1RMs: [UUID: [(weekStart: Date, e1rm: Double)]] = [:]
        var exerciseWeights: [UUID: Set<Double>] = [:]
        var exerciseNames: [UUID: String] = [:]

        for workout in completed {
            let weekStart = calendar.weekStart(for: workout.trainingDate)

            for we in workout.exercises {
                exerciseNames[we.exercise.id] = we.exercise.name
                for set in we.sets where set.isCompleted && set.setType != .warmup {
                    if let weight = set.weight, weight > 0 { exerciseWeights[we.exercise.id, default: []].insert(weight) }
                }
                let baseLoad = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                guard let bestE1RM = AnalyticsCalculations.bestE1RM(in: we.sets, baseLoadPerRep: baseLoad), bestE1RM > 0 else { continue }

                var entries = exerciseWeeklyE1RMs[we.exercise.id] ?? []
                if let existing = entries.firstIndex(where: { $0.weekStart == weekStart }) {
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
            let cutoff = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: now)!
            let recent = sorted.filter { $0.weekStart >= cutoff }
            let fitting = recent.count >= 4 ? recent : sorted
            let start = fitting[0].weekStart
            let xs = fitting.map { $0.weekStart.timeIntervalSince(start) / (7 * 86400) }
            let ys = fitting.map { $0.e1rm }

            guard let regression = AnalyticsCalculations.linearRegression(xs: xs, ys: ys) else { continue }

            let mean = ys.reduce(0, +) / Double(ys.count)
            let meanX = xs.reduce(0, +) / Double(xs.count)
            let sxx = xs.reduce(0) { $0 + pow($1 - meanX, 2) }
            let residual = zip(xs, ys).reduce(0) { $0 + pow($1.1 - (regression.intercept + regression.slope * $1.0), 2) }
            let se = sqrt(residual / Double(max(ys.count - 2, 1)) / max(sxx, 0.001))
            // Relative practical floor and uncertainty; neither assumes a universal kg gain.
            let weights = (exerciseWeights[exerciseId] ?? []).sorted()
            let increments = zip(weights, weights.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
            // Observed loading resolution, bounded to avoid treating sparse history as equipment calibration.
            let resolution = min(increments.min() ?? 0, mean * 0.02)
            let floor = max(mean * 0.001, resolution / Double(max(windowWeeks, 1)))
            let margin = max(floor, 2.5 * se)
            let latest = sorted.last!.weekStart
            let status: TrendStatus
            if now.timeIntervalSince(latest) > 21 * 86400 {
                status = .inactive
            } else if recent.count < 4 {
                status = .uncertain
            } else if regression.slope > margin {
                status = .progressing
            } else if regression.slope < -margin {
                status = .regressing
            } else if abs(regression.slope) + 2.5 * se <= floor {
                status = .plateau
            } else {
                status = .uncertain
            }

            let weeklyE1RMs = sorted.map { WeeklyE1RM(weekStart: $0.weekStart, e1rm: $0.e1rm) }
            let overloadIndex = regression.rSquared * (regression.slope > 0 ? 1.0 : -1.0)

            trends.append(OverloadTrend(
                exerciseId: exerciseId,
                exerciseName: exerciseNames[exerciseId] ?? "Unknown",
                weeklyE1RMs: weeklyE1RMs,
                slopePerWeek: regression.slope,
                trendStatus: status,
                overloadIndex: overloadIndex, windowStart: cutoff, windowEnd: now,
                slopeMargin: 2.5 * se, observationCount: recent.count, meaningfulSlope: floor
            ))
        }

        return trends.sorted { abs($0.percentPerWeek) > abs($1.percentPerWeek) }
    }
}
