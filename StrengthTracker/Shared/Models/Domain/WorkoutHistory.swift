import Foundation

public struct WorkoutHistory: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var workouts: [Workout]

    public var completedWorkouts: [Workout] {
        workouts.filter { !$0.isInProgress }
    }

    public var sortedByDate: [Workout] {
        workouts.sorted { $0.startedAt > $1.startedAt }
    }

    public var totalWorkouts: Int {
        completedWorkouts.count
    }

    public var totalVolume: Double {
        completedWorkouts.reduce(0) { $0 + $1.totalVolume }
    }

    public var averageDuration: TimeInterval? {
        let durations = completedWorkouts.compactMap(\.duration)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    public func workoutsInWeek(containing date: Date) -> [Workout] {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }
        return completedWorkouts.filter { workout in
            weekInterval.contains(workout.startedAt)
        }
    }

    public func weeklyCount(for date: Date) -> Int {
        workoutsInWeek(containing: date).count
    }

    public func currentWeeklyStreak() -> Int {
        let calendar = Calendar.current
        let now = Date()
        var streak = 0
        var weekDate = now

        while true {
            let count = weeklyCount(for: weekDate)
            if count > 0 {
                streak += 1
                guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekDate) else {
                    break
                }
                weekDate = previousWeek
            } else {
                break
            }
        }

        return streak
    }

    public func workoutsByMonth() -> [String: [Workout]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        var result: [String: [Workout]] = [:]
        for workout in completedWorkouts {
            let key = formatter.string(from: workout.startedAt)
            result[key, default: []].append(workout)
        }
        return result
    }

    public init(id: UUID, workouts: [Workout]) {
        self.id = id
        self.workouts = workouts
    }
}
