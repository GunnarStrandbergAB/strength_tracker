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
        bodyWeightKg: Double,
        workouts: [Workout],
        bestE1RM: [UUID: Double],
        now: Date = Date()
    ) -> TrainingLoad? {
        let completed = workouts
            .filter { $0.completedAt != nil && $0.trainingDate <= now }
            .sorted { $0.trainingDate < $1.trainingDate }

        // Cold-start: require 8+ workouts spanning at least 14 calendar days
        guard completed.count >= 8,
              let firstDate = completed.first?.trainingDate,
              let lastDate = completed.last?.trainingDate,
              Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0 >= 14
        else { return nil }

        // Compute session loads
        let workoutLoads: [(workout: Workout, load: Double)] = completed.map { workout in
            (workout, computeSessionLoad(workout: workout, bestE1RM: bestE1RM, bodyWeightKg: bodyWeightKg))
        }

        // Build daily load array (rest days = 0)
        let dailyLoads = buildDailyLoads(workoutLoads: workoutLoads, now: now)
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
        let perMuscle = computePerMuscleGroupACWR(workouts: completed, bestE1RM: bestE1RM, bodyWeightKg: bodyWeightKg, now: now)

        let startDay = Calendar.current.startOfDay(for: firstDate)
        let history = dailyLoads.indices.suffix(56).map { index in
            TrainingLoad.Day(date: Calendar.current.date(byAdding: .day, value: index, to: startDay)!, recent: acuteEWMA[index], baseline: chronicEWMA[index])
        }
        return TrainingLoad(
            acuteLoad: acuteLoad,
            chronicLoad: chronicLoad,
            acwr: acwr,
            loadZone: loadZone,
            perMuscleGroupACWR: perMuscle, history: history
        )
    }

    // MARK: - Private

    /// Build a daily load array from first workout to today, with 0 for rest days.
    private static func buildDailyLoads(workoutLoads: [(workout: Workout, load: Double)], now: Date) -> [Double] {
        let calendar = Calendar.current
        guard let firstWorkout = workoutLoads.first else { return [] }

        let startDay = calendar.startOfDay(for: firstWorkout.workout.trainingDate)
        let endDay = calendar.startOfDay(for: now)
        guard let totalDays = calendar.dateComponents([.day], from: startDay, to: endDay).day else { return [] }
        let dayCount = totalDays + 1
        guard dayCount > 0 else { return [] }

        var dailyLoads = [Double](repeating: 0, count: dayCount)
        for (workout, load) in workoutLoads {
            let workoutDay = calendar.startOfDay(for: workout.trainingDate)
            if let dayIndex = calendar.dateComponents([.day], from: startDay, to: workoutDay).day,
               dayIndex >= 0, dayIndex < dayCount {
                dailyLoads[dayIndex] += load
            }
        }
        return dailyLoads
    }

    /// Session load = sum of IWV per working set (drop-set segments included),
    /// independent of optional RPE recording.
    private static func computeSessionLoad(workout: Workout, bestE1RM: [UUID: Double], bodyWeightKg: Double) -> Double {
        var load = 0.0
        for we in workout.exercises {
            let base = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
            for set in we.sets {
                load += AnalyticsCalculations.setIWV(for: set, bestE1RM: bestE1RM[we.exercise.id], baseLoadPerRep: base, modulateRPE: false)
            }
        }
        return load
    }

    /// Per-muscle ACWR using rolling sum (7d acute / 28d chronic÷4).
    /// Rolling sum is more appropriate than EWMA for muscles trained 1-2x/week.
    private static func computePerMuscleGroupACWR(
        workouts: [Workout],
        bestE1RM: [UUID: Double],
        bodyWeightKg: Double, now: Date
    ) -> [String: Double] {
        let calendar = Calendar.current
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -AnalyticsCalculations.Windows.acuteLoadDays, to: now),
              let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -AnalyticsCalculations.Windows.chronicLoadDays, to: now) else {
            return [:]
        }

        var acuteLoads: [String: Double] = [:]   // Last 7 days
        var chronicLoads: [String: Double] = [:]  // Last 28 days

        for workout in workouts {
            let workoutDate = workout.trainingDate

            for we in workout.exercises {
                var muscleLoad = 0.0
                let base = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                for set in we.sets {
                    muscleLoad += AnalyticsCalculations.setIWV(for: set, bestE1RM: bestE1RM[we.exercise.id], baseLoadPerRep: base, modulateRPE: false)
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
