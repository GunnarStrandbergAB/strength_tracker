import Foundation

public struct Achievement: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String
    public let earnedAt: Date?

    public init(id: String, name: String, description: String, icon: String, earnedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.earnedAt = earnedAt
    }

    public var isEarned: Bool { earnedAt != nil }
}

public struct VolumeResponseCurve: Sendable {
    public let muscleGroup: String
    public let personalMEV: Double?
    public let personalMAV: Double?
    public let personalMRV: Double?
    public let rSquared: Double
    public let message: String

    public init(muscleGroup: String, personalMEV: Double?, personalMAV: Double?, personalMRV: Double?, rSquared: Double, message: String) {
        self.muscleGroup = muscleGroup
        self.personalMEV = personalMEV
        self.personalMAV = personalMAV
        self.personalMRV = personalMRV
        self.rSquared = rSquared
        self.message = message
    }
}

@MainActor
public final class AchievementTrackingService: Sendable {

    private let storageKey = "earned_achievements"

    public init() {}

    public func checkAchievements(
        workout: Workout,
        overloadTrends: [OverloadTrend],
        allWorkouts: [Workout]
    ) -> [Achievement] {
        var earned: [Achievement] = []
        let stored = loadEarned()

        // Progressive Loader: 3+ exercises with overloaded sets
        if !stored.contains("progressive_loader") {
            let overloadedExercises = overloadTrends.filter { $0.trendStatus == .progressing }
            if overloadedExercises.count >= 3 {
                let a = Achievement(id: "progressive_loader", name: "Progressive Loader", description: "3+ exercises progressing in one session", icon: "arrow.up.right.circle.fill", earnedAt: Date())
                earned.append(a)
                save(achievementId: a.id)
            }
        }

        // Plateau Breaker: exercise went from plateau to progressing
        if !stored.contains("plateau_breaker") {
            let progressing = overloadTrends.filter { $0.trendStatus == .progressing }
            if progressing.count >= 1 {
                // Simplified: first time 3+ weeks of progression
                if let best = progressing.first, best.weeklyE1RMs.count >= 3 {
                    let a = Achievement(id: "plateau_breaker", name: "Plateau Breaker", description: "Broke through a strength plateau", icon: "bolt.circle.fill", earnedAt: Date())
                    earned.append(a)
                    save(achievementId: a.id)
                }
            }
        }

        // Iron Consistency: 8 consecutive weeks with workouts
        if !stored.contains("iron_consistency") {
            let calendar = Calendar.current
            let now = Date()
            var streak = 0
            for weekOffset in (0..<8).reversed() {
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) else { break }
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
                let has = allWorkouts.contains { w in
                    guard let d = w.completedAt else { return false }
                    return d >= weekStart && d < weekEnd
                }
                if has { streak += 1 } else { streak = 0 }
            }
            if streak >= 8 {
                let a = Achievement(id: "iron_consistency", name: "Iron Consistency", description: "8 consecutive weeks of training", icon: "flame.circle.fill", earnedAt: Date())
                earned.append(a)
                save(achievementId: a.id)
            }
        }

