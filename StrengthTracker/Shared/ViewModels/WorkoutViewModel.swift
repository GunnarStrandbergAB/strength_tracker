import Foundation
import Observation

public enum WorkoutError: Error, Sendable {
    case noActiveWorkout
    case exerciseNotFound
}

@MainActor
@Observable
public final class WorkoutViewModel {
    /// Synchronous flag used by the iOS app on cold launch to decide whether to gate
    /// the first frame on `restoreActiveWorkout()`. Avoids drawing the Dashboard
    /// momentarily before async restoration flips routing to ActiveWorkout.
    private static let pendingActiveWorkoutKey = "st.hasPendingActiveWorkout"
    public static var hasPendingActiveWorkout: Bool {
        get { UserDefaults.standard.bool(forKey: pendingActiveWorkoutKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingActiveWorkoutKey) }
    }

    public var currentWorkout: Workout? = nil
    public var isActive = false

    /// Last exercise the user interacted with (completed or edited a set). Drives the
    /// in-app card highlight, the widget's "current exercise", and rest-timer context.
    /// Not persisted — restored from set `completedAt` timestamps on relaunch.
    public var activeExerciseId: UUID? = nil

    /// The resolved active exercise — the last-interacted one for as long as it
    /// exists in the workout, with a first-incomplete fallback.
    public var activeExercise: WorkoutExercise? {
        currentWorkout?.activeExercise(preferredId: activeExerciseId)
    }

    public var plannedSessionId: UUID? = nil
    public var plannedPlanId: UUID? = nil
    public var errorMessage: String? = nil
    public var lastPR: PersonalRecord? = nil
    public var previousSetDataCache: [String: String] = [:]
    public var watchActiveWorkout: Workout? = nil
    public var postWorkoutDebrief: PostWorkoutDebrief? = nil
    public var showPostWorkoutSummary = false
    public var exerciseCoachingCache: [UUID: ExerciseCoachingData] = [:]
    /// Message of the most recent failed persist, nil after a successful one.
    /// Mutators keep the optimistic in-memory state on failure; callers that must
    /// know whether the write landed (the AI editors) read this after each call.
    public private(set) var lastSaveError: String? = nil

    /// Adaptive progression hook: when set, planned-session completions are routed through
    /// the full pipeline (ProgressionPlanViewModel.handleSessionCompleted) instead of the
    /// plain markSessionCompleted repository call.
    public var onPlannedSessionCompleted: ((_ sessionId: UUID, _ planId: UUID, _ workoutId: UUID) async -> Void)?

    /// The post-completion pipeline (vector, PRs, HealthKit, webhook, revision, widgets).
    /// Set by AppContainer; when nil (tests) the legacy inline sequence runs.
    public var finalizer: WorkoutFinalizer?

    /// Stores original set weights before deload reduction, keyed by exerciseId → setId → weight
    private var preDeloadWeights: [UUID: [UUID: Double?]]?

    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let personalRecordService: PersonalRecordService?
    private let healthKitService: any HealthKitServiceProtocol
    private let calorieEstimationService: CalorieEstimationService
    public let userPreferencesService: UserPreferencesService?
    private let analyticsService: WorkoutAnalyticsService?
    private let webhookService: WebhookService?
    private let progressionPlanRepository: (any ProgressionPlanRepository)?
    private let coachingInsightService: CoachingInsightService?
    private let weightSuggestionService: WeightSuggestionService?
    private let bodyWeightProvider: BodyWeightProvider?

