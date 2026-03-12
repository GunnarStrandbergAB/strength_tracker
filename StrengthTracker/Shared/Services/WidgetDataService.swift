import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

public final class WidgetDataService: Sendable {
    public init() {}

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Write widget data to shared App Group UserDefaults
    public func updateWidgetData(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId) else { return }
        if let encoded = try? encoder.encode(data) {
            defaults.set(encoded, forKey: WidgetData.userDefaultsKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Read widget data from shared App Group UserDefaults
    public func readWidgetData() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId),
              let data = defaults.data(forKey: WidgetData.userDefaultsKey),
              let widgetData = try? decoder.decode(WidgetData.self, from: data) else {
            return .empty
        }
        return widgetData
    }

    // MARK: - Active Workout State

    /// Update just the active workout portion of widget data (called frequently during workouts)
    public func updateActiveWorkoutState(_ activeWorkout: WidgetActiveWorkout?) {
        let current = readWidgetData()
        let updated = WidgetData(
            lastWorkoutDate: current.lastWorkoutDate,
            lastWorkoutName: current.lastWorkoutName,
            lastWorkoutExerciseCount: current.lastWorkoutExerciseCount,
            lastWorkoutDuration: current.lastWorkoutDuration,
            weeklyWorkoutCount: current.weeklyWorkoutCount,
            weeklyGoal: current.weeklyGoal,
            currentStreak: current.currentStreak,
            totalWorkoutsAllTime: current.totalWorkoutsAllTime,
            updatedAt: Date(),
            highlights: current.highlights,
            weekDaysTrained: current.weekDaysTrained,
            activeWorkout: activeWorkout,
            nextPlannedSession: current.nextPlannedSession,
            weeklyVolume: current.weeklyVolume,
            previousWeekVolume: current.previousWeekVolume
        )
        updateWidgetData(updated)
    }

    // MARK: - Build Full Widget Data

    /// Build comprehensive widget data from app state.
    /// Call this on app foreground, workout completion, etc.
    public func buildWidgetData(
        workouts: [Workout],
        highlights: [AnalyticsHighlight],
        activeWorkout: Workout?,
        isResting: Bool,
        restEndDate: Date?,
        nextPlannedSession: WidgetPlannedSession?,
        weeklyGoal: Int
    ) -> WidgetData {
        let now = Date()
        let calendar = Calendar.current

        // Last workout (most recent completed)
        let completedWorkouts = workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let lastWorkout = completedWorkouts.first

        // Weekly workout count (this calendar week)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weeklyCount = completedWorkouts.filter { ($0.completedAt ?? .distantPast) >= startOfWeek }.count

        // Streak calculation
        let streak = calculateStreak(from: completedWorkouts, calendar: calendar, today: now)

        // 7-day calendar (Mon=0 .. Sun=6)
        let weekDaysTrained = buildWeekCalendar(from: completedWorkouts, calendar: calendar, now: now)

        // Volume trend
        let (weeklyVolume, previousWeekVolume) = calculateVolumeTrend(
            from: completedWorkouts, calendar: calendar, now: now
        )

        // Map analytics highlights to widget highlights
        let widgetHighlights = highlights.prefix(3).map { mapHighlight($0) }

        // Active workout state
        let widgetActiveWorkout: WidgetActiveWorkout?
        if let workout = activeWorkout, workout.completedAt == nil {
            widgetActiveWorkout = buildActiveWorkoutState(
                workout: workout, isResting: isResting, restEndDate: restEndDate
            )
        } else {
            widgetActiveWorkout = nil
        }

        return WidgetData(
            lastWorkoutDate: lastWorkout?.completedAt,
            lastWorkoutName: lastWorkout?.name,
            lastWorkoutExerciseCount: lastWorkout?.exercises.count ?? 0,
            lastWorkoutDuration: lastWorkout?.duration,
            weeklyWorkoutCount: weeklyCount,
            weeklyGoal: weeklyGoal,
            currentStreak: streak,
            totalWorkoutsAllTime: completedWorkouts.count,
            updatedAt: now,
            highlights: Array(widgetHighlights),
            weekDaysTrained: weekDaysTrained,
            activeWorkout: widgetActiveWorkout,
            nextPlannedSession: nextPlannedSession,
            weeklyVolume: weeklyVolume,
            previousWeekVolume: previousWeekVolume
        )
    }

    // MARK: - Helpers

    private func calculateStreak(from workouts: [Workout], calendar: Calendar, today: Date) -> Int {
        guard !workouts.isEmpty else { return 0 }

        // Get unique training dates
        let trainingDays = Set(workouts.compactMap { workout -> DateComponents? in
            guard let date = workout.completedAt else { return nil }
            return calendar.dateComponents([.year, .month, .day], from: date)
        })

        var streak = 0
        var checkDate = today

        // Allow today or yesterday as the start
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: checkDate)
        if !trainingDays.contains(todayComponents) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while true {
            let components = calendar.dateComponents([.year, .month, .day], from: checkDate)
            if trainingDays.contains(components) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return streak
    }

    private func buildWeekCalendar(from workouts: [Workout], calendar: Calendar, now: Date) -> [Bool] {
        // Find Monday of the current week
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: now) else {
            return Array(repeating: false, count: 7)
        }
        let monday = weekInterval.start