        return earned
    }

    public func allAchievements() -> [Achievement] {
        let stored = loadEarned()
        let defs: [(id: String, name: String, desc: String, icon: String)] = [
            ("progressive_loader", "Progressive Loader", "3+ exercises progressing simultaneously", "arrow.up.right.circle.fill"),
            ("plateau_breaker", "Plateau Breaker", "Broke through a strength plateau", "bolt.circle.fill"),
            ("iron_consistency", "Iron Consistency", "8 consecutive weeks of training", "flame.circle.fill"),
            ("balanced_builder", "Balanced Builder", "All muscle groups at optimal volume for 4 weeks", "scale.3d"),
            ("volume_explorer", "Volume Explorer", "All 6 muscle groups in one week", "globe"),
            ("smart_recovery", "Smart Recovery", "Took deload when recommended", "heart.circle.fill"),
        ]
        return defs.map { def in
            Achievement(id: def.id, name: def.name, description: def.desc, icon: def.icon,
                       earnedAt: stored.contains(def.id) ? Date() : nil)
        }
    }

    // MARK: - Volume-Response Curve (A9)

    public func computeVolumeResponse(
        workouts: [Workout],
        overloadTrends: [OverloadTrend]
    ) -> [VolumeResponseCurve] {
        let completed = workouts.filter { $0.completedAt != nil }
        guard completed.count >= 50 else { return [] }

        // Group into weekly blocks per muscle group
        var muscleWeeklyData: [String: [(sets: Double, gain: Double)]] = [:]

        // Simple approach: for each muscle group, compute weekly sets and corresponding
        // overload trend slope as the "gain" proxy
        for trend in overloadTrends {
            let exerciseWorkouts = completed.filter { w in
                w.exercises.contains { $0.exercise.id == trend.exerciseId }
            }

            // Get primary muscle group from workout exercises
            guard let primaryMuscle = exerciseWorkouts.first?.exercises
                .first(where: { $0.exercise.id == trend.exerciseId })?
                .exercise.primaryMuscleGroup.rawValue.lowercased() else { continue }

            // Weekly sets for this exercise
            for workout in exerciseWorkouts {
                guard let exercise = workout.exercises.first(where: { $0.exercise.id == trend.exerciseId }) else { continue }
                let sets = Double(exercise.sets.filter { $0.isCompleted && $0.setType != .warmup }.count)
                muscleWeeklyData[primaryMuscle, default: []].append((sets, trend.slopePerWeek))
            }
        }

        var curves: [VolumeResponseCurve] = []

        for (muscle, dataPoints) in muscleWeeklyData {
            guard dataPoints.count >= 12 else { continue }

            let xs = dataPoints.map(\.sets)
            let ys = dataPoints.map(\.gain)

            // Quadratic regression: gain = a*sets^2 + b*sets + c
            guard let qr = quadraticRegression(xs: xs, ys: ys), qr.rSquared > 0.3 else { continue }

            // Find vertex (MAV) and bounds (MEV, MRV)
            let (a, b, _) = (qr.a, qr.b, qr.c)
            guard a < 0 else { continue } // Must be inverted parabola

            let vertex = -b / (2 * a) // sets at peak
            let mav = max(0, vertex)

            // MEV: lower bound where gain > 0
            let discriminant = b * b - 4 * a * qr.c
            let mev: Double?
            let mrv: Double?
            if discriminant >= 0 {
                let root1 = (-b - sqrt(discriminant)) / (2 * a)
                let root2 = (-b + sqrt(discriminant)) / (2 * a)
                mev = max(0, min(root1, root2))
                mrv = max(root1, root2)
            } else {
                mev = nil
                mrv = nil
            }

            curves.append(VolumeResponseCurve(
                muscleGroup: muscle,
                personalMEV: mev,
                personalMAV: mav,
                personalMRV: mrv,
                rSquared: qr.rSquared,
                message: String(format: "Your %@ responds best to %.0f-%.0f sets/week", muscle, mev ?? 0, mrv ?? mav * 1.2)
            ))
        }

        return curves
    }

    // MARK: - Private

    private func loadEarned() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        return Set(arr)
    }

    private func save(achievementId: String) {
        var arr = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        if !arr.contains(achievementId) {
            arr.append(achievementId)
            UserDefaults.standard.set(arr, forKey: storageKey)
        }
    }

    private struct QuadraticResult {
        let a: Double, b: Double, c: Double, rSquared: Double
    }

    private func quadraticRegression(xs: [Double], ys: [Double]) -> QuadraticResult? {
        let n = Double(xs.count)
        guard xs.count >= 3, xs.count == ys.count else { return nil }

        let x2s = xs.map { $0 * $0 }
        let sumX = xs.reduce(0, +)
        let sumX2 = x2s.reduce(0, +)
        let sumX3 = zip(x2s, xs).map(*).reduce(0, +)
        let sumX4 = x2s.map { $0 * $0 }.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2Y = zip(x2s, ys).map(*).reduce(0, +)

        // Solve 3x3 system using Cramer's rule
        let d = n * (sumX2 * sumX4 - sumX3 * sumX3) - sumX * (sumX * sumX4 - sumX3 * sumX2) + sumX2 * (sumX * sumX3 - sumX2 * sumX2)
        guard abs(d) > 1e-10 else { return nil }

        let c = (sumY * (sumX2 * sumX4 - sumX3 * sumX3) - sumX * (sumXY * sumX4 - sumX2Y * sumX3) + sumX2 * (sumXY * sumX3 - sumX2Y * sumX2)) / d
        let b = (n * (sumXY * sumX4 - sumX2Y * sumX3) - sumY * (sumX * sumX4 - sumX3 * sumX2) + sumX2 * (sumX * sumX2Y - sumXY * sumX2)) / d
        let a = (n * (sumX2 * sumX2Y - sumX3 * sumXY) - sumX * (sumX * sumX2Y - sumXY * sumX2) + sumY * (sumX * sumX3 - sumX2 * sumX2)) / d

        // R-squared
        let yMean = sumY / n
        let ssTotal = ys.map { pow($0 - yMean, 2) }.reduce(0, +)
        let ssResidual: Double = zip(xs, ys).map { x, y in
            let predicted = a * x * x + b * x + c
            return pow(y - predicted, 2)
        }.reduce(0.0, +)
        let r2 = ssTotal > 0 ? 1.0 - ssResidual / ssTotal : 0

        return QuadraticResult(a: a, b: b, c: c, rSquared: r2)
    }
}