    /// Single resolved body weight (HealthKit → prefs → default) shared with every screen.
    private var bodyWeightKg: Double {
        bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    public init(
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        personalRecordService: PersonalRecordService? = nil,
        healthKitService: any HealthKitServiceProtocol,
        calorieEstimationService: CalorieEstimationService = CalorieEstimationService(),
        userPreferencesService: UserPreferencesService? = nil,
        analyticsService: WorkoutAnalyticsService? = nil,
        webhookService: WebhookService? = nil,
        progressionPlanRepository: (any ProgressionPlanRepository)? = nil,
        coachingInsightService: CoachingInsightService? = nil,
        weightSuggestionService: WeightSuggestionService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil
    ) {
        self.bodyWeightProvider = bodyWeightProvider
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.personalRecordService = personalRecordService
        self.healthKitService = healthKitService
        self.calorieEstimationService = calorieEstimationService
        self.userPreferencesService = userPreferencesService
        self.analyticsService = analyticsService
        self.webhookService = webhookService
        self.progressionPlanRepository = progressionPlanRepository
        self.coachingInsightService = coachingInsightService
        self.weightSuggestionService = weightSuggestionService
    }

    public func toggleDeload() async {
        guard var workout = currentWorkout else { return }

        if workout.isDeload {
            // Toggling OFF — restore original weights
            if let originals = preDeloadWeights {
                for i in workout.exercises.indices {
                    let exerciseId = workout.exercises[i].id
                    if let exerciseOriginals = originals[exerciseId] {
                        for j in workout.exercises[i].sets.indices {
                            let setId = workout.exercises[i].sets[j].id
                            if let original = exerciseOriginals[setId] {
                                workout.exercises[i].sets[j].weight = original
                            }
                        }
                    }
                }
            }
            preDeloadWeights = nil
        } else {
            // Toggling ON — save originals, apply deload reduction
            let pct = Double(userPreferencesService?.deloadWeightPercentage ?? 50) / 100.0
            var originals: [UUID: [UUID: Double?]] = [:]
            for i in workout.exercises.indices {
                var exerciseOriginals: [UUID: Double?] = [:]
                for j in workout.exercises[i].sets.indices {
                    let set = workout.exercises[i].sets[j]
                    exerciseOriginals[set.id] = set.weight
                    if let w = set.weight, !set.isCompleted {
                        workout.exercises[i].sets[j].weight = (w * pct).rounded(toNearest: 2.5)
                    }
                }
                originals[workout.exercises[i].id] = exerciseOriginals
            }
            preDeloadWeights = originals
        }

        workout.isDeload.toggle()
        await persist(workout)
        if lastSaveError == nil {
            // Refresh coaching data — suppresses/restores "Try" text
            exerciseCoachingCache.removeAll()
            await loadCoachingData()
        }
    }

    /// Idempotent deload flag setter (the UI toggle stays `toggleDeload`).
    public func setDeload(_ isDeload: Bool) async {
        guard let workout = currentWorkout, workout.isDeload != isDeload else { return }
        await toggleDeload()
    }

    public func startWorkout(name: String, from template: WorkoutTemplate? = nil, isDeload: Bool = false) async {
        try? await workoutRepository.deleteAllIncomplete()

        let exercises: [WorkoutExercise] = template?.instantiateExercises() ?? []

        var workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: template?.id,
            isDeload: isDeload,
            plannedSessionId: plannedSessionId,
            plannedPlanId: plannedPlanId,
            exercises: exercises
        )

        do {
            workout = try await workoutRepository.save(workout)
            currentWorkout = workout
            isActive = true
            activeExerciseId = nil
            Self.hasPendingActiveWorkout = true

            // Update template usage stats
            if let template = template {
                try? await templateRepository.incrementUsage(template.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// UI entry point: optimistic append now, persisted in the background.
    public func addExercise(_ exercise: Exercise) {
        guard let (workout, workoutExercise) = appendExerciseOptimistically(exercise, sets: [], restTimerSeconds: nil, notes: nil) else { return }
        Task { [workout] in
            // Persist right away — without this the new exercise lives only in memory
            // until the next unrelated save and is lost if the app is killed.
            await persist(workout)
            await loadPreviousDataForExercise(workoutExercise.id)
        }
    }

    /// Appends an exercise (optionally with pre-built sets, renumbered here) and
    /// awaits the save so a following mutation cannot race a stale snapshot.
    @discardableResult
    public func addExercise(
        _ exercise: Exercise,
        sets: [ExerciseSet],
        restTimerSeconds: Int? = nil,
        notes: String? = nil
    ) async -> WorkoutExercise? {
        guard let (workout, workoutExercise) = appendExerciseOptimistically(
            exercise, sets: sets, restTimerSeconds: restTimerSeconds, notes: notes
        ) else { return nil }
        await persist(workout)
        await loadPreviousDataForExercise(workoutExercise.id)
        return currentWorkout?.exercises.first { $0.id == workoutExercise.id }
    }

    private func appendExerciseOptimistically(
        _ exercise: Exercise, sets: [ExerciseSet], restTimerSeconds: Int?, notes: String?
    ) -> (Workout, WorkoutExercise)? {
        guard var workout = currentWorkout else { return nil }
        var numbered = sets
        for i in numbered.indices { numbered[i].order = i + 1 }
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: workout.exercises.count + 1,
            supersetGroup: nil,
            notes: notes,
            restTimerSeconds: restTimerSeconds,
            sets: numbered
        )
        workout.exercises.append(workoutExercise)
        currentWorkout = workout  // Immediate UI update (optimistic)
        activeExerciseId = workoutExercise.id
        return (workout, workoutExercise)
    }

    /// Swaps the exercise of a logged WorkoutExercise while keeping its id, order,
    /// notes and every set. Per-set PR flags are cleared (they belonged to the old exercise).
    public func replaceExercise(exerciseId: UUID, with exercise: Exercise) async {
        guard var workout = currentWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              workout.exercises[ei].exercise.id != exercise.id else { return }
        workout.exercises[ei].exercise = exercise
        for si in workout.exercises[ei].sets.indices {
            workout.exercises[ei].sets[si].isPersonalRecord = false
        }
        exerciseCoachingCache[exerciseId] = nil
        await persist(workout)
        await loadPreviousDataForExercise(exerciseId)
    }

    public func updateExerciseRestTimer(exerciseId: UUID, seconds: Int?) async {
        guard var workout = currentWorkout,
              let idx = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        workout.exercises[idx].restTimerSeconds = seconds
        await persist(workout)
    }

    /// Move an exercise card to a new position, renumbering the persisted 1-based
    /// `order` field (SwiftData's relationship is unordered — `order` is the truth).
    public func moveExercise(from source: Int, to destination: Int) async {
        guard var workout = currentWorkout,
              source >= 0, source < workout.exercises.count,
              destination >= 0, destination < workout.exercises.count,
              source != destination else { return }
        let exercise = workout.exercises.remove(at: source)
        workout.exercises.insert(exercise, at: destination)
        for i in workout.exercises.indices {
            workout.exercises[i].order = i + 1
        }
        currentWorkout = workout  // Immediate UI update (optimistic)
        await persist(workout)
    }

    public func logSet(exerciseId: UUID, weight: Double?, reps: Int?, setType: SetType = .normal) async throws {
        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.exercise.id == exerciseId }) else {
            throw WorkoutError.exerciseNotFound
        }

        activeExerciseId = workout.exercises[exerciseIndex].id
        let setOrder = workout.exercises[exerciseIndex].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )

        workout.exercises[exerciseIndex].sets.append(newSet)
        // Live PR check flags the set before the single save (skipped on deload).
        await evaluatePR(in: &workout, exerciseId: workout.exercises[exerciseIndex].id, setId: newSet.id)
        workout = try await workoutRepository.save(workout)
        currentWorkout = workout
    }

