import Foundation
import Observation
#if os(watchOS)
import WatchKit
#endif

@MainActor
@Observable
public final class WatchWorkoutViewModel {
    public var activeWorkout: Workout? = nil
    public var currentExerciseIndex: Int = 0
    public var isActive = false
    public var isQuickStart: Bool = false
    public var plannedSessionId: UUID? = nil
    public var plannedPlanId: UUID? = nil

    // Template target data per exercise index
    public var plannedSetsPerExercise: [Int: Int] = [:]
    public var targetWeightPerExercise: [Int: Double?] = [:]
    public var targetRepsPerExercise: [Int: Int?] = [:]

    // Rest timer state
    public var isResting = false
    public var restTimeRemaining: TimeInterval = 0
    public var restDuration: TimeInterval = TimeInterval(UserPreferencesService.defaultRestSecondsValue)

    // Set navigation (nil = active/next set)
    public var viewingSetIndex: Int? = nil

    // Pending set type for quick-start (no sets exist yet)
    public var pendingSetType: SetType = .normal

    // Completion guard (prevents double-tap and provides loading state)
    public var isCompleting = false

    // Notes
    public var workoutNotes: String = ""

    // HealthKit metrics (forwarded from WatchWorkoutSessionManager)
    public var heartRate: Double { watchSessionManager?.heartRate ?? 0 }
    public var activeCalories: Double { watchSessionManager?.activeCalories ?? 0 }
    public var healthKitElapsedTime: TimeInterval { watchSessionManager?.elapsedTime ?? 0 }
    public var isHealthKitSessionActive: Bool { watchSessionManager?.isSessionActive ?? false }

    private let workoutRepository: any WorkoutRepository
    private let healthKitService: any HealthKitServiceProtocol
    private let connectivityManager: ConnectivityManager
    private let userPreferencesService: UserPreferencesService?
    private let analyticsService: WorkoutAnalyticsService?
    private var restTimer: Timer?
    private var restStartDate: Date?

    // Watch workout session manager (nil on iOS)
    private var watchSessionManager: (any WatchWorkoutSessionManager)?

    public init(
        workoutRepository: any WorkoutRepository,
        healthKitService: any HealthKitServiceProtocol,
        connectivityManager: ConnectivityManager,
        userPreferencesService: UserPreferencesService? = nil,
        analyticsService: WorkoutAnalyticsService? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.healthKitService = healthKitService
        self.connectivityManager = connectivityManager
        self.userPreferencesService = userPreferencesService
        self.analyticsService = analyticsService
        if let prefs = userPreferencesService {
            self.restDuration = TimeInterval(prefs.defaultRestSeconds)
        }
    }

    public func setWatchSessionManager(_ manager: any WatchWorkoutSessionManager) {
        self.watchSessionManager = manager
    }

    // MARK: - Computed Properties

    public var currentExercise: WorkoutExercise? {
        guard let workout = activeWorkout,
              currentExerciseIndex < workout.exercises.count else {
            return nil
        }
        return workout.exercises[currentExerciseIndex]
    }

    public var currentSetNumber: Int {
        guard let exercise = currentExercise else { return 1 }
        let completedCount = exercise.sets.filter(\.isCompleted).count
        return completedCount + 1
    }

    public var hasPlannedSets: Bool {
        plannedSetsPerExercise[currentExerciseIndex] != nil
    }

    public var plannedSets: Int {
        plannedSetsPerExercise[currentExerciseIndex] ?? (isQuickStart ? 1 : 4)
    }

    public var currentTargetWeight: Double? {
        // Prefer the next incomplete pre-populated set's weight (per-set targets from template)
        if let exercise = currentExercise,
           let nextIncomplete = exercise.sets.first(where: { !$0.isCompleted }) {
            return nextIncomplete.weight
        }
        // Fall back to exercise-level target for extra sets
        return targetWeightPerExercise[currentExerciseIndex] ?? nil
    }

    public var currentTargetReps: Int? {
        // Prefer the next incomplete pre-populated set's reps (per-set targets from template)
        if let exercise = currentExercise,
           let nextIncomplete = exercise.sets.first(where: { !$0.isCompleted }) {
            return nextIncomplete.reps
        }
        // Fall back to exercise-level target for extra sets
        return targetRepsPerExercise[currentExerciseIndex] ?? nil
    }

    public var isEditingCompletedSet: Bool {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise else { return false }
        return idx < exercise.sets.count && exercise.sets[idx].isCompleted
    }

    public var viewingSetWeight: Double? {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise,
              idx < exercise.sets.count else { return currentTargetWeight }
        return exercise.sets[idx].weight
    }

