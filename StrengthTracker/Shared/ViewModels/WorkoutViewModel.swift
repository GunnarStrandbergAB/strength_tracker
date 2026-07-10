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
    public var plannedSessionId: UUID? = nil
    public var plannedPlanId: UUID? = nil
    public var errorMessage: String? = nil
    public var lastPR: PersonalRecord? = nil
    public var previousSetDataCache: [String: String] = [:]
    public var watchActiveWorkout: Workout? = nil
    public var postWorkoutDebrief: PostWorkoutDebrief? = nil
    public var showPostWorkoutSummary = false
    public var exerciseCoachingCache: [UUID: ExerciseCoachingData] = [:]

    /// Adaptive progression hook: when set, planned-session completions are routed through
    /// the full pipeline (ProgressionPlanViewModel.handleSessionCompleted) instead of the
    /// plain markSessionCompleted repository call.
    public var onPlannedSessionCompleted: ((_ sessionId: UUID, _ planId: UUID, _ workoutId: UUID) async -> Void)?

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
        weightSuggestionService: WeightSuggestionService? = nil
    ) {
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
        do {
            currentWorkout = try await workoutRepository.save(workout)
            // Refresh coaching data — suppresses/restores "Try" text
            exerciseCoachingCache.removeAll()
            await loadCoachingData()
        } catch {
            currentWorkout = workout
        }
    }

    public func startWorkout(name: String, from template: WorkoutTemplate? = nil, isDeload: Bool = false) async {
        try? await workoutRepository.deleteAllIncomplete()

        var exercises: [WorkoutExercise] = []

        if let template = template {
            exercises = template.exercises.sorted(by: { $0.order < $1.order }).enumerated().map { index, te in
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
        }

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
            Self.hasPendingActiveWorkout = true

            // Update template usage stats
            if let template = template {
                try? await templateRepository.incrementUsage(template.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addExercise(_ exercise: Exercise) {
        guard var workout = currentWorkout else { return }
        let order = workout.exercises.count + 1
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: []
        )
        workout.exercises.append(workoutExercise)
        currentWorkout = workout

        Task {
            await loadPreviousDataForExercise(workoutExercise.id)
        }
    }

    public func logSet(exerciseId: UUID, weight: Double?, reps: Int?, setType: SetType = .normal) async throws {
        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.exercise.id == exerciseId }) else {
            throw WorkoutError.exerciseNotFound
        }

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
        workout = try await workoutRepository.save(workout)
        currentWorkout = workout

        // Check for personal records (skip during deload — intentionally lighter)
        if let prService = personalRecordService, !(currentWorkout?.isDeload ?? false) {
            let exercise = workout.exercises[exerciseIndex].exercise
            if let pr = try? await prService.checkForPR(exercise: exercise, set: newSet) {
                lastPR = pr
            }
        }
    }

    public func removeSet(exerciseId: UUID, setId: UUID) async {
        guard var workout = currentWorkout else { return }
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        workout.exercises[exerciseIndex].sets.removeAll { $0.id == setId }
        // Re-number set orders
        for i in workout.exercises[exerciseIndex].sets.indices {
            workout.exercises[exerciseIndex].sets[i].order = i + 1
        }
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    public func removeExercise(exerciseId: UUID) async {
        guard var workout = currentWorkout else { return }
        workout.exercises.removeAll { $0.id == exerciseId }
        // Re-number orders
        for i in workout.exercises.indices {
            workout.exercises[i].order = i + 1
        }
        currentWorkout = workout  // Immediate UI update (optimistic)
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            // Already set above; save failed but local state is correct
        }
    }

    public func updateNotes(_ notes: String) async {
        guard var workout = currentWorkout else { return }
        workout.notes = notes.isEmpty ? nil : notes
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
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
        Self.hasPendingActiveWorkout = false

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
            let bodyWeightKg = await resolveBodyWeightKg()
            if let bw = bodyWeightKg {
                let result = calorieEstimationService.estimateCalories(workout: saved, bodyWeightKg: bw)
                try? await healthKitService.saveWorkout(saved, calories: result.totalCalories)
            } else {
                try? await healthKitService.saveWorkout(saved)
            }
        }
        #endif

        // Vectorize workout for analytics, then generate post-workout debrief
        Task {
            let bodyWeightKg = await resolveBodyWeightKg() ?? UserPreferencesService.defaultBodyWeightKg
            try? await analyticsService?.vectorizeWorkout(saved, bodyWeightKg: bodyWeightKg)

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

    /// Resolve body weight via fallback chain: HealthKit → UserPreferences → nil
    private func resolveBodyWeightKg() async -> Double? {
        // Try HealthKit first
        if let hkWeight = await healthKitService.fetchBodyWeightKg() {
            return hkWeight
        }
        // Fallback to user preference
        return userPreferencesService?.bodyWeightKg
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

    /// Load previous data for all exercises when workout starts
    public func loadPreviousData() async {
        guard let workout = currentWorkout else { return }
        for exercise in workout.exercises {
            await loadPreviousDataForExercise(exercise.id)
        }
    }

    /// Load coaching data (weight suggestions, effort creep) for all exercises.
    public func loadCoachingData() async {
        guard let workout = currentWorkout, let wss = weightSuggestionService else { return }
        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            let recentCompleted = allWorkouts
                .filter { $0.completedAt != nil && $0.id != workout.id }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            guard recentCompleted.count >= 3 else { return }

            for we in workout.exercises {
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
                        isDeload: workout.isDeload
                    ) {
                        suggestions[setIndex] = suggestion
                    }
                }

                let effortCreep = wss.checkEffortCreep(
                    exerciseId: exerciseId,
                    exerciseName: we.exercise.name,
                    recentWorkouts: recentCompleted
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
        for (index, _) in exercise.sets.enumerated() {
            let key = "\(exercise.id)-\(index)"
            if previousSetDataCache[key] == nil {
                if let data = await previousSetData(for: exercise.id, setIndex: index) {
                    previousSetDataCache[key] = data
                }
            }
        }
    }

    // MARK: - Inline Editing Methods

    /// Add an empty (incomplete) set to an exercise for the inline editing workflow.
    public func addEmptySet(exerciseId: UUID) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else {
            return
        }

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
        do {
            currentWorkout = try await workoutRepository.save(workout)
            await loadPreviousDataForExercise(exerciseId)
        } catch {
            currentWorkout = workout
        }
    }

    /// Find-mutate-save helper shared by the per-set editing methods below.
    private func mutateSet(exerciseId: UUID, setId: UUID, _ mutate: (inout ExerciseSet) -> Void) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        mutate(&workout.exercises[exerciseIndex].sets[setIndex])
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    /// Update the weight of a specific set within an exercise.
    public func updateSetWeight(exerciseId: UUID, setId: UUID, weight: Double?) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            // Parent fields of a grouped drop set mirror its top segment — edit the segment instead.
            guard set.dropSets.isEmpty else { return }
            set.weight = weight
        }
    }

    /// Update the reps of a specific set within an exercise.
    public func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async {
        await mutateSet(exerciseId: exerciseId, setId: setId) { set in
            guard set.dropSets.isEmpty else { return }
            set.reps = reps
        }
    }

    /// Update the RPE of a specific set within an exercise.
    public func updateSetRPE(exerciseId: UUID, setId: UUID, rpe: Double?) async {
        await updateSetIntensity(exerciseId: exerciseId, setId: setId, value: rpe, metric: .rpe)
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
        guard var workout = currentWorkout else { return }
        guard workout.toggleSetCompletion(exerciseId: exerciseId, setId: setId) != nil else { return }
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
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
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    public func updateExerciseNotes(exerciseId: UUID, notes: String) async {
        guard var workout = currentWorkout,
              let idx = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        workout.exercises[idx].notes = notes.isEmpty ? nil : notes
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
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
        try? await workoutRepository.deleteAllIncomplete()
        currentWorkout = nil
        isActive = false
        plannedSessionId = nil
        plannedPlanId = nil
        Self.hasPendingActiveWorkout = false
    }
}