    public func removeSet(exerciseId: UUID, setId: UUID) async {
        guard var workout = currentWorkout else { return }
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        activeExerciseId = exerciseId
        workout.exercises[exerciseIndex].sets.removeAll { $0.id == setId }
        // Re-number set orders
        for i in workout.exercises[exerciseIndex].sets.indices {
            workout.exercises[exerciseIndex].sets[i].order = i + 1
        }
        await persist(workout)
    }

    public func removeExercise(exerciseId: UUID) async {
        guard var workout = currentWorkout else { return }
        if activeExerciseId == exerciseId { activeExerciseId = nil }
        workout.exercises.removeAll { $0.id == exerciseId }
        // Re-number orders
        for i in workout.exercises.indices {
            workout.exercises[i].order = i + 1
        }
        currentWorkout = workout  // Immediate UI update (optimistic)
        await persist(workout)
    }

    public func updateNotes(_ notes: String) async {
        guard var workout = currentWorkout else { return }
        workout.notes = notes.isEmpty ? nil : notes
        await persist(workout)
    }

    public func completeWorkout() async throws {
        // Allow pending UI debounces (400ms) to flush before finalizing
        try? await Task.sleep(for: .milliseconds(500))

        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        workout.completedAt = Date()
        let saved = try await workoutRepository.save(workout)
        currentWorkout = saved
        isActive = false
        activeExerciseId = nil
        Self.hasPendingActiveWorkout = false

        if let finalizer {
            plannedSessionId = nil
            plannedPlanId = nil
            Task {
                let finalized = await finalizer.workoutCompleted(saved, source: .phone)
                if currentWorkout?.id == finalized.id { currentWorkout = finalized }
                if let coaching = coachingInsightService, let analytics = analyticsService {
                    await generateDebrief(workout: finalized, analyticsService: analytics, coachingService: coaching, bodyWeightKg: bodyWeightKg)
                }
            }
            return
        }

        // Legacy inline sequence (no finalizer injected).
        // Mark progression plan session completed.
        // Prefer the IDs persisted on the workout itself so this works even if the VM was
        // reset/rebuilt mid-workout (e.g., the app was killed and resumed).
        if let sessionId = saved.plannedSessionId ?? plannedSessionId,
           let planId = saved.plannedPlanId ?? plannedPlanId {
            let workoutId = saved.id
            if let onPlannedSessionCompleted {
                await onPlannedSessionCompleted(sessionId, planId, workoutId)
            } else {
                try? await progressionPlanRepository?.markSessionCompleted(
                    sessionId, workoutId: workoutId, inPlan: planId
                )
            }
            plannedSessionId = nil
            plannedPlanId = nil
        }

        // Save to HealthKit with calorie estimation (iPhone-only path)
        #if canImport(HealthKit)
        Task {
            let bw = bodyWeightKg
            let result = calorieEstimationService.estimateCalories(workout: saved, bodyWeightKg: bw)
            try? await healthKitService.saveWorkout(saved, calories: result.totalCalories, bodyWeightKg: bw)
        }
        #endif

        // Vectorize workout for analytics, then generate post-workout debrief
        Task {
            let bodyWeightKg = self.bodyWeightKg
            try? await analyticsService?.vectorizeWorkout(saved)

            // Generate post-workout debrief after vectorization completes
            if let coaching = coachingInsightService, let analytics = analyticsService {
                await generateDebrief(workout: saved, analyticsService: analytics, coachingService: coaching, bodyWeightKg: bodyWeightKg)
            }
        }

        // Send to webhook in background (fire-and-forget)
        Task {
            await webhookService?.send(saved)
        }
    }

