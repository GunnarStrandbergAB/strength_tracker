import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

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
        let cutoff = Calendar.mondayStart.date(byAdding: .month, value: -windowMonths, to: Date())!
        var bestE1RM: [UUID: Double] = [:]
        for past in workouts {
            guard past.id != excludingWorkoutId,
                  past.completedAt != nil,
                  (past.completedAt ?? past.startedAt) >= cutoff else { continue }
            for we in past.exercises {
                for set in we.sets {
                    guard set.isCompleted, set.setType != .warmup else { continue }
                    for part in set.effectiveParts {
                        guard let weight = part.weight, weight > 0,
                              let reps = part.reps, reps > 0 else { continue }
                        let e1rm = calculateOneRM(weight: weight, reps: min(reps, 15))
                        bestE1RM[we.exercise.id] = max(bestE1RM[we.exercise.id] ?? 0, e1rm)
                    }
                }
            }
        }
        return bestE1RM
    }

    // MARK: - Set IWV (Intensity-Weighted Volume)

    /// Compute IWV for a single set, optionally modulated by RPE.
    /// When RPE is available: IWV = reps * pct1RM * (RPE / 10.0)
    /// When RPE is not available: IWV = reps * pct1RM (unchanged)
    public static func setIWV(reps: Int, pct1RM: Double, rpe: Double?) -> Double {
        let base = Double(reps) * pct1RM
        if let rpe, rpe > 0 {
            return base * (rpe / 10.0)
        }
        return base
    }

    /// Drop-aware IWV for a whole set: sums part-level IWV across `effectiveParts`
    /// (a plain set has one part; a grouped drop set contributes every segment).
    /// pct1RM = min(weight / bestE1RM, 1.5), falling back to 0.75 when no e1RM is
    /// known — identical to the historical per-set loops this replaces.
    /// Returns 0 for incomplete or warmup sets.
    public static func setIWV(for set: ExerciseSet, bestE1RM: Double?) -> Double {
        guard set.isCompleted, set.setType != .warmup else { return 0 }
        return set.effectiveParts.reduce(0) { sum, part in
            guard let weight = part.weight, weight > 0,
                  let reps = part.reps, reps > 0 else { return sum }
            let pct1RM: Double
            if let best = bestE1RM, best > 0 {
                pct1RM = min(weight / best, 1.5)
            } else {
                pct1RM = 0.75
            }
            return sum + setIWV(reps: reps, pct1RM: pct1RM, rpe: part.rpe)
        }
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

    // MARK: - Time Windows

    /// Canonical analysis windows shared across analytics services so "recent"
    /// means the same thing everywhere.
    public enum Windows {
        /// Acute training load window (ACWR numerator)
        public static let acuteLoadDays = 7
        /// Chronic training load window (ACWR denominator)
        public static let chronicLoadDays = 28
        /// Default lookback for volume landmarks / plateau analysis
        public static let recentWeeks = 4
        /// Lookback for current recovery state
        public static let recoveryLookbackWeeks = 2
    }

    // MARK: - Volume Attribution
    //
    // Two attribution policies, one per metric:
    // - kg-volume (muscle balance): 70% primary, 30% split across secondaries.
    // - hard-set credits (volume landmarks, recovery): 1.0 primary per set,
    //   0.5 per set split across secondaries (MEV/MRV literature convention).
    // All services must go through these helpers so the policies can't drift.

    /// Attribute volume across primary (70%) and secondary (30% split) muscle groups.
    public static func attributeVolume(
        volume: Double,
        primaryMuscle: MuscleGroup,
        secondaryMuscles: [MuscleGroup]
    ) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        result[primaryMuscle] = volume * 0.7
        let secondaryCount = secondaryMuscles.count
        let secondaryShare = volume * 0.3 / Double(max(secondaryCount, 1))
        for muscle in secondaryMuscles {
            result[muscle, default: 0] += secondaryShare
        }
        return result
    }

    /// Attribute hard-set credits: primary muscle gets 1.0 per set, secondaries
    /// split 0.5 per set equally.
    public static func attributeHardSetCredits(
        hardSets: Int,
        primaryMuscle: MuscleGroup,
        secondaryMuscles: [MuscleGroup]
    ) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        result[primaryMuscle] = Double(hardSets)
        let secondaryCount = max(secondaryMuscles.count, 1)
        let creditPerSecondary = Double(hardSets) * 0.5 / Double(secondaryCount)
        for muscle in secondaryMuscles {
            result[muscle, default: 0] += creditPerSecondary
        }
        return result
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

    // MARK: - L2 Normalization

    /// L2 normalize a vector (unit length). Used by vectorizer and centroid computation.
    public static func l2Normalize(_ vector: [Double]) -> [Double] {
        #if canImport(Accelerate)
        var result = vector
        var magnitude: Double = 0.0
        vDSP_dotprD(vector, 1, vector, 1, &magnitude, vDSP_Length(vector.count))
        magnitude = sqrt(magnitude)
        if magnitude > 0 {
            var divisor = magnitude
            vDSP_vsdivD(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        }
        return result
        #else
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return magnitude > 0 ? vector.map { $0 / magnitude } : vector
        #endif
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
