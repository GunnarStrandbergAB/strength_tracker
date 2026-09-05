import Foundation

/// Seam over `WidgetRefreshService` (which touches WidgetCenter and the App Group).
@MainActor
public protocol WidgetRefreshing: AnyObject {
    func refresh() async
}

extension WidgetRefreshService: WidgetRefreshing {}

/// The ONE post-mutation pipeline for completed workouts. Every path that
/// changes a completed workout — finish on the phone, history edit (UI or AI),
/// Watch receive, delete, retro creation, full rebuilds — ends here, so derived
/// data can never drift: vector → personal records (+ per-set flags) → cache
/// invalidation → plan hooks → HealthKit → webhook → revision bump → widgets.
///
/// Pipelines are serialized so a finish, an AI edit and a body-weight rebuild
/// never interleave. The revision is bumped exactly once per pipeline, after
/// derived data is consistent and before widgets republish.
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
        dataRevision: DataRevision
    ) {
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

    /// A workout was just completed. Returns it with PR flags (and HealthKit id) applied.
    @discardableResult
    public func workoutCompleted(_ workout: Workout, source: Source) async -> Workout {
        await enqueue { [self] in
            var current = workout
            if let sessionId = current.plannedSessionId, let planId = current.plannedPlanId {
                await onSessionCompleted?(sessionId, planId, current.id)
            }
            try? await analyticsService?.vectorizeWorkout(current)
            current = await rebuildRecords(for: current, exerciseIds: current.exerciseIds)
            invalidateCaches()
            if source == .phone {
                current = await saveToHealthKit(current)
            }
            await webhookService?.send(current)
            dataRevision.bump()
            await widgetRefresh?.refresh()
            return current
        }
    }

    /// A completed workout was edited (History UI, AI editor, retro creation).
    @discardableResult
    public func workoutEdited(_ workout: Workout, touchedExerciseIds: Set<UUID>, retro: RetroOptions?) async -> Workout {
        await enqueue { [self] in
            var current = workout
            try? await analyticsService?.vectorizeWorkout(current)
            current = await rebuildRecords(for: current, exerciseIds: touchedExerciseIds.union(current.exerciseIds))
            invalidateCaches()
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
            await webhookService?.send(current)
            dataRevision.bump()
            await widgetRefresh?.refresh()
            return current
        }
    }

    /// A completed workout was deleted (the repository row is already gone).
    public func workoutDeleted(_ workout: Workout) async {
        await enqueue { [self] in
            try? await analyticsRepository.deleteVector(for: workout.id)
            _ = try? await personalRecordService?.recalculatePRs(for: workout.exerciseIds)
            invalidateCaches()
            await onWorkoutUnlinked?(workout.id)
            try? await healthKitService.deleteWorkout(appWorkoutId: workout.id)
            dataRevision.bump()
            await widgetRefresh?.refresh()
        }
    }

    /// A completed workout arrived from the Watch. Saves it (never letting an
    /// incomplete copy overwrite a completed one) and runs the completion pipeline.
    public func workoutReceivedFromWatch(_ workout: Workout, metadata: [String: String]?) async {
        var incoming = workout
        if let existing = try? await workoutRepository.fetchAll().first(where: { $0.id == incoming.id }),
           existing.completedAt != nil, incoming.completedAt == nil {
            return
        }
        if incoming.plannedSessionId == nil,
           let sessionIdString = metadata?["plannedSessionId"],
           let planIdString = metadata?["plannedPlanId"],
           let sessionId = UUID(uuidString: sessionIdString),
           let planId = UUID(uuidString: planIdString) {
            incoming.plannedSessionId = sessionId
            incoming.plannedPlanId = planId
        }
        guard let saved = try? await workoutRepository.save(incoming) else { return }
        guard saved.completedAt != nil else {
            dataRevision.bump()
            return
        }
        await workoutCompleted(saved, source: .watch)
    }

    /// Everything derived is rebuilt from scratch (body-weight change, migrations).
    public func rebuildAll(reason: RebuildReason) async {
        await enqueue { [self] in
            try? await analyticsRepository.deleteAllVectors()
            try? await analyticsService?.vectorizeAllWorkouts()
            try? await analyticsService?.sweepOrphanVectors()
            try? await personalRecordService?.recalculateAllPRs()
            invalidateCaches()
            dataRevision.bump()
            await widgetRefresh?.refresh()
        }
    }

    // MARK: - Steps

    private func rebuildRecords(for workout: Workout, exerciseIds: Set<UUID>) async -> Workout {
        guard let personalRecordService,
              let changed = try? await personalRecordService.recalculatePRs(for: exerciseIds) else { return workout }
        return changed[workout.id] ?? workout
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
        var updated = workout
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