    private func generateDebrief(
        workout: Workout,
        analyticsService: WorkoutAnalyticsService,
        coachingService: CoachingInsightService,
        bodyWeightKg: Double
    ) async {
        do {
            let insights = try await analyticsService.generateInsights()
            let allWorkouts = try await workoutRepository.fetchAll()
            let allVectors = try await analyticsService.fetchAllVectors()
            let currentVector = allVectors.first { $0.workoutId == workout.id }

            // Try to compute quality score for this workout
            let qualityScore: WorkoutQualityScore? = nil  // scored async elsewhere if available

            let debrief = await coachingService.generatePostWorkoutDebrief(
                workout: workout,
                allWorkouts: allWorkouts,
                overloadTrends: insights.overloadTrends,
                qualityScore: qualityScore,
                recoveryPatterns: insights.recoveryPatterns,
                trainingLoad: insights.trainingLoad,
                optimalVolumes: insights.optimalVolumes,
                currentVector: currentVector,
                allVectors: allVectors,
                bodyWeightKg: bodyWeightKg
            )
            postWorkoutDebrief = debrief
            showPostWorkoutSummary = true
        } catch {
            // Debrief is best-effort; don't show if it fails
        }
    }


    /// Fetch previous set data for an exercise to help with progressive overload
    public func previousSetData(for exerciseId: UUID, setIndex: Int) async -> String? {
        // Get the exercise ID from the current workout's exercise
        guard let currentWorkout = currentWorkout,
              let workoutExercise = currentWorkout.exercises.first(where: { $0.id == exerciseId }) else {
            return nil
        }

        let targetExerciseId = workoutExercise.exercise.id

        // Fetch recent completed workouts
        #if canImport(SwiftData)
        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            // Find last completed workout with this exercise (not the current one)
            let previousWorkout = allWorkouts
                .filter { $0.completedAt != nil && $0.id != currentWorkout.id }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                .first { workout in
                    workout.exercises.contains { $0.exercise.id == targetExerciseId }
                }

            guard let prev = previousWorkout,
                  let prevExercise = prev.exercises.first(where: { $0.exercise.id == targetExerciseId }),
                  setIndex < prevExercise.sets.count else {
                return nil
            }

            let prevSet = prevExercise.sets[setIndex]
            let unit = userPreferencesService?.weightUnit ?? .kg
            let weight = prevSet.weight.map { unit.formatValue($0) } ?? "0"
            let reps = prevSet.reps.map { String($0) } ?? "0"
            return "\(weight)\(unit.symbol) × \(reps)"
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Load previous data for all exercises when workout starts.
    /// Fetches the history ONCE — a per-set fetch here used to block the main
    /// actor for seconds on workout entry, starving the first tap's render.
    public func loadPreviousData() async {
        guard let workout = currentWorkout else { return }
        guard let allWorkouts = try? await workoutRepository.fetchAll() else { return }
        let previousCompleted = allWorkouts
            .filter { $0.completedAt != nil && $0.id != workout.id }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        for exercise in workout.exercises {
            fillPreviousDataCache(for: exercise, from: previousCompleted)
            await Task.yield()  // let queued UI updates (e.g. a tap) get a frame
        }
    }

    /// Fill missing previous-set cache keys for one exercise from an already
    /// fetched, completed-and-sorted workout history.
    private func fillPreviousDataCache(for exercise: WorkoutExercise, from previousCompleted: [Workout]) {
        let missingIndices = exercise.sets.indices.filter {
            previousSetDataCache["\(exercise.id)-\($0)"] == nil
        }
        guard !missingIndices.isEmpty else { return }

        let targetExerciseId = exercise.exercise.id
        guard let prevExercise = previousCompleted
            .first(where: { workout in workout.exercises.contains { $0.exercise.id == targetExerciseId } })?
            .exercises.first(where: { $0.exercise.id == targetExerciseId }) else { return }

        let unit = userPreferencesService?.weightUnit ?? .kg
        for index in missingIndices where index < prevExercise.sets.count {
            let prevSet = prevExercise.sets[index]
            let weight = prevSet.weight.map { unit.formatValue($0) } ?? "0"
            let reps = prevSet.reps.map { String($0) } ?? "0"
            previousSetDataCache["\(exercise.id)-\(index)"] = "\(weight)\(unit.symbol) × \(reps)"
        }
    }

    /// Load coaching data (weight suggestions, effort creep) for all exercises.
    public func loadCoachingData() async {
        guard let workout = currentWorkout, let wss = weightSuggestionService else { return }
        let bodyWeightKg = self.bodyWeightKg
        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            // Suggestions scan recentWorkouts per set — cap the window so a long
            // history doesn't cost seconds of main-actor time on workout entry.
            let recentCompleted = Array(
                allWorkouts
                    .filter { $0.completedAt != nil && $0.id != workout.id }
                    .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                    .prefix(20)
            )
            guard recentCompleted.count >= 3 else { return }

            for we in workout.exercises {
                await Task.yield()  // keep the UI responsive during workout entry
                let exerciseId = we.exercise.id
                var suggestions: [Int: WeightSuggestion] = [:]
                for (setIndex, set) in we.sets.enumerated() {
                    let targetReps = set.reps ?? 8
                    if let suggestion = wss.suggest(
                        exerciseId: exerciseId,
                        exerciseName: we.exercise.name,
                        targetReps: targetReps,
                        recentWorkouts: recentCompleted,
                        overloadTrend: nil,
                        recoveryStatus: nil,
                        trainingLoad: nil,
                        isDeload: workout.isDeload,
                        bodyWeightKg: bodyWeightKg
                    ) {
                        suggestions[setIndex] = suggestion
                    }
                }

                let effortCreep = wss.checkEffortCreep(
                    exerciseId: exerciseId,
                    exerciseName: we.exercise.name,
                    recentWorkouts: recentCompleted,
                    bodyWeightKg: bodyWeightKg
                )

                if !suggestions.isEmpty || effortCreep != nil {
                    exerciseCoachingCache[we.id] = ExerciseCoachingData(
                        suggestions: suggestions,
                        effortCreepWarning: effortCreep
                    )
                }
            }
        } catch {
            // Coaching data is best-effort
        }
    }

