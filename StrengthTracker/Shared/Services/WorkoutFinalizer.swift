import Foundation

/// Seam over `WidgetRefreshService` (which touches WidgetCenter and the App Group).
@MainActor
public protocol WidgetRefreshing: AnyObject {
    func refresh() async
}

extension WidgetRefreshService: WidgetRefreshing {}

/// Serializes completed-workout mutations. Local derivation runs in dependency
/// order (PR election, vectors, cache invalidation) before publishing a revision.
@MainActor
public final class WorkoutFinalizer {

    public enum Source: Sendable {
        /// Finished on this phone: HealthKit save + webhook are ours to do.
        case phone
        /// Received from the Watch, which already wrote its own HKWorkout.
        case watch
    }

    public struct RetroOptions: Sendable {
        public var saveToHealthKit: Bool
        public init(saveToHealthKit: Bool) { self.saveToHealthKit = saveToHealthKit }
    }

    public enum RebuildReason: Sendable {
        case bodyWeightChanged
        case migration
        case manual
    }

    private let workoutRepository: any WorkoutRepository
    private let analyticsRepository: any AnalyticsRepository
    private let analyticsService: WorkoutAnalyticsService?
    private let personalRecordService: PersonalRecordService?
    private let qualityScoreService: WorkoutQualityScoreService?
    private let healthKitService: any HealthKitServiceProtocol
    private let calorieEstimationService: CalorieEstimationService
    private let webhookService: WebhookService?
    private let widgetRefresh: (any WidgetRefreshing)?
    private let bodyWeightProvider: BodyWeightProvider?
    private let dataRevision: DataRevision

    /// Plan hooks, wired by AppContainer to ProgressionPlanViewModel.
    public var onSessionCompleted: (@MainActor (_ sessionId: UUID, _ planId: UUID, _ workoutId: UUID) async -> Void)?
    public var onSessionEdited: (@MainActor (_ sessionId: UUID, _ planId: UUID, _ workoutId: UUID) async -> Void)?
    public var onWorkoutUnlinked: (@MainActor (_ workoutId: UUID) async -> Void)?

    private static let repairKey = "workout_analytics_pending_repairs"
    private static let vectorRepairVersion = 1
    private let repairDefaults: UserDefaults?
    // Tokens distinguish two saves of the same workout across suspension points.
    private var pending: [String: String] {
        didSet { repairDefaults?.set(pending, forKey: Self.repairKey) }
    }
    private var interrupted: [String: String]
    public private(set) var localRepairError: String?

    private var chain: Task<Void, Never> = Task {}

    public init(
        workoutRepository: any WorkoutRepository,
        analyticsRepository: any AnalyticsRepository,
        analyticsService: WorkoutAnalyticsService?,
        personalRecordService: PersonalRecordService?,
        qualityScoreService: WorkoutQualityScoreService?,
        healthKitService: any HealthKitServiceProtocol,
        calorieEstimationService: CalorieEstimationService = CalorieEstimationService(),
        webhookService: WebhookService?,
        widgetRefresh: (any WidgetRefreshing)?,
        bodyWeightProvider: BodyWeightProvider?,
        dataRevision: DataRevision,
        repairDefaults: UserDefaults? = nil
    ) {
        self.repairDefaults = repairDefaults
        let interrupted = repairDefaults?.dictionary(forKey: Self.repairKey) as? [String: String] ?? [:]
        self.interrupted = interrupted
        self.pending = interrupted
        self.workoutRepository = workoutRepository
        self.analyticsRepository = analyticsRepository
        self.analyticsService = analyticsService
        self.personalRecordService = personalRecordService
        self.qualityScoreService = qualityScoreService
        self.healthKitService = healthKitService
        self.calorieEstimationService = calorieEstimationService
        self.webhookService = webhookService
        self.widgetRefresh = widgetRefresh
        self.bodyWeightProvider = bodyWeightProvider
        self.dataRevision = dataRevision
    }

    private var bodyWeightKg: Double {
        bodyWeightProvider?.current ?? UserPreferencesService.defaultBodyWeightKg
    }

    // MARK: - Pipelines

    /// Write ahead of the source save. If the app exits before Done, startup
    /// rebuilds local analytics from whatever was actually persisted.
    public func willChangeWorkout(_ id: UUID) {
        pending[id.uuidString] = UUID().uuidString
    }

