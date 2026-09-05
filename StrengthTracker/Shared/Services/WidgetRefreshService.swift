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
    private let workoutAnalyticsViewModel: WorkoutAnalyticsViewModel
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
        workoutAnalyticsViewModel: WorkoutAnalyticsViewModel,
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
        self.workoutAnalyticsViewModel = workoutAnalyticsViewModel
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

            // Get analytics highlights
            var highlights: [AnalyticsHighlight] = []
            if !workoutAnalyticsViewModel.insights.highlights.isEmpty {
                highlights = workoutAnalyticsViewModel.insights.highlights
            } else {
                // Try a lightweight generation
                highlights = (try? await analyticsService.generateInsights().highlights) ?? []
            }

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

            // Supplement with volume trend if room remains (calendar-week, bodyweight-aware).
            // Uses the same week-split as the widget payload so the numbers always agree.
            if highlights.count < 3 {
                let completedWorkouts = workouts.filter { $0.completedAt != nil }
                let (thisWeekWorkouts, lastWeekWorkouts) = widgetService.weeklyWorkoutSplit(from: completedWorkouts)

                let thisWeekVol = thisWeekWorkouts.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bw) }
                let lastWeekVol = lastWeekWorkouts.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bw) }

                // Compare per-session averages to avoid misleading partial-week comparisons
                if !thisWeekWorkouts.isEmpty && !lastWeekWorkouts.isEmpty {
                    let thisAvg = thisWeekVol / Double(thisWeekWorkouts.count)
                    let lastAvg = lastWeekVol / Double(lastWeekWorkouts.count)
                    let pct = ((thisAvg - lastAvg) / lastAvg) * 100
                    if pct > 0 {
                        highlights.append(AnalyticsHighlight(
                            type: .improvement,
                            title: "Volume Up",
                            detail: "+\(Int(pct))% avg/session vs last week"
                        ))
                    } else if pct < -5 {
                        highlights.append(AnalyticsHighlight(
                            type: .warning,
                            title: "Volume Down",
                            detail: "\(Int(pct))% avg/session vs last week"
                        ))
                    }
                }
            }

            // Compute aggregate quality for widget
            let qualityScore: Double?
            let qualityTrend: Double?
            if let agg = workoutAnalyticsViewModel.aggregateQuality, agg.workoutsIncluded > 0 {
                qualityScore = agg.ewmaOverall
                qualityTrend = agg.trendVsPrior
            } else {
                let agg = qualityScoreService.computeAggregateScore(workouts: workouts)
                qualityScore = agg.workoutsIncluded > 0 ? agg.ewmaOverall : nil
                qualityTrend = agg.workoutsIncluded > 0 ? agg.trendVsPrior : nil
            }

            // Supplement with quality score highlight if room remains
            if highlights.count < 3, let qs = qualityScore {
                highlights.append(AnalyticsHighlight(
                    type: .improvement,
                    title: "Quality",
                    detail: "\(Int(qs))/100"
                ))
            }

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
                activeExerciseId: workoutViewModel.activeExerciseId
            )
            widgetService.updateWidgetData(data)
        } catch {
            print("[Widget] Failed to refresh widget data: \(error)")
        }
    }
}
