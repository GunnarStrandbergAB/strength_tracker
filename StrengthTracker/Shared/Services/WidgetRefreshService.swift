import Foundation

/// Rebuilds the shared widget payload from current data and pushes it to WidgetKit.
///
/// Extracted from the app layer so non-app flows (e.g. retro workout logging in
/// History) can refresh widgets immediately instead of waiting for the next
/// foreground `scenePhase` refresh. The widget-intent pending-completions replay
/// deliberately stays in the app layer — it mutates the live workout singleton.
@MainActor
public final class WidgetRefreshService {
    private let workoutRepository: any WorkoutRepository
    private let progressionPlanRepository: any ProgressionPlanRepository
    private let healthKitService: any HealthKitServiceProtocol
    private let userPreferencesService: UserPreferencesService
    private let analyticsService: WorkoutAnalyticsService
    private let qualityScoreService: WorkoutQualityScoreService
    private let workoutViewModel: WorkoutViewModel
    private let restTimerService: RestTimerService
    private let bodyWeightProvider: BodyWeightProvider?

    public init(
        workoutRepository: any WorkoutRepository,
        progressionPlanRepository: any ProgressionPlanRepository,
        healthKitService: any HealthKitServiceProtocol,
        userPreferencesService: UserPreferencesService,
        analyticsService: WorkoutAnalyticsService,
        qualityScoreService: WorkoutQualityScoreService,
        workoutViewModel: WorkoutViewModel,
        restTimerService: RestTimerService,
        bodyWeightProvider: BodyWeightProvider? = nil
    ) {
        self.bodyWeightProvider = bodyWeightProvider
        self.workoutRepository = workoutRepository
        self.progressionPlanRepository = progressionPlanRepository
        self.healthKitService = healthKitService
        self.userPreferencesService = userPreferencesService
        self.analyticsService = analyticsService
        self.qualityScoreService = qualityScoreService
        self.workoutViewModel = workoutViewModel
        self.restTimerService = restTimerService
    }

    /// Rebuild and publish the widget payload (updateWidgetData reloads all timelines).
    public func refresh() async {
        let widgetService = WidgetDataService()
        do {
            let workouts = try await workoutRepository.fetchAll()

            let bw = bodyWeightProvider?.current
                ?? userPreferencesService.bodyWeightKg
                ?? UserPreferencesService.defaultBodyWeightKg

            // Highlights straight from the service (cached per data revision, so this
            // is cheap when a screen already computed them — and never pre-edit stale).
            let insights = try? await analyticsService.generateInsights()
            let highlights: [AnalyticsHighlight] = insights?.highlights ?? []

            // Fetch active plan once — reused for next session + weekly goal
            let activePlan = try await progressionPlanRepository.fetchActive()

            // Build next planned session (first open session across the whole plan)
            var nextPlanned: WidgetPlannedSession? = nil
            if let plan = activePlan,
               let nextSession = plan.nextPlannedSession {
                nextPlanned = WidgetPlannedSession(
                    sessionName: nextSession.sessionLabel,
                    exerciseNames: Array(nextSession.plannedExercises.prefix(4).map(\.exerciseName)),
                    planName: plan.name
                )
            }

            // Compute aggregate quality for widget
            let agg = qualityScoreService.computeAggregateScore(workouts: workouts)
            let qualityScore: Double? = agg.workoutsIncluded > 0 && !agg.provisional ? agg.ewmaOverall : nil
            let qualityTrend: Double? = agg.workoutsIncluded > 0 && !agg.provisional ? agg.trendVsPrior : nil

            // Weekly goal from plan's frequency (0 = no active plan)
            let weeklyGoal = activePlan?.weeklyFrequency ?? 0

            let data = widgetService.buildWidgetData(
                workouts: workouts,
                highlights: highlights,
                activeWorkout: workoutViewModel.isActive ? workoutViewModel.currentWorkout : nil,
                isResting: restTimerService.isRunning,
                restEndDate: restTimerService.endDate,
                nextPlannedSession: nextPlanned,
                weeklyGoal: weeklyGoal,
                bodyWeightKg: bw,
                weeklyQualityScore: qualityScore,
                qualityTrend: qualityTrend,
                activeExerciseId: workoutViewModel.activeExerciseId,
                weightUnitSymbol: userPreferencesService.weightUnit.symbol,
                analyticsGeneratedAt: insights?.generatedAt
            )
            widgetService.updateWidgetData(data)
        } catch {
            print("[Widget] Failed to refresh widget data: \(error)")
        }
    }

    static func verdictHighlight(_ verdict: TrainingVerdict) -> AnalyticsHighlight {
        let type: HighlightType
        if verdict.isActiveDeload {
            type = .improvement
        } else {
            switch verdict.kind {
            case .deload: type = .warning
            case .hold: type = .milestone
            case .progress: type = .improvement
            }
        }
        return AnalyticsHighlight(type: type, title: verdict.headline, detail: verdict.action)
    }
}
