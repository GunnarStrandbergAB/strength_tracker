import Foundation

/// Computes acute/chronic training load and ACWR using daily EWMA.
/// Stateless: takes workouts and best e1RM map as parameters.
public enum TrainingLoadService {

    /// Compute training load from workout history.
    /// - Parameters:
    ///   - workouts: All completed workouts sorted by date (oldest first)
    ///   - bestE1RM: Per-exercise best estimated 1RM
    /// - Returns: Training load with ACWR, or nil if insufficient data
    public static func computeTrainingLoad(
        workouts: [Workout],
        bestE1RM: [UUID: Double]
    ) -> TrainingLoad? {
        let completed = workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }

        // Cold-start: require 8+ workouts spanning at least 14 calendar days
        guard completed.count >= 8,
              let firstDate = completed.first?.completedAt ?? completed.first?.startedAt,
              let lastDate = completed.last?.completedAt ?? completed.last?.startedAt,
              Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0 >= 14
        else { return nil }

        // Compute session loads
        let workoutLoads: [(workout: Workout, load: Double)] = completed.map { workout in
            (workout, computeSessionLoad(workout: workout, bestE1RM: bestE1RM))
        }

        // Build daily load array (rest days = 0)
        let dailyLoads = buildDailyLoads(workoutLoads: workoutLoads)
        guard !dailyLoads.isEmpty else { return nil }

        // EWMA on daily array: acute (lambda=0.25), chronic (lambda=0.069)
        let acuteEWMA = AnalyticsCalculations.ewma(values: dailyLoads, lambda: 0.25)
        let chronicEWMA = AnalyticsCalculations.ewma(values: dailyLoads, lambda: 0.069)

        guard let acuteLoad = acuteEWMA.last,
              let chronicLoad = chronicEWMA.last,
              chronicLoad > 0 else { return nil }

        let acwr = acuteLoad / chronicLoad
        let loadZone = LoadZone.from(acwr: acwr)

        // Per-muscle-group ACWR (rolling sum method for sparse per-muscle data)
        let perMuscle = computePerMuscleGroupACWR(workouts: completed, bestE1RM: bestE1RM)

        return TrainingLoad(
            acuteLoad: acuteLoad,
            chronicLoad: chronicLoad,
            acwr: acwr,
            loadZone: loadZone,
            perMuscleGroupACWR: perMuscle
        )
    }

    // MARK: - Private

    /// Build a daily load array from first workout to today, with 0 for rest days.
    private static func buildDailyLoads(workoutLoads: [(workout: Workout, load: Double)]) -> [Double] {
        let calendar = Calendar.current
        guard let firstWorkout = workoutLoads.first else { return [] }

        let startDay = calendar.startOfDay(for: firstWorkout.workout.completedAt ?? firstWorkout.workout.startedAt)
        let endDay = calendar.startOfDay(for: Date())
        guard let totalDays = calendar.dateComponents([.day], from: startDay, to: endDay).day else { return [] }
        let dayCount = totalDays + 1
        guard dayCount > 0 else { return [] }

        var dailyLoads = [Double](repeating: 0, count: dayCount)
        for (workout, load) in workoutLoads {
            let workoutDay = calendar.startOfDay(for: workout.completedAt ?? workout.startedAt)
            if let dayIndex = calendar.dateComponents([.day], from: startDay, to: workoutDay).day,
               dayIndex >= 0, dayIndex < dayCount {
                dailyLoads[dayIndex] += load
            }
        }
        return dailyLoads
    }

    /// Session load = sum of IWV per working set, optionally RPE-modulated.
    private static func computeSessionLoad(workout: Workout, bestE1RM: [UUID: Double]) -> Double {
        var load = 0.0
        for we in workout.exercises {
            for set in we.sets {
                guard set.isCompleted, set.setType != .warmup,
                      let weight = set.weight, weight > 0,
                      let reps = set.reps, reps > 0 else { continue }

                let pct1RM: Double
                if let best = bestE1RM[we.exercise.id], best > 0 {
                    pct1RM = min(weight / best, 1.5)
                } else {
                    pct1RM = 0.75
                }
                load += AnalyticsCalculations.setIWV(reps: reps, pct1RM: pct1RM, rpe: set.rpe)
            }
        }
        return load
    }

    /// Per-muscle ACWR using rolling sum (7d acute / 28d chronic÷4).
    /// Rolling sum is more appropriate than EWMA for muscles trained 1-2x/week.
    private static func computePerMuscleGroupACWR(
        workouts: [Workout],
        bestE1RM: [UUID: Double]
    ) -> [String: Double] {
        let now = Date()
        let calendar = Calendar.current
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: now) else {
            return [:]
        }

        var acuteLoads: [String: Double] = [:]   // Last 7 days
        var chronicLoads: [String: Double] = [:]  // Last 28 days

        for workout in workouts {
            let workoutDate = workout.completedAt ?? workout.startedAt

            for we in workout.exercises {
                var muscleLoad = 0.0
                for set in we.sets {
                    guard set.isCompleted, set.setType != .warmup,
                          let weight = set.weight, weight > 0,
                          let reps = set.reps, reps > 0 else { continue }

                    let pct1RM: Double
                    if let best = bestE1RM[we.exercise.id], best > 0 {
                        pct1RM = min(weight / best, 1.5)
                    } else {
                        pct1RM = 0.75
                    }
                    muscleLoad += AnalyticsCalculations.setIWV(reps: reps, pct1RM: pct1RM, rpe: set.rpe)
                }

                let muscle = we.exercise.primaryMuscleGroup.rawValue

                if workoutDate >= twentyEightDaysAgo {
                    chronicLoads[muscle, default: 0] += muscleLoad
                }
                if workoutDate >= sevenDaysAgo {
                    acuteLoads[muscle, default: 0] += muscleLoad
                }
            }
        }

        var perMuscleACWR: [String: Double] = [:]
        for (muscle, chronic28d) in chronicLoads {
            let chronicWeekly = chronic28d / 4.0
            guard chronicWeekly > 0 else { continue }
            let acute7d = acuteLoads[muscle] ?? 0
            perMuscleACWR[muscle] = acute7d / chronicWeekly
        }

        return perMuscleACWR
    }
}
