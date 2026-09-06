import Foundation

@MainActor
public final class ChangePointDetectionService: Sendable {
    public init() {}
    public func analyzeTimeOfDay(workouts: [Workout], qualityScores: [UUID: WorkoutQualityScore], now: Date = Date()) -> TimeOfDayAnalysis? {
        struct Observation { let bucket: Int; let family: String; let score: Double }
        let cutoff = now.addingTimeInterval(-12 * 7 * 86400)
        let observations = workouts.compactMap { workout -> Observation? in
            guard workout.completedAt != nil, !workout.isDeload, workout.trainingDate >= cutoff, workout.trainingDate <= now,
                  let score = qualityScores[workout.id], !score.isProvisional else { return nil }
            let hour = Calendar.current.component(.hour, from: workout.trainingDate)
            let bucket = (6..<11).contains(hour) ? 0 : (11..<17).contains(hour) ? 1 : (17..<22).contains(hour) ? 2 : 3
            let family = workout.templateId?.uuidString ?? workout.exercises.map { $0.exercise.id.uuidString }.sorted().joined(separator: ":")
            return Observation(bucket: bucket, family: family, score: score.overallScore)
        }
        guard observations.count >= 10 else { return nil }
        let labels = ["Morning (6–11 AM)", "Afternoon (11 AM–5 PM)", "Evening (5–10 PM)", "Night (10 PM–6 AM)"]
        var candidates: [TimeOfDayAnalysis] = []
        for a in 0..<4 { for b in (a + 1)..<4 {
            var left: [Double] = [], right: [Double] = []
            var weightedLeft = 0.0, weightedRight = 0.0, weights = 0.0
            for family in Set(observations.map(\.family)) {
                let l = observations.filter { $0.family == family && $0.bucket == a }.map(\.score)
                let r = observations.filter { $0.family == family && $0.bucket == b }.map(\.score)
                guard l.count >= 3, r.count >= 3 else { continue }
                let weight = Double(min(l.count, r.count))
                weightedLeft += l.reduce(0, +) / Double(l.count) * weight
                weightedRight += r.reduce(0, +) / Double(r.count) * weight
                weights += weight; left += l; right += r
            }
            guard weights > 0 else { continue }
            let l = weightedLeft / weights, r = weightedRight / weights
            func variance(_ values: [Double]) -> Double {
                let m = values.reduce(0, +) / Double(values.count)
                return values.reduce(0) { $0 + pow($1 - m, 2) } / Double(max(values.count - 1, 1))
            }
            let se = sqrt(variance(left) / Double(left.count) + variance(right) / Double(right.count))
            guard abs(l - r) > max(5, 2.5 * se) else { continue }
            let best = l > r ? a : b, worst = l > r ? b : a
            candidates.append(TimeOfDayAnalysis(bestWindow: labels[best], bestAvgQuality: max(l, r), worstWindow: labels[worst], worstAvgQuality: min(l, r),
                message: String(format: "%@ sessions scored %.0f points higher in comparable routines", labels[best], abs(l-r)),
                bestCount: l > r ? left.count : right.count, worstCount: l > r ? right.count : left.count, windowStart: cutoff, windowEnd: now))
        } }
        return candidates.max { ($0.bestAvgQuality - $0.worstAvgQuality) < ($1.bestAvgQuality - $1.worstAvgQuality) }
    }
}
