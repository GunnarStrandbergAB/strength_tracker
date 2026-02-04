import Foundation

struct WorkoutHistory: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var workouts: [Workout]

    var completedWorkouts: [Workout] {
        workouts.filter { !$0.isInProgress }
    }

    var sortedByDate: [Workout] {
        workouts.sorted { $0.startedAt > $1.startedAt }
    }

    var totalWorkouts: Int {
        completedWorkouts.count
    }

    var totalVolume: Double {
        completedWorkouts.reduce(0) { $0 + $1.totalVolume }
    }

    var averageDuration: TimeInterval? {
        let durations = completedWorkouts.compactMap(\.duration)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    func workoutsInWeek(containing date: Date) -> [Workout] {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }
        return completedWorkouts.filter { workout in
            weekInterval.contains(workout.startedAt)
        }
    }

    func weeklyCount(for date: Date) -> Int {
        workoutsInWeek(containing: date).count
    }

    func currentWeeklyStreak() -> Int {
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

    func workoutsByMonth() -> [String: [Workout]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        var result: [String: [Workout]] = [:]
        for workout in completedWorkouts {
            let key = formatter.string(from: workout.startedAt)
            result[key, default: []].append(workout)
        }
        return result
    }
}
