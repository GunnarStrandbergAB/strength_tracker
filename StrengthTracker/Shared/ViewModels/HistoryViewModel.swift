import Foundation
import Observation

@MainActor
@Observable
public final class HistoryViewModel {
    public var workouts: [Workout] = []
    public var selectedWorkout: Workout? = nil
    public var isLoading = false
    public var isEditing = false
    public var errorMessage: String? = nil

    private let workoutRepository: any WorkoutRepository
    public let userPreferencesService: UserPreferencesService?
    private let templateRepository: (any TemplateRepository)?
    private let analyticsService: WorkoutAnalyticsService?
    private let personalRecordService: PersonalRecordService?
    private let healthKitService: (any HealthKitServiceProtocol)?
    private let calorieEstimationService: CalorieEstimationService?
    private let webhookService: WebhookService?
    private let widgetRefreshService: WidgetRefreshService?
    private let qualityScoreService: WorkoutQualityScoreService?

    /// Workouts retro-created this session that still owe their one-shot side effects
    /// (webhook + optional HealthKit save). Keyed by workout id; value = HealthKit opt-in.
    private var pendingRetroFinalization: [UUID: Bool] = [:]
    /// Set whenever an edit persists; lets endEditing() skip finalization for no-op sessions.
    private var hasUnsavedFinalization = false

    public init(
        workoutRepository: any WorkoutRepository,
        userPreferencesService: UserPreferencesService? = nil,
        templateRepository: (any TemplateRepository)? = nil,
        analyticsService: WorkoutAnalyticsService? = nil,
        personalRecordService: PersonalRecordService? = nil,
        healthKitService: (any HealthKitServiceProtocol)? = nil,
        calorieEstimationService: CalorieEstimationService? = nil,
        webhookService: WebhookService? = nil,
        widgetRefreshService: WidgetRefreshService? = nil,
        qualityScoreService: WorkoutQualityScoreService? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
        self.templateRepository = templateRepository
        self.analyticsService = analyticsService
        self.personalRecordService = personalRecordService
        self.healthKitService = healthKitService
        self.calorieEstimationService = calorieEstimationService
        self.webhookService = webhookService
        self.widgetRefreshService = widgetRefreshService
        self.qualityScoreService = qualityScoreService
    }