    /// A workout was just completed. Returns it with PR flags (and HealthKit id) applied.
    @discardableResult
    public func workoutCompleted(_ workout: Workout, source: Source, replacing previous: Workout? = nil) async -> Workout {
        let token = repairToken(for: workout.id)
        return await enqueue { [self] in
            var current = workout
            if let sessionId = current.plannedSessionId, let planId = current.plannedPlanId {
                await onSessionCompleted?(sessionId, planId, current.id)
            }
            let exercises = current.exerciseIds.union(previous?.exerciseIds ?? [])
            let repair = await derive(current, previous: previous, exercises: exercises, checkLiveRecords: source == .phone)
            current = repair.workout ?? current
            if source == .phone {
                current = await saveToHealthKit(current)
            }
            if repair.success { await publishRepair(for: workout.id, token: token) }
            await webhookService?.send(current)
            return current
        }
    }

    /// A completed workout was edited (History UI, AI editor, retro creation).
    @discardableResult
    public func workoutEdited(_ workout: Workout, touchedExerciseIds: Set<UUID>, retro: RetroOptions?) async -> Workout {
        let token = repairToken(for: workout.id)
        return await enqueue { [self] in
            let repair = await derive(workout, exercises: touchedExerciseIds.union(workout.exerciseIds))
            var current = repair.workout ?? workout
            if let sessionId = current.plannedSessionId, let planId = current.plannedPlanId {
                await onSessionEdited?(sessionId, planId, current.id)
            }
            if let retro {
                if retro.saveToHealthKit {
                    current = await saveToHealthKit(current)
                }
            } else {
                // Keep Health in sync: replace the sample we wrote earlier (if any).
                try? await healthKitService.deleteWorkout(appWorkoutId: current.id)
                if current.healthKitWorkoutId != nil {
                    current = await saveToHealthKit(current)
                }
            }
            if repair.success { await publishRepair(for: workout.id, token: token) }
            await webhookService?.send(current)
            return current
        }
    }

    /// A completed workout was deleted (the repository row is already gone).
    public func workoutDeleted(_ workout: Workout, touchedExerciseIds: Set<UUID> = []) async {
        let token = repairToken(for: workout.id)
        await enqueue { [self] in
            let repair = await derive(workout, exercises: touchedExerciseIds.union(workout.exerciseIds), deleted: true)
            await onWorkoutUnlinked?(workout.id)
            if repair.success { await publishRepair(for: workout.id, token: token) }
            try? await healthKitService.deleteWorkout(appWorkoutId: workout.id)
        }
    }

    /// A completed workout arrived from the Watch. Saves it (never letting an
    /// incomplete copy overwrite a completed one) and runs the completion pipeline.
    public func workoutReceivedFromWatch(_ workout: Workout, metadata: [String: String]?) async {
        var incoming = workout
        let previous = try? await workoutRepository.fetchAll().first { $0.id == incoming.id }
        if let existing = previous,
           existing.completedAt != nil, incoming.completedAt == nil {
            return
        }
        if let existing = previous {
            for i in incoming.exercises.indices where incoming.exercises[i].exercise.weightRecording == nil {
                if let prior = existing.exercises.first(where: { $0.id == incoming.exercises[i].id }) {
                    incoming.exercises[i].exercise.weightRecording = prior.exercise.weightRecording
                }
            }
        }
        if incoming.plannedSessionId == nil,
           let sessionIdString = metadata?["plannedSessionId"],
           let planIdString = metadata?["plannedPlanId"],
           let sessionId = UUID(uuidString: sessionIdString),
           let planId = UUID(uuidString: planIdString) {
            incoming.plannedSessionId = sessionId
            incoming.plannedPlanId = planId
        }
        if incoming.completedAt != nil { willChangeWorkout(incoming.id) }
        guard let saved = try? await workoutRepository.save(incoming) else { return }
        guard saved.completedAt != nil else {
            dataRevision.bump()
            return
        }
        await workoutCompleted(saved, source: .watch, replacing: previous)
    }

    /// Metadata changes may affect every workout, including old record holders.
    public func rebuildAll(reason: RebuildReason) async {
        try? await rebuildWeightRecordingData()
    }

    public func rebuildWeightRecordingData() async throws {
        let result: Result<Void, Error> = await enqueue { [self] in
            pending["full"] = UUID().uuidString
            do {
                try await rebuildLocalHistory()
                pending.removeValue(forKey: "full")
                await publish()
                return .success(())
            } catch {
                localRepairError = error.localizedDescription
                return .failure(error)
            }
        }
        try result.get()
    }