        var trained = Array(repeating: false, count: 7)
        for workout in workouts {
            guard let date = workout.completedAt, date >= monday else { continue }
            let dayOfWeek = cal.component(.weekday, from: date)
            // Convert: Sunday=1, Monday=2, ..., Saturday=7 -> Mon=0, ..., Sun=6
            let index = (dayOfWeek + 5) % 7
            if index < 7 { trained[index] = true }
        }
        return trained
    }

    private func calculateVolumeTrend(
        from workouts: [Workout], calendar: Calendar, now: Date
    ) -> (current: Double?, previous: Double?) {
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return (nil, nil)
        }
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart

        let thisWeekVolume = workouts
            .filter { ($0.completedAt ?? .distantPast) >= thisWeekStart }
            .reduce(0.0) { $0 + $1.totalVolume }

        let lastWeekVolume = workouts
            .filter {
                let date = $0.completedAt ?? .distantPast
                return date >= lastWeekStart && date < thisWeekStart
            }
            .reduce(0.0) { $0 + $1.totalVolume }

        return (
            thisWeekVolume > 0 ? thisWeekVolume : nil,
            lastWeekVolume > 0 ? lastWeekVolume : nil
        )
    }

    private func mapHighlight(_ highlight: AnalyticsHighlight) -> WidgetHighlight {
        let (icon, color): (String, String) = switch highlight.type {
        case .personalRecord: ("trophy.fill", "yellow")
        case .streak: ("flame.fill", "orange")
        case .milestone: ("star.fill", "blue")
        case .improvement: ("arrow.up.right", "green")
        case .warning: ("exclamationmark.triangle.fill", "red")
        }
        return WidgetHighlight(icon: icon, title: highlight.title, detail: highlight.detail, color: color)
    }

    private func buildActiveWorkoutState(
        workout: Workout, isResting: Bool, restEndDate: Date?
    ) -> WidgetActiveWorkout {
        // Find current exercise (first with incomplete sets, or last)
        let currentExercise = workout.exercises.first { ex in
            ex.sets.contains { !$0.isCompleted }
        } ?? workout.exercises.last

        let completedSets = workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
        let totalSets = workout.exercises.reduce(0) { $0 + $1.sets.count }

        // Find next incomplete set for targets
        let nextSet = currentExercise?.sets.first { !$0.isCompleted }

        // Find next exercise after current
        let currentIndex = workout.exercises.firstIndex { $0.id == currentExercise?.id }
        let nextExercise: WorkoutExercise?
        if let idx = currentIndex, idx + 1 < workout.exercises.count {
            nextExercise = workout.exercises[idx + 1]
        } else {
            nextExercise = nil
        }

        return WidgetActiveWorkout(
            workoutName: workout.name,
            currentExerciseName: currentExercise?.exercise.name ?? "Exercise",
            currentExerciseId: currentExercise?.id.uuidString ?? "",
            completedSets: completedSets,
            totalPlannedSets: totalSets,
            startedAt: workout.startedAt,
            isResting: isResting,
            restEndDate: restEndDate,
            nextSetWeight: nextSet?.weight,
            nextSetReps: nextSet?.reps,
            nextExerciseName: nextExercise?.exercise.name
        )
    }

    // MARK: - Watch Rest Timer State

    /// Write watch rest timer state to App Group for the watchOS widget
    public func updateWatchRestTimerState(_ state: WatchRestTimerState?) {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId) else { return }
        if let state, let encoded = try? encoder.encode(state) {
            defaults.set(encoded, forKey: WatchRestTimerState.userDefaultsKey)
        } else {
            defaults.removeObject(forKey: WatchRestTimerState.userDefaultsKey)
        }
        defaults.synchronize()   // force cross-process sync before reload
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "WatchRestTimerWidget")
        // Safety-net reload in case first fires before UserDefaults syncs
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WidgetCenter.shared.reloadTimelines(ofKind: "WatchRestTimerWidget")
        }
        #endif
    }

    /// Read watch rest timer state from App Group
    public func readWatchRestTimerState() -> WatchRestTimerState? {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId),
              let data = defaults.data(forKey: WatchRestTimerState.userDefaultsKey),
              let state = try? decoder.decode(WatchRestTimerState.self, from: data) else { return nil }
        guard state.endDate > Date() else { return nil }
        return state
    }

    // MARK: - Pending Completions (Widget → App sync)

    /// Read pending set completions written by widget intents
    public func readPendingCompletions() -> [WidgetPendingCompletion] {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId),
              let data = defaults.data(forKey: WidgetData.pendingCompletionsKey),
              let completions = try? decoder.decode([WidgetPendingCompletion].self, from: data) else {
            return []
        }
        return completions
    }

    /// Clear pending completions after the app has processed them
    public func clearPendingCompletions() {
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId) else { return }
        defaults.removeObject(forKey: WidgetData.pendingCompletionsKey)
    }

    /// Append a pending completion (used by widget intents)
    public func appendPendingCompletion(_ completion: WidgetPendingCompletion) {
        var existing = readPendingCompletions()
        existing.append(completion)
        guard let defaults = UserDefaults(suiteName: WidgetData.appGroupId),
              let encoded = try? encoder.encode(existing) else { return }
        defaults.set(encoded, forKey: WidgetData.pendingCompletionsKey)
    }
}

/// A pending set completion recorded by a widget intent, to be persisted by the app
public struct WidgetPendingCompletion: Codable, Sendable {
    public let exerciseId: String  // UUID string
    public let setIndex: Int
    public let completedAt: Date

    public init(exerciseId: String, setIndex: Int, completedAt: Date) {
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.completedAt = completedAt
    }
}
