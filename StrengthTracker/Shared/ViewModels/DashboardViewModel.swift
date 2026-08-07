import Foundation
import Observation

@MainActor
@Observable
public final class DashboardViewModel {
    // MARK: - Published State

    public var weeklyWorkoutCounts: [Int] = Array(repeating: 0, count: 7) // Mon-Sun
    public var weeklyQualityScores: [Double?] = Array(repeating: nil, count: 7) // Mon-Sun, nil = no workout
    public var allTimeVolume: Double = 0
    public var allTimeHours: Double = 0
    public var avgSessionsPerWeek: Double = 0
    public var recentWorkouts: [Workout] = []
    public var recentWorkoutScores: [UUID: WorkoutQualityScore] = [:]
    public var weeklyTrend: Double = 0 // percentage change vs last week
    public var weeklyWorkoutTotal: Int = 0
    public var isLoading = false

    // MARK: - Dependencies

    private let workoutRepository: any WorkoutRepository
    private let personalRecordRepository: any PersonalRecordRepository
    private let qualityScoreService: WorkoutQualityScoreService
    private let healthKitService: any HealthKitServiceProtocol
    private let userPreferencesService: UserPreferencesService

    public var weightUnit: WeightUnit { userPreferencesService.weightUnit }
    /// Body weight resolved during load() (HealthKit → prefs → default); used by
    /// per-row volume formatting so it matches the aggregate numbers.
    private var resolvedBodyWeightKg: Double = UserPreferencesService.defaultBodyWeightKg

    // MARK: - Init

    public init(
        workoutRepository: any WorkoutRepository,
        personalRecordRepository: any PersonalRecordRepository,
        qualityScoreService: WorkoutQualityScoreService,
        healthKitService: any HealthKitServiceProtocol,
        userPreferencesService: UserPreferencesService
    ) {
        self.workoutRepository = workoutRepository
        self.personalRecordRepository = personalRecordRepository
        self.qualityScoreService = qualityScoreService
        self.healthKitService = healthKitService
        self.userPreferencesService = userPreferencesService
    }

    // MARK: - Data Loading

    public func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            let completed = allWorkouts.filter { $0.completedAt != nil }

            // Resolve bodyweight once for volume calculations
            let bw = await healthKitService.fetchBodyWeightKg()
                ?? userPreferencesService.bodyWeightKg
                ?? UserPreferencesService.defaultBodyWeightKg
            resolvedBodyWeightKg = bw

            let calendar = Calendar.current
            let now = Date()

            // Determine start of current week (Monday-based)
            let currentWeekWorkouts = workoutsInWeek(from: completed, containing: now)

            // Calculate weekly counts Mon-Sun
            weeklyWorkoutCounts = calculateDailyCounts(for: currentWeekWorkouts)

            // Weekly total
            weeklyWorkoutTotal = currentWeekWorkouts.count

            // Quality scores per day (Mon-Sun) — pass history to avoid N+1 fetches
            weeklyQualityScores = calculateDailyQualityScores(for: currentWeekWorkouts, allWorkouts: allWorkouts)

            // All-time volume (bodyweight-aware)
            allTimeVolume = completed.reduce(0) { $0 + $1.totalVolume(bodyWeightKg: bw) }

            // All-time training hours
            let allTimeSeconds = completed.compactMap(\.duration).reduce(0, +)
            allTimeHours = allTimeSeconds / 3600.0

            // Average sessions per week
            if let earliest = completed.map(\.startedAt).min() {
                let weeksSinceStart = max(1, calendar.dateComponents([.weekOfYear], from: earliest, to: now).weekOfYear ?? 1)
                avgSessionsPerWeek = Double(completed.count) / Double(weeksSinceStart)
            } else {
                avgSessionsPerWeek = 0
            }

            // Recent 3 completed workouts (across all time, sorted newest first)
            let sorted = completed.sorted { $0.startedAt > $1.startedAt }
            recentWorkouts = Array(sorted.prefix(3))

            // Quality scores for recent workout cards
            var scores: [UUID: WorkoutQualityScore] = [:]
            for workout in recentWorkouts {
                let score = qualityScoreService.computeScore(for: workout, history: completed)
                scores[workout.id] = score
            }
            recentWorkoutScores = scores

            // Weekly trend: EWMA-based via aggregate quality
            let aggregate = qualityScoreService.computeAggregateScore(workouts: allWorkouts)
            if aggregate.workoutsIncluded >= 3 {
                weeklyTrend = aggregate.trendVsPrior
            } else {
                // Fall back to simple week-over-week for very new users
                let previousWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
                let previousWeekWorkouts = workoutsInWeek(from: completed, containing: previousWeekDate)
                let currentAvg = averageQualityScore(for: currentWeekWorkouts, allWorkouts: allWorkouts)
                let previousAvg = averageQualityScore(for: previousWeekWorkouts, allWorkouts: allWorkouts)
                if let curr = currentAvg, let prev = previousAvg, prev > 0 {
                    weeklyTrend = ((curr - prev) / prev) * 100.0
                } else if currentAvg != nil && previousAvg == nil {
                    weeklyTrend = 100.0
                } else {
                    weeklyTrend = 0
                }
            }
        } catch {
            // Reset state on error
            weeklyWorkoutCounts = Array(repeating: 0, count: 7)
            weeklyQualityScores = Array(repeating: nil, count: 7)
            allTimeVolume = 0
            allTimeHours = 0
            avgSessionsPerWeek = 0
            recentWorkoutScores = [:]
            recentWorkouts = []
            weeklyTrend = 0
            weeklyWorkoutTotal = 0
        }
    }

    // MARK: - Helpers

    private func workoutsInWeek(from workouts: [Workout], containing date: Date) -> [Workout] {
        let cal = Calendar.mondayStart
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }
        return workouts.filter { weekInterval.contains($0.startedAt) }
    }

    private func calculateDailyCounts(for workouts: [Workout]) -> [Int] {
        let cal = Calendar.mondayStart
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

    private func calculateDailyQualityScores(for workouts: [Workout], allWorkouts: [Workout]) -> [Double?] {
        let cal = Calendar.mondayStart
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
                let score = qualityScoreService.computeScore(for: workout, history: allWorkouts)
                dayScores.append(score.overallScore)
            }
            if !dayScores.isEmpty {
                scores[index] = dayScores.reduce(0, +) / Double(dayScores.count)
            }
        }
        return scores
    }

    private func averageQualityScore(for workouts: [Workout], allWorkouts: [Workout]) -> Double? {
        guard !workouts.isEmpty else { return nil }
        let scores = workouts.map { qualityScoreService.computeScore(for: $0, history: allWorkouts).overallScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    // MARK: - Formatting Helpers

    public func formattedVolume() -> String {
        let volume = weightUnit.fromKg(allTimeVolume)
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 10_000 {
            return String(format: "%.0fK", volume / 1_000)
        } else if volume >= 1_000 {
            return String(format: "%.1fK", volume / 1_000)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: volume)) ?? "0"
    }

    public func formattedDuration() -> String {
        if allTimeHours >= 10 {
            return String(format: "%.0f", allTimeHours)
        }
        return String(format: "%.1f", allTimeHours)
    }

    public func formattedAvgSessions() -> String {
        String(format: "%.1f", avgSessionsPerWeek)
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
        let volume = workout.totalVolume(bodyWeightKg: resolvedBodyWeightKg)
        return formatter.string(from: NSNumber(value: weightUnit.fromKg(volume))) ?? "0"
    }
}
