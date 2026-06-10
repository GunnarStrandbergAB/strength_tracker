import Foundation

/// Time-of-day workout quality analysis.
/// (The former CUSUM change-point detector was removed — it overlapped with the
/// wired PhaseDetectionService/TrainingDriftService and had no consumers.)
@MainActor
public final class ChangePointDetectionService: Sendable {

    public init() {}

    // MARK: - Time-of-Day Analysis (B5)

    public func analyzeTimeOfDay(
        workouts: [Workout],
        qualityScores: [UUID: WorkoutQualityScore]
    ) -> TimeOfDayAnalysis? {
        let scored = workouts.compactMap { workout -> (hour: Int, quality: Double)? in
            guard let score = qualityScores[workout.id] else { return nil }
            let hour = Calendar.current.component(.hour, from: workout.startedAt)
            return (hour, score.overallScore)
        }
        guard scored.count >= 10 else { return nil }

        // Group into windows
        let windows: [(name: String, range: ClosedRange<Int>)] = [
            ("Morning (6-11 AM)", 5...10),
            ("Afternoon (11 AM-5 PM)", 11...16),
            ("Evening (5-10 PM)", 17...21),
            ("Night (10 PM-6 AM)", 22...28) // 22-4 wraps
        ]

        var windowScores: [(name: String, avg: Double, count: Int)] = []
        for window in windows {
            let matching = scored.filter { entry in
                let h = entry.hour
                if window.range.upperBound > 23 {
                    return h >= window.range.lowerBound || h <= (window.range.upperBound - 24)
                }
                return window.range.contains(h)
            }
            if matching.count >= 3 {
                let avg = matching.map(\.quality).reduce(0, +) / Double(matching.count)
                windowScores.append((window.name, avg, matching.count))
            }
        }

        guard windowScores.count >= 2,
              let best = windowScores.max(by: { $0.avg < $1.avg }),
              let worst = windowScores.min(by: { $0.avg < $1.avg }),
              best.name != worst.name else { return nil }

        let delta = best.avg - worst.avg
        guard delta > 5 else { return nil } // Only report if >5% difference

        return TimeOfDayAnalysis(
            bestWindow: best.name,
            bestAvgQuality: best.avg,
            worstWindow: worst.name,
            worstAvgQuality: worst.avg,
            message: String(format: "Your %@ workouts average %.0f%% higher quality than %@",
                          best.name.lowercased(), delta, worst.name.lowercased())
        )
    }
}
