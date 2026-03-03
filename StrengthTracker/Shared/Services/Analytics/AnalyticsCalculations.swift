import Foundation

/// Shared static utility functions used across analytics services.
/// Extracted from WorkoutQualityScoreService for reuse in advanced insights.
public enum AnalyticsCalculations {

    // MARK: - Best e1RM Map

    /// Build per-exercise best estimated 1RM from historical workouts.
    /// - Parameters:
    ///   - excludingWorkoutId: Workout ID to exclude from the map (typically the current workout)
    ///   - workouts: All workout history
    ///   - windowMonths: How far back to look (default 6 months)
    /// - Returns: Dictionary mapping exercise ID to best e1RM
    public static func buildBestE1RMMap(
        excluding excludingWorkoutId: UUID? = nil,
        from workouts: [Workout],
        windowMonths: Int = 6
    ) -> [UUID: Double] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -windowMonths, to: Date())!
        var bestE1RM: [UUID: Double] = [:]
        for past in workouts {
            guard past.id != excludingWorkoutId,
                  past.completedAt != nil,
                  (past.completedAt ?? past.startedAt) >= cutoff else { continue }
            for we in past.exercises {
                for set in we.sets {
                    guard set.isCompleted,
                          set.setType != .warmup,
                          let weight = set.weight, weight > 0,
                          let reps = set.reps, reps > 0 else { continue }
                    let e1rm = calculateOneRM(weight: weight, reps: min(reps, 15))
                    bestE1RM[we.exercise.id] = max(bestE1RM[we.exercise.id] ?? 0, e1rm)
                }
            }
        }
        return bestE1RM
    }

    // MARK: - e1RM Calculation (nonisolated copy)

    /// Estimated 1RM using Brzycki formula — nonisolated mirror of
    /// `TrainingStatusDetector.calculateOneRM` for use in analytics services
    /// that run outside the main actor.
    public static func calculateOneRM(weight: Double, reps: Int) -> Double {
        if reps == 1 {
            return weight
        } else if reps <= 5 {
            return weight * (1.0 + Double(reps) / 30.0)
        } else {
            return weight * 36.0 / (37.0 - Double(reps))
        }
    }

    // MARK: - Linear Regression

    /// Simple ordinary least-squares linear regression.
    /// - Returns: (slope, intercept, rSquared) or nil if fewer than 2 points
    public static func linearRegression(xs: [Double], ys: [Double]) -> (slope: Double, intercept: Double, rSquared: Double)? {
        let n = Double(xs.count)
        guard xs.count >= 2, xs.count == ys.count else { return nil }

        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }

        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-12 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        // R-squared
        let meanY = sumY / n
        let ssTotal = ys.reduce(0) { $0 + ($1 - meanY) * ($1 - meanY) }
        let ssResidual = zip(xs, ys).reduce(0) { sum, pair in
            let predicted = slope * pair.0 + intercept
            return sum + (pair.1 - predicted) * (pair.1 - predicted)
        }
        let rSquared = ssTotal > 1e-12 ? 1.0 - ssResidual / ssTotal : 0.0

        return (slope, intercept, rSquared)
    }

    // MARK: - Exponentially Weighted Moving Average

    /// Compute EWMA over a time series.
    /// - Parameters:
    ///   - values: Ordered time series (oldest first)
    ///   - lambda: Smoothing factor (higher = more weight on recent values)
    /// - Returns: EWMA values of same length as input
    public static func ewma(values: [Double], lambda: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: values.count)
        result[0] = values[0]
        for i in 1..<values.count {
            result[i] = lambda * values[i] + (1.0 - lambda) * result[i - 1]
        }
        return result
    }
}