    /// Load previous data for a single exercise (fills any missing cache keys)
    public func loadPreviousDataForExercise(_ exerciseId: UUID) async {
        guard let workout = currentWorkout,
              let exercise = workout.exercises.first(where: { $0.id == exerciseId }) else { return }
        let hasMissing = exercise.sets.indices.contains {
            previousSetDataCache["\(exercise.id)-\($0)"] == nil
        }
        guard hasMissing, let allWorkouts = try? await workoutRepository.fetchAll() else { return }
        let previousCompleted = allWorkouts
            .filter { $0.completedAt != nil && $0.id != workout.id }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        fillPreviousDataCache(for: exercise, from: previousCompleted)
    }

    // MARK: - Inline Editing Methods

    /// Add an empty (incomplete) set to an exercise for the inline editing workflow.
    public func addEmptySet(exerciseId: UUID) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else {
            return
        }

        activeExerciseId = exerciseId
        let setOrder = workout.exercises[exerciseIndex].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
            setType: .normal,
            weight: nil,
            reps: nil,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: false,
            isPersonalRecord: false,
            completedAt: nil
        )

        workout.exercises[exerciseIndex].sets.append(newSet)
        await persist(workout)
        if lastSaveError == nil {
            await loadPreviousDataForExercise(exerciseId)
        }
    }

    /// Find-mutate-save helper shared by the per-set editing methods below.
    private func mutateSet(exerciseId: UUID, setId: UUID, _ mutate: (inout ExerciseSet) -> Void) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        activeExerciseId = exerciseId
        mutate(&workout.exercises[exerciseIndex].sets[setIndex])
        await persist(workout)
    }

    /// Saves and publishes the result. On failure the optimistic copy stays in
    /// memory (the UI never loses the edit) and `lastSaveError` records why.
    private func persist(_ workout: Workout) async {
        lastSaveError = nil
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
            lastSaveError = error.localizedDescription
        }
    }

    /// Replaces every drop-set segment of a set (`[]` reverts it to a plain set).
    public func replaceDropSets(exerciseId: UUID, setId: UUID, entries: [DropSetEntry]) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            set.applyDropSets(entries)
        }
    }

    /// Appends pre-built sets (renumbered here) in one save. Returns the saved sets.
    @discardableResult
    public func appendSets(exerciseId: UUID, sets: [ExerciseSet]) async -> [ExerciseSet] {
        guard !sets.isEmpty,
              var workout = currentWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return [] }
        activeExerciseId = exerciseId
        var numbered = sets
        let base = workout.exercises[ei].sets.count
        for i in numbered.indices { numbered[i].order = base + i + 1 }
        workout.exercises[ei].sets.append(contentsOf: numbered)
        await persist(workout)
        if lastSaveError == nil {
            await loadPreviousDataForExercise(exerciseId)
        }
        let ids = Set(numbered.map(\.id))
        return currentWorkout?.exercises.first { $0.id == exerciseId }?.sets.filter { ids.contains($0.id) } ?? []
    }

    public func updateSetDuration(exerciseId: UUID, setId: UUID, seconds: Int?) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            set.durationSeconds = seconds
        }
    }

    public func updateSetDistance(exerciseId: UUID, setId: UUID, meters: Double?) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            set.distanceMeters = meters
        }
    }

    /// Update the weight of a specific set within an exercise.
    public func updateSetWeight(exerciseId: UUID, setId: UUID, weight: Double?) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            // Parent fields of a grouped drop set mirror its top segment — edit the segment instead.
            guard set.dropSets.isEmpty else { return }
            set.weight = weight
        }
        await reelectIfCompleted(exerciseId: exerciseId, setId: setId)
    }

    /// A completed set's load changed: its record status may have changed either way.
    private func reelectIfCompleted(exerciseId: UUID, setId: UUID) async {
        guard let set = currentWorkout?.exercises.first(where: { $0.id == exerciseId })?
                .sets.first(where: { $0.id == setId }), set.isCompleted else { return }
        await reelectPRs(exerciseId: exerciseId)
    }

    /// Update the reps of a specific set within an exercise.
    public func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            guard set.dropSets.isEmpty else { return }
            set.reps = reps
        }
        await reelectIfCompleted(exerciseId: exerciseId, setId: setId)
    }

    /// Update the intensity of a set in the given metric — stores the entered value
    /// and its derived counterpart (RPE↔RIR) together.
    public func updateSetIntensity(exerciseId: UUID, setId: UUID, value: Double?, metric: IntensityMetric) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { $0.applyIntensity(value, metric: metric) }
    }

    /// Toggle the per-set failure flag. One-way defaults: turning ON backfills RIR 0 /
    /// RPE 10 when no intensity was recorded; turning OFF never clears intensity.
    /// Legacy `.failure`-typed rows normalize to `.normal` + flag on first touch.
    public func toggleSetFailure(exerciseId: UUID, setId: UUID) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            let effective = set.isFailure || set.setType == .failure
            if set.setType == .failure { set.setType = .normal }
            set.setFailureFlag(!effective)
        }
    }

    /// Update the type of a specific set (normal, warmup, rest-pause).
    public func updateSetType(exerciseId: UUID, setId: UUID, setType: SetType) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            // A grouped drop set's type is managed by applyDropSets — never silently
            // destroy its segments by retyping it.
            guard set.dropSets.isEmpty else { return }
            set.setType = setType
        }
    }

    // MARK: - Drop Set Editing

    /// Convert a set into a grouped drop set (its current values become segment "a"
    /// plus an empty segment to fill in), or append one more empty segment if it
    /// already is one.
    public func addDropEntry(exerciseId: UUID, setId: UUID) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            if set.dropSets.isEmpty {
                let top = DropSetEntry(weight: set.weight, reps: set.reps, rpe: set.rpe, rir: set.rir, isFailure: set.isFailure)
                set.applyDropSets([top, DropSetEntry()])
            } else {
                set.applyDropSets(set.dropSets + [DropSetEntry()])
            }
        }
    }

    /// Remove one drop segment; when a single segment remains the set collapses back
    /// to a plain set carrying the survivor's values.
    public func removeDropEntry(exerciseId: UUID, setId: UUID, entryId: UUID) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            var entries = set.dropSets
            entries.removeAll { $0.id == entryId }
            if entries.count == 1, let survivor = entries.first {
                set.applyDropSets([survivor])
                set.applyDropSets([])
            } else {
                set.applyDropSets(entries)
            }
        }
    }

    public func updateDropEntryWeight(exerciseId: UUID, setId: UUID, entryId: UUID, weight: Double?) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.weight = weight }
    }

    public func updateDropEntryReps(exerciseId: UUID, setId: UUID, entryId: UUID, reps: Int?) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.reps = reps }
    }

    public func updateDropEntryIntensity(exerciseId: UUID, setId: UUID, entryId: UUID, value: Double?, metric: IntensityMetric) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.applyIntensity(value, metric: metric) }
    }

    public func toggleDropEntryFailure(exerciseId: UUID, setId: UUID, entryId: UUID) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.setFailureFlag(!$0.isFailure) }
    }

    private func mutateDropEntry(exerciseId: UUID, setId: UUID, entryId: UUID, _ mutate: (inout DropSetEntry) -> Void) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            guard let entryIndex = set.dropSets.firstIndex(where: { $0.id == entryId }) else { return }
            var entries = set.dropSets
            mutate(&entries[entryIndex])
            set.applyDropSets(entries)
        }
    }

    /// Toggle the completion status of a specific set.
    public func toggleSetCompletion(exerciseId: UUID, setId: UUID) async {
        guard var workout = currentWorkout,
              let nowCompleted = workout.toggleSetCompletion(exerciseId: exerciseId, setId: setId) else { return }
        activeExerciseId = exerciseId
        if nowCompleted {
            await evaluatePR(in: &workout, exerciseId: exerciseId, setId: setId)
            await persist(workout)
        } else {
            let hadRecord = workout.exercises.first { $0.id == exerciseId }?
                .sets.first { $0.id == setId }?.isPersonalRecord ?? false
            if hadRecord, let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
               let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) {
                workout.exercises[ei].sets[si].isPersonalRecord = false
            }
            await persist(workout)
            if hadRecord { await reelectPRs(exerciseId: exerciseId) }
        }
    }

    // MARK: - Personal records (live)

    /// Runs the live PR check on a just-completed set and flags it on `workout`.
    private func evaluatePR(in workout: inout Workout, exerciseId: UUID, setId: UUID) async {
        guard let prService = personalRecordService, !workout.isDeload,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        let exercise = workout.exercises[ei].exercise
        let set = workout.exercises[ei].sets[si]
        if let pr = try? await prService.checkForPR(exercise: exercise, set: set, isDeloadWorkout: workout.isDeload) {
            workout.exercises[ei].sets[si].isPersonalRecord = true
            lastPR = pr
        }
    }

    /// Authoritative re-election for one exercise (after an un-complete or an edit
    /// of a completed set); refreshes this workout's flags from the result.
    private func reelectPRs(exerciseId: UUID) async {
        guard let prService = personalRecordService,
              let current = currentWorkout,
              let exercise = current.exercises.first(where: { $0.id == exerciseId })?.exercise else { return }
        guard let changed = try? await prService.recalculatePRs(for: [exercise.id], includeInProgress: true) else { return }
        if let refreshed = changed[current.id] {
            currentWorkout = refreshed
        }
    }

    public func moveSets(exerciseId: UUID, from source: Int, to destination: Int) async {
        guard var workout = currentWorkout,
              let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let sets = workout.exercises[exerciseIndex].sets
        guard source >= 0, source < sets.count, destination >= 0, destination < sets.count, source != destination else { return }
        let set = workout.exercises[exerciseIndex].sets.remove(at: source)
        workout.exercises[exerciseIndex].sets.insert(set, at: destination)
        for i in workout.exercises[exerciseIndex].sets.indices {
            workout.exercises[exerciseIndex].sets[i].order = i + 1
        }
        await persist(workout)
    }

    public func updateExerciseNotes(exerciseId: UUID, notes: String) async {
        guard var workout = currentWorkout,
              let idx = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        workout.exercises[idx].notes = notes.isEmpty ? nil : notes
        await persist(workout)
    }

    // MARK: - Restore & Template Sync

    /// Restore an active (incomplete) workout from the database on app launch.
    public func restoreActiveWorkout() async {
        guard currentWorkout == nil, !isActive else { return }
        do {
            if let active = try await workoutRepository.fetchActive() {
                if Date().timeIntervalSince(active.startedAt) > 12 * 60 * 60 {
                    try? await workoutRepository.deleteAllIncomplete()
                    Self.hasPendingActiveWorkout = false
                    return
                }
                currentWorkout = active
                isActive = true
                activeExerciseId = active.lastInteractedExerciseId
                Self.hasPendingActiveWorkout = true
                await loadPreviousData()
            } else {
                Self.hasPendingActiveWorkout = false
            }
        } catch {
            print("[WorkoutVM] Failed to restore active workout: \(error)")
            Self.hasPendingActiveWorkout = false
        }
    }

    /// Whether the active workout was started from the given template.
    public func activeWorkoutUsesTemplate(_ templateId: UUID) -> Bool {
        isActive && currentWorkout?.templateId == templateId
    }

    /// Update uncompleted sets in the active workout to match new template values.
    public func updateUncompletedSetsFromTemplate(_ template: WorkoutTemplate) async {
        guard var workout = currentWorkout, workout.templateId == template.id else { return }
        let templateExercises = template.exercises.sorted { $0.order < $1.order }
        for (ei, we) in workout.exercises.enumerated() {
            guard let te = templateExercises.first(where: { $0.exercise.id == we.exercise.id }) else { continue }
            for (si, set) in we.sets.enumerated() where !set.isCompleted {
                let target = te.setTargets.indices.contains(si) ? te.setTargets[si] : nil
                workout.exercises[ei].sets[si].weight = target?.targetWeight ?? te.targetWeight
                workout.exercises[ei].sets[si].reps = target?.targetReps ?? te.targetReps
            }
        }
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cancel the current workout without saving completion.
    public func cancelWorkout() async {
        let cancelledExerciseIds = Set(currentWorkout?.exercises.map(\.exercise.id) ?? [])
        try? await workoutRepository.deleteAllIncomplete()
        // Live PRs from the discarded session must not linger.
        if !cancelledExerciseIds.isEmpty {
            _ = try? await personalRecordService?.recalculatePRs(for: cancelledExerciseIds)
        }
        currentWorkout = nil
        isActive = false
        activeExerciseId = nil
        plannedSessionId = nil
        plannedPlanId = nil
        Self.hasPendingActiveWorkout = false
    }
}
