import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

public final class WidgetDataService: Sendable {
    public init() {}

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Serializes read-modify-write cycles on shared UserDefaults within this process.
    /// (Cross-process races with the widget extension remain possible but are bounded
    /// by UserDefaults' own atomicity per key.)
    private let pendingCompletionsLock = NSLock()

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
            previousWeekVolume: current.previousWeekVolume,
            weeklyQualityScore: current.weeklyQualityScore,
            qualityTrend: current.qualityTrend,
            weightUnitSymbol: current.weightUnitSymbol,
            analyticsGeneratedAt: current.analyticsGeneratedAt
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
        weeklyGoal: Int,
        bodyWeightKg: Double,
        weeklyQualityScore: Double? = nil,
        qualityTrend: Double? = nil,
        activeExerciseId: UUID? = nil,
        weightUnitSymbol: String = "kg",
        analyticsGeneratedAt: Date? = nil
    ) -> WidgetData {
        let now = Date()
        let calendar = Calendar.mondayStart

        // Last workout (most recent completed)
        let completedWorkouts = workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let lastWorkout = completedWorkouts.first

        // Weekly workout count (Monday-start week, by training date) — the same
        // definition the Dashboard chart uses.
        let weeklyCount = WorkoutWeekWindow.split(completedWorkouts, now: now, calendar: calendar).current.count

        // Streak = consecutive trained weeks (lifters train a few times a week; a
        // day streak reads 0 or 1 almost always).
        let streak = WorkoutWeekWindow.consecutiveWeeksTrained(completedWorkouts, now: now, calendar: calendar)

        // 7-day calendar (Mon=0 .. Sun=6)
        let weekDaysTrained = buildWeekCalendar(from: completedWorkouts, calendar: calendar, now: now)

        // Volume trend (calendar-week, bodyweight-aware)
        let (weeklyVolume, previousWeekVolume) = calculateVolumeTrend(
            from: completedWorkouts, calendar: calendar, now: now, bodyWeightKg: bodyWeightKg
        )

        // Map analytics highlights to widget highlights
        let widgetHighlights = highlights.prefix(3).map { mapHighlight($0) }

        // Active workout state
        let widgetActiveWorkout: WidgetActiveWorkout?
        if let workout = activeWorkout, workout.completedAt == nil {
            widgetActiveWorkout = buildActiveWorkoutState(
                workout: workout, isResting: isResting, restEndDate: restEndDate,
                activeExerciseId: activeExerciseId
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
            previousWeekVolume: previousWeekVolume,
            weeklyQualityScore: weeklyQualityScore,
            qualityTrend: qualityTrend,
            weightUnitSymbol: weightUnitSymbol,
            analyticsGeneratedAt: analyticsGeneratedAt
        )
    }

    // MARK: - Helpers

    private func buildWeekCalendar(from workouts: [Workout], calendar: Calendar, now: Date) -> [Bool] {
        // Find Monday of the current week (calendar is already Monday-start)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return Array(repeating: false, count: 7)
        }
        let monday = weekInterval.start

        var trained = Array(repeating: false, count: 7)
        for workout in workouts where workout.completedAt != nil {
            let date = workout.trainingDate
            guard date >= monday else { continue }
            let dayOfWeek = calendar.component(.weekday, from: date)
            // Convert: Sunday=1, Monday=2, ..., Saturday=7 -> Mon=0, ..., Sun=6
            let index = (dayOfWeek + 5) % 7
            if index < 7 { trained[index] = true }
        }
        return trained
    }

    /// Splits completed workouts into the current and previous calendar week.
    /// Delegates to `WorkoutWeekWindow` — the one week definition in the app.
    public func weeklyWorkoutSplit(
        from workouts: [Workout], calendar: Calendar = .mondayStart, now: Date = Date()
    ) -> (current: [Workout], previous: [Workout]) {
        let window = WorkoutWeekWindow.split(workouts, now: now, calendar: calendar)
        return (window.current, window.previous)
    }

    /// Calendar-week (Monday-start) volume for the current and previous week.
    public func calculateVolumeTrend(
        from workouts: [Workout], calendar: Calendar = .mondayStart, now: Date = Date(),
        bodyWeightKg: Double
    ) -> (current: Double?, previous: Double?) {
        let (thisWeek, lastWeek) = weeklyWorkoutSplit(from: workouts, calendar: calendar, now: now)
        let thisWeekVolume = thisWeek.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bodyWeightKg) }
        let lastWeekVolume = lastWeek.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bodyWeightKg) }

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
        return WidgetHighlight(id: highlight.id, icon: icon, title: highlight.title, detail: highlight.detail, color: color, destination: highlight.destination, validUntil: highlight.validUntil, isAction: highlight.isAction ?? false)
    }

    public func buildActiveWorkoutState(
        workout: Workout, isResting: Bool, restEndDate: Date?, activeExerciseId: UUID? = nil
    ) -> WidgetActiveWorkout {
        let currentExercise = workout.activeExercise(preferredId: activeExerciseId)

        let completedSets = workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
        let totalSets = workout.exercises.reduce(0) { $0 + $1.sets.count }

        // Find next incomplete set for targets
        let nextSet = currentExercise?.sets.first { !$0.isCompleted }
        let nextSetIndex = currentExercise?.sets.firstIndex { !$0.isCompleted }

        let nextExercise = workout.nextIncompleteExercise(afterId: currentExercise?.id)

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
            nextExerciseName: nextExercise?.exercise.name,
            nextSetIndex: nextSetIndex,
            nextExerciseId: nextExercise?.id.uuidString
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

    /// Append a pending completion (used by widget intents).
    /// Locked: two rapid widget taps would otherwise lose the first append.
    public func appendPendingCompletion(_ completion: WidgetPendingCompletion) {
        pendingCompletionsLock.lock()
        defer { pendingCompletionsLock.unlock() }
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