    public func loadHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await workoutRepository.fetchAll()
            workouts = all.filter { $0.completedAt != nil }
        } catch {
            errorMessage = error.localizedDescription
            workouts = []
        }
        isLoading = false
    }

    public func selectWorkout(_ workout: Workout) {
        selectedWorkout = workout
    }

    public func exerciseProgression(for exerciseId: UUID) -> [(date: Date, weight: Double, reps: Int)] {
        var results: [(date: Date, weight: Double, reps: Int)] = []

        for workout in workouts {
            for workoutExercise in workout.exercises {
                if workoutExercise.exercise.id == exerciseId {
                    let baseLoad = workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: displayBodyWeightKg)
                    for set in workoutExercise.sets where set.isCompleted {
                        // One point per performed segment so drop-set parts feed the
                        // charts like any other effort.
                        for part in set.effectiveLoadParts(baseLoadPerRep: baseLoad) {
                            results.append((date: workout.startedAt, weight: part.load, reps: part.reps))
                        }
                    }
                }
            }
        }

        return results.sorted { $0.date < $1.date }
    }

    // MARK: - Inline Editing (History)

    public func updateSetWeight(exerciseId: UUID, setId: UUID, weight: Double?) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        // Parent fields of a grouped drop set mirror its top segment — edit the segment instead.
        guard workout.exercises[ei].sets[si].dropSets.isEmpty else { return }
        workout.exercises[ei].sets[si].weight = weight
        await saveAndSync(workout)
    }

    public func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        guard workout.exercises[ei].sets[si].dropSets.isEmpty else { return }
        workout.exercises[ei].sets[si].reps = reps
        await saveAndSync(workout)
    }

    public func updateSetType(exerciseId: UUID, setId: UUID, setType: SetType) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        // A grouped drop set's type is managed by applyDropSets — never silently
        // destroy its segments by retyping it.
        guard workout.exercises[ei].sets[si].dropSets.isEmpty else { return }
        workout.exercises[ei].sets[si].setType = setType
        await saveAndSync(workout)
    }

    public func toggleSetCompletion(exerciseId: UUID, setId: UUID) async {
        guard var workout = selectedWorkout else { return }
        // Stamp the workout's own window, not "now" — history/retro sets must carry
        // backdated timestamps (PR achievedAt and analytics derive from them).
        let stamp = workout.completedAt ?? Date()
        guard workout.toggleSetCompletion(exerciseId: exerciseId, setId: setId, at: stamp) != nil else { return }
        await saveAndSync(workout)
    }

    public func addEmptySet(exerciseId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let setOrder = workout.exercises[ei].sets.count + 1
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
        workout.exercises[ei].sets.append(newSet)
        await saveAndSync(workout)
    }

    public func removeLastSet(exerciseId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              !workout.exercises[ei].sets.isEmpty else { return }
        workout.exercises[ei].sets.removeLast()
        await saveAndSync(workout)
    }

    // MARK: - Retro Logging

    /// Creates a past-dated workout that is BORN COMPLETE (`completedAt` derived from
    /// duration, never "now") so the active-workout machinery — `fetchActive()`,
    /// `deleteAllIncomplete()`, the 12-hour stale reaper — can never touch it.
    /// Selects it and enters edit mode for composition.
    /// Templates available for pre-filling a retro workout: the user's own
    /// templates first, then the library set, each sorted by sortOrder.
    /// User templates are numbered after the 9 library seeds in older stores,
    /// so a flat sortOrder sort would bury them below the fold of the picker.
    public func loadTemplates() async -> [WorkoutTemplate] {
        guard let templateRepository else { return [] }
        let all = (try? await templateRepository.fetchAll()) ?? []
        let user = all.filter(\.isCustom).sorted { $0.sortOrder < $1.sortOrder }
        let library = all.filter { !$0.isCustom }.sorted { $0.sortOrder < $1.sortOrder }
        return user + library
    }

    @discardableResult
    public func createRetroWorkout(
        name: String,
        startedAt: Date,
        duration: TimeInterval,
        saveToHealthKit: Bool,
        template: WorkoutTemplate? = nil
    ) async -> Workout? {
        guard startedAt < Date() else { return nil }
        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: startedAt,
            completedAt: min(startedAt.addingTimeInterval(duration), Date()),
            notes: nil,
            templateId: template?.id,
            exercises: template?.instantiateExercises() ?? []
        )
        do {
            let saved = try await workoutRepository.save(workout)
            // saveAndSync only replaces existing rows — insert the new one at its
            // sorted (startedAt-descending) position.
            let insertIndex = workouts.firstIndex { $0.startedAt < saved.startedAt } ?? workouts.endIndex
            workouts.insert(saved, at: insertIndex)
            selectedWorkout = saved
            isEditing = true
            pendingRetroFinalization[saved.id] = saveToHealthKit
            hasUnsavedFinalization = true
            if let template {
                try? await templateRepository?.incrementUsage(template.id)
            }
            return saved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Adds an exercise to the selected workout (mirror of the active-workout flow,
    /// but persisted immediately).
    public func addExercise(_ exercise: Exercise) async {
        guard var workout = selectedWorkout else { return }
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: workout.exercises.count + 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: []
        )
        workout.exercises.append(workoutExercise)
        await saveAndSync(workout)
    }

    public func removeExercise(exerciseId: UUID) async {
        guard var workout = selectedWorkout else { return }
        workout.exercises.removeAll { $0.id == exerciseId }
        for i in workout.exercises.indices {
            workout.exercises[i].order = i + 1
        }
        await saveAndSync(workout)
    }

    /// Swaps the exercise of a logged WorkoutExercise while keeping its id, order,
    /// notes, superset group and every set. PR rows are rebuilt by endEditing();
    /// per-set PR flags are cleared because they belonged to the old exercise.
    public func replaceExercise(exerciseId: UUID, with exercise: Exercise) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              workout.exercises[ei].exercise.id != exercise.id else { return }
        workout.exercises[ei].exercise = exercise
        for si in workout.exercises[ei].sets.indices {
            workout.exercises[ei].sets[si].isPersonalRecord = false
        }
        await saveAndSync(workout)
    }

    public func updateWorkoutName(_ name: String) async {
        guard var workout = selectedWorkout, !name.isEmpty, name != workout.name else { return }
        workout.name = name
        await saveAndSync(workout)
    }

    /// Completes every incomplete set, stamped inside the workout's own window.
    public func markAllSetsComplete() async {
        guard var workout = selectedWorkout else { return }
        workout.completeAllSets(at: workout.completedAt ?? Date())
        await saveAndSync(workout)
    }

    /// Ends the edit session and runs the deferred side effects exactly once.
    ///
    /// Always (retro AND normal history edits): re-vectorize the workout (history
    /// edits previously never re-vectorized — stale-analytics bug), rebuild PRs
    /// (order-proof for backdated inserts; preserves manual records), refresh widgets.
    /// Retro-created workouts additionally get their one-shot effects: webhook export
    /// and, when opted in, a HealthKit save with the workout's past dates.
    /// Never: debrief/summary, rest timer, Live Activity, watch sync.
    public func endEditing() async {
        isEditing = false
        guard hasUnsavedFinalization,
              let workout = selectedWorkout,
              workout.completedAt != nil else { return }
        hasUnsavedFinalization = false

        let bodyWeightKg = await resolveBodyWeightKg()
        try? await analyticsService?.vectorizeWorkout(
            workout,
            bodyWeightKg: bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
        )
        try? await personalRecordService?.recalculateAllPRs()

        if let healthKitOptIn = pendingRetroFinalization.removeValue(forKey: workout.id) {
            if healthKitOptIn, let healthKitService {
                if let bw = bodyWeightKg, let calorieEstimationService {
                    let result = calorieEstimationService.estimateCalories(workout: workout, bodyWeightKg: bw)
                    try? await healthKitService.saveWorkout(workout, calories: result.totalCalories, bodyWeightKg: bw)
                } else {
                    try? await healthKitService.saveWorkout(workout)
                }
            }
            await webhookService?.send(workout)
        }

        // Quality scores are history-relative and memoized — drop them before the
        // widget refresh republishes the aggregate.
        qualityScoreService?.invalidateAll()
        await widgetRefreshService?.refresh()
    }

    /// Synchronous body-weight resolution for display sites (prefs → default);
    /// the async HealthKit chain is only used for finalization side effects.
    public var displayBodyWeightKg: Double {
        userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    private func resolveBodyWeightKg() async -> Double? {
        if let hkWeight = await healthKitService?.fetchBodyWeightKg() {
            return hkWeight
        }
        return userPreferencesService?.bodyWeightKg
    }

    // MARK: - Delete Workout

    public func deleteWorkout(_ workout: Workout) async {
        do {
            try await workoutRepository.delete(workout)
            workouts.removeAll { $0.id == workout.id }
            if selectedWorkout?.id == workout.id {
                selectedWorkout = nil
            }
            // A deleted workout changes every history-relative metric.
            qualityScoreService?.invalidateAll()
            await widgetRefreshService?.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Intensity & Failure Editing

    public func updateSetIntensity(exerciseId: UUID, setId: UUID, value: Double?, metric: IntensityMetric) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        workout.exercises[ei].sets[si].applyIntensity(value, metric: metric)
        await saveAndSync(workout)
    }

    public func toggleSetFailure(exerciseId: UUID, setId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        var set = workout.exercises[ei].sets[si]
        let effective = set.isFailure || set.setType == .failure
        // Normalize legacy failure-typed rows into the per-set flag on first touch.
        if set.setType == .failure { set.setType = .normal }
        set.setFailureFlag(!effective)
        workout.exercises[ei].sets[si] = set
        await saveAndSync(workout)
    }

    // MARK: - Drop Set Editing

    public func addDropEntry(exerciseId: UUID, setId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        var set = workout.exercises[ei].sets[si]
        if set.dropSets.isEmpty {
            // Convert: current values become the top segment, plus one empty entry to fill in.
            let top = DropSetEntry(weight: set.weight, reps: set.reps, rpe: set.rpe, rir: set.rir, isFailure: set.isFailure)
            set.applyDropSets([top, DropSetEntry()])
        } else {
            set.applyDropSets(set.dropSets + [DropSetEntry()])
        }
        workout.exercises[ei].sets[si] = set
        await saveAndSync(workout)
    }

    public func removeDropEntry(exerciseId: UUID, setId: UUID, entryId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        var set = workout.exercises[ei].sets[si]
        var entries = set.dropSets
        entries.removeAll { $0.id == entryId }
        if entries.count == 1, let survivor = entries.first {
            // Collapse back to a plain set carrying the surviving segment's values.
            set.applyDropSets([survivor])
            set.applyDropSets([])
        } else {
            set.applyDropSets(entries)
        }
        workout.exercises[ei].sets[si] = set
        await saveAndSync(workout)
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
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }),
              let di = workout.exercises[ei].sets[si].dropSets.firstIndex(where: { $0.id == entryId }) else { return }
        var set = workout.exercises[ei].sets[si]
        var entries = set.dropSets
        mutate(&entries[di])
        set.applyDropSets(entries)
        workout.exercises[ei].sets[si] = set
        await saveAndSync(workout)
    }

    // MARK: - Save Helper

    private func saveAndSync(_ workout: Workout) async {
        do {
            let saved = try await workoutRepository.save(workout)
            selectedWorkout = saved
            hasUnsavedFinalization = true
            // Update the workouts array so the list reflects changes
            if let index = workouts.firstIndex(where: { $0.id == saved.id }) {
                workouts[index] = saved
            }
        } catch {
            // Revert on failure
            selectedWorkout = workout
        }
    }
}
