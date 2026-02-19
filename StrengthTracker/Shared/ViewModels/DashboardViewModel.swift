import Foundation
import Observation

@MainActor
@Observable
public final class DashboardViewModel {
    // MARK: - Published State

    public var weeklyWorkoutCounts: [Int] = Array(repeating: 0, count: 7) // Mon-Sun
    public var weeklyQualityScores: [Double?] = Array(repeating: nil, count: 7) // Mon-Sun, nil = no workout
    public var totalVolume: Double = 0
    public var totalDurationHours: Double = 0
    public var prsThisWeek: Int = 0
    public var recentWorkouts: [Workout] = []
    public var weeklyTrend: Double = 0 // percentage change vs last week
    public var weeklyWorkoutTotal: Int = 0
    public var isLoading = false

    // MARK: - Dependencies

    private let workoutRepository: any WorkoutRepository
    private let personalRecordRepository: any PersonalRecordRepository
    private let qualityScoreService: WorkoutQualityScoreService

    // MARK: - Init

    public init(
        workoutRepository: any WorkoutRepository,
        personalRecordRepository: any PersonalRecordRepository,
        qualityScoreService: WorkoutQualityScoreService
    ) {
        self.workoutRepository = workoutRepository
        self.personalRecordRepository = personalRecordRepository
        self.qualityScoreService = qualityScoreService
    }

    // MARK: - Data Loading

    public func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            let completed = allWorkouts.filter { $0.completedAt != nil }

            let calendar = Calendar.current
            let now = Date()

            // Determine start of current week (Monday-based)
            let currentWeekWorkouts = workoutsInWeek(from: completed, containing: now, calendar: calendar)
            let previousWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            let previousWeekWorkouts = workoutsInWeek(from: completed, containing: previousWeekDate, calendar: calendar)

            // Calculate weekly counts Mon-Sun
            weeklyWorkoutCounts = calculateDailyCounts(for: currentWeekWorkouts, in: now, calendar: calendar)

            // Weekly total
            weeklyWorkoutTotal = currentWeekWorkouts.count

            // Quality scores per day (Mon-Sun)
            weeklyQualityScores = await calculateDailyQualityScores(for: currentWeekWorkouts, calendar: calendar)

            // Total volume this week
            totalVolume = currentWeekWorkouts.reduce(0) { $0 + $1.totalVolume }

            // Total duration this week (in hours)
            let totalSeconds = currentWeekWorkouts.compactMap(\.duration).reduce(0, +)
            totalDurationHours = totalSeconds / 3600.0

            // PRs this week: count sets flagged as personal records in this week's workouts
            prsThisWeek = countPRsInWorkouts(currentWeekWorkouts)

            // Recent 3 completed workouts (across all time, sorted newest first)
            let sorted = completed.sorted { $0.startedAt > $1.startedAt }
            recentWorkouts = Array(sorted.prefix(3))

            // Weekly trend: percentage change vs previous week
            let currentCount = Double(currentWeekWorkouts.count)
            let previousCount = Double(previousWeekWorkouts.count)
            if previousCount > 0 {
                weeklyTrend = ((currentCount - previousCount) / previousCount) * 100.0
            } else if currentCount > 0 {
                weeklyTrend = 100.0
            } else {
                weeklyTrend = 0
            }
        } catch {
            // Reset state on error
            weeklyWorkoutCounts = Array(repeating: 0, count: 7)
            weeklyQualityScores = Array(repeating: nil, count: 7)
            totalVolume = 0
            totalDurationHours = 0
            prsThisWeek = 0
            recentWorkouts = []
            weeklyTrend = 0
            weeklyWorkoutTotal = 0
        }
    }

    // MARK: - Helpers

    private func workoutsInWeek(from workouts: [Workout], containing date: Date, calendar: Calendar) -> [Workout] {
        // Use ISO 8601 week (Monday = first day)
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }
        return workouts.filter { weekInterval.contains($0.startedAt) }
    }

    private func calculateDailyCounts(for workouts: [Workout], in referenceDate: Date, calendar: Calendar) -> [Int] {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        var counts = Array(repeating: 0, count: 7)

        for workout in workouts {
            // weekday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
            let weekday = cal.component(.weekday, from: workout.startedAt)
            // Convert to Mon=0, Tue=1, ..., Sun=6
            let index = (weekday + 5) % 7
            counts[index] += 1
        }

        return counts
    }

    private func calculateDailyQualityScores(for workouts: [Workout], calendar: Calendar) async -> [Double?] {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        // Group workouts by weekday index (Mon=0 .. Sun=6)
        var grouped: [Int: [Workout]] = [:]
        for workout in workouts {
            let weekday = cal.component(.weekday, from: workout.startedAt)
            let index = (weekday + 5) % 7
            grouped[index, default: []].append(workout)
        }

        var scores: [Double?] = Array(repeating: nil, count: 7)
        for (index, dayWorkouts) in grouped {
            var dayScores: [Double] = []
            for workout in dayWorkouts {
                if let score = try? await qualityScoreService.computeScore(for: workout) {
                    dayScores.append(score.overallScore)
                }
            }
            if !dayScores.isEmpty {
                scores[index] = dayScores.reduce(0, +) / Double(dayScores.count)
            }
        }
        return scores
    }

    private func countPRsInWorkouts(_ workouts: [Workout]) -> Int {
        var count = 0
        for workout in workouts {
            for exercise in workout.exercises {
                for set in exercise.sets where set.isPersonalRecord {
                    count += 1
                }
            }
        }
        return count
    }

    // MARK: - Formatting Helpers

    public func formattedVolume() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: totalVolume)) ?? "0"
    }

    public func formattedDuration() -> String {
        if totalDurationHours >= 10 {
            return String(format: "%.0f", totalDurationHours)
        }
        return String(format: "%.1f", totalDurationHours)
    }

    public func formattedTrend() -> String {
        let absValue = abs(weeklyTrend)
        if absValue == absValue.rounded() {
            return String(format: "%.0f%%", absValue)
        }
        return String(format: "%.0f%%", absValue)
    }

    public func trendIsPositive() -> Bool {
        weeklyTrend >= 0
    }

    public func formatWorkoutDuration(_ workout: Workout) -> String {
        guard let duration = workout.duration else { return "--" }
        let minutes = Int(duration) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)m"
    }

    public func formatWorkoutDate(_ workout: Workout) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(workout.startedAt) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            return "Today \u{2022} \(timeFormatter.string(from: workout.startedAt))"
        } else if calendar.isDateInYesterday(workout.startedAt) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            return "Yesterday \u{2022} \(timeFormatter.string(from: workout.startedAt))"
        } else {
            let daysDiff = calendar.dateComponents([.day], from: workout.startedAt, to: now).day ?? 0
            if daysDiff < 7 {
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEEE"
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"
                return "\(dayFormatter.string(from: workout.startedAt)) \u{2022} \(timeFormatter.string(from: workout.startedAt))"
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"
                return "\(dateFormatter.string(from: workout.startedAt)) \u{2022} \(timeFormatter.string(from: workout.startedAt))"
            }
        }
    }

    public func totalSetsCount(for workout: Workout) -> Int {
        workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    public func formattedWorkoutVolume(_ workout: Workout) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: workout.totalVolume)) ?? "0"
    }
}