    /// The vector repair version is independent of the scoring formula version.
    /// Only a successful local rebuild advances either migration marker.
    @discardableResult
    public func migrateAnalyticsModelIfNeeded(defaults: UserDefaults = .standard) async -> Bool {
        await enqueue { [self] in
            let modelKey = "analytics_derived_model_version"
            let vectorKey = "analytics_vector_repair_version"
            let outstanding = interrupted.filter { pending[$0.key] == $0.value }
            guard defaults.integer(forKey: modelKey) < WorkoutQualityScore.modelVersion ||
                    defaults.integer(forKey: vectorKey) < Self.vectorRepairVersion ||
                    !interrupted.isEmpty || pending["full"] != nil else { return false }
            guard personalRecordService != nil else { return false }
            do {
                try await rebuildLocalHistory()
                // Replay only local plan changes for interrupted edits. An edited
                // session replay derives future targets from the saved history.
                if !outstanding.isEmpty {
                    let rows = try await workoutRepository.fetchAll()
                    for key in outstanding.keys {
                        guard let id = UUID(uuidString: key) else { continue }
                        if let workout = rows.first(where: { $0.id == id }) {
                            if let session = workout.plannedSessionId, let plan = workout.plannedPlanId {
                                await onSessionEdited?(session, plan, id)
                            }
                        } else {
                            await onWorkoutUnlinked?(id)
                        }
                    }
                }
                for (key, token) in outstanding where pending[key] == token {
                    pending.removeValue(forKey: key)
                }
                interrupted.removeAll()
                pending.removeValue(forKey: "full")
                defaults.set(WorkoutQualityScore.modelVersion, forKey: modelKey)
                defaults.set(Self.vectorRepairVersion, forKey: vectorKey)
                await publish()
                return true
            } catch {
                localRepairError = error.localizedDescription
                return false
            }
        }
    }

    private func repairToken(for id: UUID) -> String {
        if let token = pending[id.uuidString] { return token }
        let token = UUID().uuidString
        pending[id.uuidString] = token
        return token
    }

    private func rebuildLocalHistory() async throws {
        try await personalRecordService?.recalculateAllPRs()
        try await analyticsService?.vectorizeAllWorkouts(replacingExisting: true)
    }

    private func derive(_ mutation: Workout, previous: Workout? = nil, exercises: Set<UUID>,
                        deleted: Bool = false, checkLiveRecords: Bool = false) async -> (workout: Workout?, success: Bool) {
        do {
            let updated: Workout?
            if pending["full"] != nil {
                // A partial election may have already moved flags. Its original
                // set of changed IDs cannot be reconstructed by repeating it.
                try await rebuildLocalHistory()
                updated = try await workoutRepository.fetchAll().first { $0.id == mutation.id }
                pending.removeValue(forKey: "full")
            } else {
                let changed = try await personalRecordService?.recalculatePRs(for: exercises) ?? [:]
                if let analyticsService {
                    updated = try await analyticsService.rebuildVectors(after: mutation, previous: previous,
                        changedRecordIds: Set(changed.keys), checkLiveRecords: checkLiveRecords)
                } else {
                    if deleted { try await analyticsRepository.deleteVector(for: mutation.id) }
                    updated = changed[mutation.id]
                }
            }
            return (updated, true)
        } catch {
            pending["full"] = UUID().uuidString
            localRepairError = error.localizedDescription
            return (nil, false)
        }
    }

    private func publishRepair(for id: UUID, token: String) async {
        if pending[id.uuidString] == token { pending.removeValue(forKey: id.uuidString) }
        await publish()
    }

    private func publish() async {
        localRepairError = nil
        invalidateCaches()
        dataRevision.bump()
        await widgetRefresh?.refresh()
    }

    private func invalidateCaches() {
        qualityScoreService?.invalidateAll()
        analyticsService?.invalidateDerivedCaches()
    }

    private func saveToHealthKit(_ workout: Workout) async -> Workout {
        let bw = bodyWeightKg
        let calories = calorieEstimationService.estimateCalories(workout: workout, bodyWeightKg: bw).totalCalories
        guard let uuid = try? await healthKitService.saveWorkout(workout, calories: calories, bodyWeightKg: bw),
              uuid != workout.healthKitWorkoutId else { return workout }
        // HealthKit can suspend while History saves another edit or deletes the row.
        guard var updated = try? await workoutRepository.fetchAll().first(where: { $0.id == workout.id }) else { return workout }
        updated.healthKitWorkoutId = uuid
        return (try? await workoutRepository.save(updated)) ?? updated
    }

    /// Serializes pipelines in call order.
    private func enqueue<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = chain
        let task = Task<T, Never> {
            await previous.value
            return await body()
        }
        chain = Task { _ = await task.value }
        return await task.value
    }
}

extension Workout {
    /// Catalog exercise ids in this workout (not WorkoutExercise row ids).
    public var exerciseIds: Set<UUID> {
        Set(exercises.map(\.exercise.id))
    }
}
