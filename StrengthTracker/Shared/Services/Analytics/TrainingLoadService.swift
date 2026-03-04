import Foundation

/// Computes acute/chronic training load and ACWR using EWMA.
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

        guard completed.count >= 4 else { return nil }

        // Compute session loads
        let sessionLoads = completed.map { workout in
            computeSessionLoad(workout: workout, bestE1RM: bestE1RM)
        }

        // EWMA: acute (lambda=0.25), chronic (lambda=0.069)
        let acuteEWMA = AnalyticsCalculations.ewma(values: sessionLoads, lambda: 0.25)
        let chronicEWMA = AnalyticsCalculations.ewma(values: sessionLoads, lambda: 0.069)

        guard let acuteLoad = acuteEWMA.last,
              let chronicLoad = chronicEWMA.last,
              chronicLoad > 0 else { return nil }

        let acwr = acuteLoad / chronicLoad
        let loadZone = LoadZone.from(acwr: acwr)

        // Per-muscle-group ACWR
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

    /// ACWR per muscle group (top-level muscles only).
    private static func computePerMuscleGroupACWR(
        workouts: [Workout],
        bestE1RM: [UUID: Double]
    ) -> [String: Double] {
        var muscleSessionLoads: [String: [Double]] = [:]

        for workout in workouts {
            var muscleLoad: [String: Double] = [:]
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
                    let setIWV = AnalyticsCalculations.setIWV(reps: reps, pct1RM: pct1RM, rpe: set.rpe)
                    muscleLoad[we.exercise.primaryMuscleGroup.rawValue, default: 0] += setIWV
                }
            }

            for (muscle, load) in muscleLoad {
                muscleSessionLoads[muscle, default: []].append(load)
            }
        }

        var perMuscleACWR: [String: Double] = [:]
        for (muscle, loads) in muscleSessionLoads {
            guard loads.count >= 4 else { continue }
            let acute = AnalyticsCalculations.ewma(values: loads, lambda: 0.25)
            let chronic = AnalyticsCalculations.ewma(values: loads, lambda: 0.069)
            if let a = acute.last, let c = chronic.last, c > 0 {
                perMuscleACWR[muscle] = a / c
            }
        }

        return perMuscleACWR
    }
}
