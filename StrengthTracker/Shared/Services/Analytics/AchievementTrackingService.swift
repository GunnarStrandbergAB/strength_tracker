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

}