    public var viewingSetReps: Int? {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise,
              idx < exercise.sets.count else { return currentTargetReps }
        return exercise.sets[idx].reps
    }

    public var canNavigateToPreviousSet: Bool {
        guard let exercise = currentExercise else { return false }
        let completedCount = exercise.sets.filter(\.isCompleted).count
        if viewingSetIndex == nil {
            return completedCount > 0
        }
        return (viewingSetIndex ?? 0) > 0
    }

    public var canNavigateToNextSet: Bool {
        viewingSetIndex != nil
    }

    public var currentExercisePlannedSetsComplete: Bool {
        guard !isQuickStart,
              let planned = plannedSetsPerExercise[currentExerciseIndex],
              let exercise = currentExercise else { return false }
        return exercise.sets.filter(\.isCompleted).count >= planned
    }

    public var isLastExercise: Bool {
        guard let workout = activeWorkout else { return false }
        return currentExerciseIndex >= workout.exercises.count - 1
    }

    public var currentExerciseVolume: Double {
        currentExercise?.exerciseVolume ?? 0
    }

    public var totalSetsCompleted: Int {
        guard let workout = activeWorkout else { return 0 }
        return workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    public var elapsedTime: TimeInterval {
        guard let workout = activeWorkout else { return 0 }
        return Date().timeIntervalSince(workout.startedAt)
    }

    public var restTimerText: String {
        let minutes = Int(restTimeRemaining) / 60
        let seconds = Int(restTimeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var restProgress: Double {
        guard restDuration > 0 else { return 0 }
        return 1.0 - (restTimeRemaining / restDuration)
    }

    // MARK: - Workout Lifecycle

    /// Synchronous: builds workout, sets state, activates navigation immediately.
    /// Call from the same synchronous scope as sheet dismiss for batched rendering.
    public func prepareQuickStart(name: String, exercises: [Exercise]) {
        isQuickStart = true
        plannedSetsPerExercise = [:]
        targetWeightPerExercise = [:]
        targetRepsPerExercise = [:]
        viewingSetIndex = nil

        let workoutExercises = exercises.enumerated().map { index, exercise in
            WorkoutExercise(
                id: UUID(),
                exercise: exercise,
                order: index + 1,
                supersetGroup: nil,
                notes: nil,
                restTimerSeconds: nil,
                sets: []
            )
        }

        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            healthKitWorkoutId: nil,
            exercises: workoutExercises
        )

        activeWorkout = workout
        currentExerciseIndex = 0
        isActive = true
    }

    /// Async: persists the current workout and starts HealthKit session.
    /// Call in a background Task after prepareQuickStart.
    public func persistAndStartSession() async {
        guard let workout = activeWorkout else { return }

        do {
            let saved = try await workoutRepository.save(workout)
            activeWorkout = saved
        } catch {
            print("[WatchWorkoutVM] Initial save failed: \(error)")
        }

        do {
            try await watchSessionManager?.requestAuthorization()
            try await watchSessionManager?.startWorkoutSession()
        } catch {
            print("[WatchWorkoutVM] HealthKit session start failed: \(error)")
        }

        connectivityManager.sendWorkoutStarted(activeWorkout ?? workout)
    }

    public func startWorkout(name: String, from template: WorkoutTemplate) async {
        isQuickStart = false

        let workoutExercises = template.exercises.sorted { $0.order < $1.order }.enumerated().map { index, te in
            let sets = (0..<te.targetSets).map { setIndex in
                let target = te.setTargets.indices.contains(setIndex) ? te.setTargets[setIndex] : nil
                let resolvedSetType: SetType = {
                    if let t = target, t.setType != .normal { return t.setType }
                    return te.isWarmUp ? .warmup : .normal
                }()
                return ExerciseSet(
                    id: UUID(),
                    order: setIndex + 1,
                    setType: resolvedSetType,
                    weight: target?.targetWeight ?? te.targetWeight,
                    reps: target?.targetReps ?? te.targetReps,
                    durationSeconds: target?.targetDurationSeconds ?? te.targetDurationSeconds,
                    distanceMeters: target?.targetDistanceMeters ?? te.targetDistanceMeters,
                    rpe: nil,
                    isCompleted: false,
                    isPersonalRecord: false,
                    completedAt: nil
                )
            }
            return WorkoutExercise(
                id: UUID(),
                exercise: te.exercise,
                order: index + 1,
                supersetGroup: te.supersetGroup,
                notes: te.notes,
                restTimerSeconds: te.restTimerSeconds,
                sets: sets
            )
        }

        // Store per-exercise targets
        for (index, te) in template.exercises.sorted(by: { $0.order < $1.order }).enumerated() {
            plannedSetsPerExercise[index] = te.targetSets
            targetWeightPerExercise[index] = te.targetWeight
            targetRepsPerExercise[index] = te.targetReps
        }

        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: template.id,
            exercises: workoutExercises
        )

        // Set state immediately so navigation pushes without waiting for save
        activeWorkout = workout
        currentExerciseIndex = 0
        isActive = true

        // Persist and start HealthKit in background
        do {
            let saved = try await workoutRepository.save(workout)
            activeWorkout = saved
        } catch {
            print("[WatchWorkoutVM] Initial save failed: \(error)")
        }

        do {
            try await watchSessionManager?.requestAuthorization()
            try await watchSessionManager?.startWorkoutSession()
        } catch {
            print("[WatchWorkoutVM] HealthKit session start failed: \(error)")
        }

        connectivityManager.sendWorkoutStarted(workout)
    }

    /// Start a workout from a planned session (progression plan sync from iPhone).
    public func startPlannedSession(_ session: PlannedSessionSync) async {
        plannedSessionId = session.id
        plannedPlanId = session.planId
        await startWorkout(name: session.sessionLabel, from: session.template)
    }

    public func logSet(weight: Double?, reps: Int?, rpe: Double? = nil) async throws {
        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard currentExerciseIndex < workout.exercises.count else {
            throw WorkoutError.exerciseNotFound
        }

        // If there's an incomplete pre-populated set, update it instead of appending
        if let incompleteIndex = workout.exercises[currentExerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) {
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].weight = weight
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].reps = reps
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].rpe = rpe
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].isCompleted = true
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].completedAt = Date()
        } else {
            // All pre-populated sets done (or none existed), append a new one
            let setOrder = workout.exercises[currentExerciseIndex].sets.count + 1
            let newSet = ExerciseSet(
                id: UUID(),
                order: setOrder,
                setType: pendingSetType,
                weight: weight,
                reps: reps,
                durationSeconds: nil,
                distanceMeters: nil,
                rpe: rpe,
                isCompleted: true,
                isPersonalRecord: false,
                completedAt: Date()
            )
            workout.exercises[currentExerciseIndex].sets.append(newSet)
        }

        activeWorkout = workout
        viewingSetIndex = nil
        pendingSetType = .normal

        // Send live snapshot to iPhone
        connectivityManager.sendWorkoutSnapshot(workout)

        // Auto-start rest timer after logging a set (uses per-exercise override if set)
        let exercise = workout.exercises[currentExerciseIndex]
        startRestTimer(seconds: exercise.restTimerSeconds)
    }

    public func removeSet(at exerciseIndex: Int, setIndex: Int) {
        guard var workout = activeWorkout,
              exerciseIndex < workout.exercises.count,
              setIndex < workout.exercises[exerciseIndex].sets.count else {
            return
        }

        workout.exercises[exerciseIndex].sets.remove(at: setIndex)

        // Re-order remaining sets
        for i in 0..<workout.exercises[exerciseIndex].sets.count {
            workout.exercises[exerciseIndex].sets[i].order = i + 1
        }

        activeWorkout = workout
    }

    public func removeSetFromCurrentExercise(at setIndex: Int) {
        removeSet(at: currentExerciseIndex, setIndex: setIndex)
    }

    public func completeWorkout() async throws {
        guard !isCompleting else { return }
        isCompleting = true
        defer {
            isCompleting = false
            // Always pop navigation so user is never stuck
            isActive = false
        }

        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        workout.completedAt = Date()
        if !workoutNotes.isEmpty {
            workout.notes = workoutNotes
        }
        var saved = try await workoutRepository.save(workout)
        stopRestTimer()

        // End HealthKit workout session BEFORE setting isActive = false.
        do {
            try await watchSessionManager?.endWorkoutSession()
        } catch {
            print("[WatchWorkoutVM] HealthKit session end failed: \(error)")
        }

        // Attach the Watch's HKWorkout UUID so iPhone can add calorie data to it
        if let hkUUID = watchSessionManager?.finishedWorkoutUUID {
            saved.healthKitWorkoutId = hkUUID
            saved = (try? await workoutRepository.save(saved)) ?? saved
        }

        activeWorkout = saved

        // Notify iPhone workout ended, then send full workout via transferUserInfo
        connectivityManager.sendWorkoutEnded()
        var metadata: [String: String]? = nil
        if let sid = plannedSessionId, let pid = plannedPlanId {
            metadata = [
                "plannedSessionId": sid.uuidString,
                "plannedPlanId": pid.uuidString
            ]
        }
        connectivityManager.sendWorkoutCompleted(saved, metadata: metadata)
        plannedSessionId = nil
        plannedPlanId = nil

        // Vectorize workout for analytics in background
        Task {
            let bodyWeightKg = userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
            try? await analyticsService?.vectorizeWorkout(saved, bodyWeightKg: bodyWeightKg)
        }
    }

    public func cancelWorkout() async {
        guard !isCompleting else { return }
        isCompleting = true
        defer {
            isCompleting = false
            isActive = false
        }

        stopRestTimer()

        await watchSessionManager?.discardWorkoutSession()

        if let workout = activeWorkout {
            try? await workoutRepository.delete(workout)
        }

        activeWorkout = nil
        currentExerciseIndex = 0
        workoutNotes = ""

        connectivityManager.sendWorkoutEnded()
        plannedSessionId = nil
        plannedPlanId = nil
    }

    // MARK: - Navigation

    public func nextExercise() {
        guard let workout = activeWorkout else { return }
        if currentExerciseIndex < workout.exercises.count - 1 {
            viewingSetIndex = nil
            pendingSetType = .normal
            currentExerciseIndex += 1
        }
    }

    public func previousExercise() {
        if currentExerciseIndex > 0 {
            viewingSetIndex = nil
            pendingSetType = .normal
            currentExerciseIndex -= 1
        }
    }

    // MARK: - Set Navigation

    public func navigateToPreviousSet() {
        guard let exercise = currentExercise else { return }
        let completedCount = exercise.sets.filter(\.isCompleted).count
        if viewingSetIndex == nil {
            // From active set, go to last completed
            if completedCount > 0 {
                viewingSetIndex = completedCount - 1
            }
        } else if let idx = viewingSetIndex, idx > 0 {
            viewingSetIndex = idx - 1
        }
    }

    public func navigateToNextSet() {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise else { return }
        let completedCount = exercise.sets.filter(\.isCompleted).count
        if idx < completedCount - 1 {
            viewingSetIndex = idx + 1
        } else {
            viewingSetIndex = nil
        }
    }

    public var currentSetType: SetType {
        guard let exercise = currentExercise else { return pendingSetType }
        if let idx = viewingSetIndex, idx < exercise.sets.count {
            return exercise.sets[idx].setType
        }
        if let nextIncomplete = exercise.sets.first(where: { !$0.isCompleted }) {
            return nextIncomplete.setType
        }
        return pendingSetType
    }

    public func updateSetType(setType: SetType) {
        guard var workout = activeWorkout,
              currentExerciseIndex < workout.exercises.count else { return }
        if let idx = viewingSetIndex,
           idx < workout.exercises[currentExerciseIndex].sets.count {
            workout.exercises[currentExerciseIndex].sets[idx].setType = setType
            activeWorkout = workout
        } else if let incompleteIdx = workout.exercises[currentExerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) {
            workout.exercises[currentExerciseIndex].sets[incompleteIdx].setType = setType
            activeWorkout = workout
        } else {
            // No set exists yet (quick-start) — store for next logSet()
            pendingSetType = setType
        }
    }

    public func updateSet(weight: Double?, reps: Int?) {
        guard let idx = viewingSetIndex,
              var workout = activeWorkout,
              currentExerciseIndex < workout.exercises.count,
              idx < workout.exercises[currentExerciseIndex].sets.count else { return }
        workout.exercises[currentExerciseIndex].sets[idx].weight = weight
        workout.exercises[currentExerciseIndex].sets[idx].reps = reps
        activeWorkout = workout
        viewingSetIndex = nil

        // Send updated snapshot to iPhone
        connectivityManager.sendWorkoutSnapshot(workout)
    }

    // MARK: - Rest Timer

    /// Start rest timer with optional per-exercise duration override
    public func startRestTimer(seconds: Int? = nil) {
        // Respect autoStartRestTimer preference
        guard userPreferencesService?.autoStartRestTimer ?? true else { return }

        stopRestTimer()

        let duration = seconds
            ?? userPreferencesService?.defaultRestSeconds
            ?? UserPreferencesService.defaultRestSecondsValue
        restDuration = TimeInterval(duration)
        isResting = true
        restTimeRemaining = restDuration
        restStartDate = Date()

        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.restStartDate else { return }
                let elapsed = Date().timeIntervalSince(start)
                let remaining = self.restDuration - elapsed
                if remaining > 0 {
                    self.restTimeRemaining = remaining
                } else {
                    self.restTimeRemaining = 0
                    self.restTimerCompleted()
                }
            }
        }
    }

    public func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        restStartDate = nil
        isResting = false
        restTimeRemaining = 0
    }

    /// Called when timer naturally expires — plays haptic then stops
    private func restTimerCompleted() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
        stopRestTimer()
    }

    public func skipRestTimer() {
        stopRestTimer()
    }
}
