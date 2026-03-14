#if canImport(SwiftUI) && canImport(SwiftData)
import SwiftUI
import SwiftData
import StrengthTrackerShared

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

#if canImport(WidgetKit)
import WidgetKit
#endif

import UserNotifications

// MARK: - Notification Delegate (foreground delivery + tap handling)

class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onRestTimerNotificationTapped: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == "rest-timer" {
            onRestTimerNotificationTapped?()
        }
        handler()
    }
}

@main
struct StrengthTrackeriOSApp: App {
    let container: AppContainer
    private let notificationDelegate = AppNotificationDelegate()

    init() {
        do {
            container = try AppContainer()

            // Initialize WatchConnectivity
            #if canImport(WatchConnectivity)
            if WCSession.isSupported() {
                let session = WCSession.default
                session.delegate = container.connectivityManager
                session.activate()
            }
            #endif

            container.exerciseSeeder.startSeeding()
            container.templateSeedService.startSeeding()

            // Request notification permission for rest timer background alerts
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .timeSensitive]) { _, _ in }

            // Register notification category for rest timer completions
            let restCategory = UNNotificationCategory(
                identifier: "REST_TIMER_COMPLETE",
                actions: [],
                intentIdentifiers: [],
                options: []
            )
            UNUserNotificationCenter.current().setNotificationCategories([restCategory])

            // Set up notification delegate for foreground delivery and tap handling
            let restTimerService = container.restTimerService
            notificationDelegate.onRestTimerNotificationTapped = {
                Task { @MainActor in
                    restTimerService.handleForegroundReturn()
                    restTimerService.endAllStaleActivities()
                }
            }
            UNUserNotificationCenter.current().delegate = notificationDelegate

            // Wire up Watch → iPhone workout sync (SwiftData + webhook only)
            // Watch already saves HKWorkout with sensor-based calories — iPhone must NOT touch HealthKit
            let workoutRepo = container.workoutRepository
            let webhookService = container.webhookService
            let progressionPlanRepo = container.progressionPlanRepository
            container.connectivityManager.onWorkoutReceived = { workout, metadata in
                Task { @MainActor in
                    do {
                        _ = try await workoutRepo.save(workout)
                        await webhookService.send(workout)

                        // Mark planned session completed if Watch sent session/plan IDs
                        if let sessionIdStr = metadata?["plannedSessionId"],
                           let planIdStr = metadata?["plannedPlanId"],
                           let sessionId = UUID(uuidString: sessionIdStr),
                           let planId = UUID(uuidString: planIdStr) {
                            try? await progressionPlanRepo.markSessionCompleted(
                                sessionId, workoutId: workout.id, inPlan: planId
                            )
                        }
                    } catch {
                        print("Failed to save Watch workout: \(error)")
                    }
                }
            }

            // Wire up live Watch workout mirror (Fix 6)
            let workoutVM = container.workoutViewModel
            container.connectivityManager.onWatchWorkoutSnapshot = { workout in
                Task { @MainActor in
                    workoutVM.watchActiveWorkout = workout
                }
            }
            container.connectivityManager.onWatchWorkoutStarted = { workout in
                Task { @MainActor in
                    workoutVM.watchActiveWorkout = workout
                }
            }
            container.connectivityManager.onWatchWorkoutEnded = {
                Task { @MainActor in
                    workoutVM.watchActiveWorkout = nil
                }
            }

            // Clean up any orphaned Live Activities from previous launches
            container.restTimerService.endAllStaleActivities()
        } catch {
            fatalError("Failed to initialize app: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentViewWrapper(container: container)
        }
        .modelContainer(container.modelContainer)
    }

}

struct ContentViewWrapper: View {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentView(
            dashboardViewModel: container.makeDashboardViewModel(),
            exerciseListViewModel: container.makeExerciseListViewModel(),
            progressViewModel: container.makeProgressViewModel(),
            workoutViewModel: container.makeWorkoutViewModel(),
            historyViewModel: container.makeHistoryViewModel(),
            templateViewModel: container.makeTemplateViewModel(),
            analyticsViewModel: container.makeWorkoutAnalyticsViewModel(),
            progressionPlanViewModel: container.makeProgressionPlanViewModel(),
            userPreferencesService: container.userPreferencesService,
            connectivityManager: container.connectivityManager,
            restTimerService: container.restTimerService,
            personalRecordService: container.personalRecordService,
            proFeatureGate: container.proFeatureGate,
            storeService: container.storeService
        )
        .onOpenURL { url in
            // Handle deep links from widgets
            handleDeepLink(url)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // End stale mirrored Live Activity if watch timer expired while iPhone was backgrounded
                container.restTimerService.handleForegroundReturn()
                container.restTimerService.endAllStaleActivities()

                // Refresh widget data with analytics
                Task { @MainActor in
                    await refreshWidgetData()
                }

                // Sync templates, exercises, settings, and planned sessions to Watch when app becomes active
                Task { @MainActor in
                    do {
                        let allTemplates = try await container.templateRepository.fetchAll()
                        // Only sync user-created templates to Watch (not seed/library templates)
                        container.connectivityManager.syncTemplates(allTemplates.filter { $0.isCustom })

                        let exercises = try await container.exerciseRepository.fetchAll()
                        container.connectivityManager.syncExercises(exercises)

                        // Sync planned sessions from active progression plan
                        if let plan = try await container.progressionPlanRepository.fetchActive(),
                           let week = plan.currentWeek {
                            let allTemplates = try await container.templateRepository.fetchAll()
                            let templateLookup = Dictionary(
                                allTemplates.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first }
                            )
                            let vm = container.progressionPlanViewModel

                            let sessions: [PlannedSessionSync] = week.sessions
                                .filter { !$0.isCompleted }
                                .map { session in
                                    let template: WorkoutTemplate
                                    if let tid = session.templateId,
                                       let linked = templateLookup[tid] {
                                        template = vm.mergeSessionIntoTemplate(
                                            session: session, template: linked, exercises: exercises
                                        )
                                    } else {
                                        template = session.toWorkoutTemplate(exercises: exercises)
                                    }
                                    return PlannedSessionSync(
                                        id: session.id,
                                        planId: plan.id,
                                        planName: plan.name,
                                        sessionLabel: session.sessionLabel,
                                        weekLabel: "Week \(week.absoluteWeekNumber)",
                                        blockName: plan.currentBlock?.name,
                                        template: template
                                    )
                                }
                            print("[iOS Sync] Syncing \(sessions.count) planned sessions to Watch for plan '\(plan.name)'")
                            container.connectivityManager.syncPlannedSessions(sessions)
                        } else {
                            print("[iOS Sync] No active plan or no current week — clearing Watch planned sessions")
                            container.connectivityManager.syncPlannedSessions([])
                        }
                    } catch {
                        print("[iOS Sync] Failed to sync data on activation: \(error)")
                    }

                    let prefs = container.userPreferencesService
                    container.connectivityManager.syncSettings([
                        "defaultRestSeconds": prefs.defaultRestSeconds,
                        "weightUnit": prefs.weightUnit.rawValue,
                        "autoStartRestTimer": prefs.autoStartRestTimer,
                        "distanceUnit": prefs.distanceUnit.rawValue
                    ])
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        switch host {
        case "rest-timer":
            container.restTimerService.handleForegroundReturn()
            container.restTimerService.endAllStaleActivities()
        default:
            break
        }
    }

    @MainActor
    private func refreshWidgetData() async {
        let widgetService = WidgetDataService()

        // Process any pending set completions from widget intents
        let pending = widgetService.readPendingCompletions()
        if !pending.isEmpty {
            let workoutVM = container.workoutViewModel
            for completion in pending {
                if let workout = workoutVM.currentWorkout,
                   let exercise = workout.exercises.first(where: { $0.id.uuidString == completion.exerciseId }),
                   completion.setIndex < exercise.sets.count {
                    let set = exercise.sets[completion.setIndex]
                    if !set.isCompleted {
                        await workoutVM.toggleSetCompletion(exerciseId: exercise.id, setId: set.id)
                    }
                }
            }
            widgetService.clearPendingCompletions()
        }

        do {
            let workouts = try await container.workoutRepository.fetchAll()

            // Get analytics highlights
            var highlights: [AnalyticsHighlight] = []
            let analyticsVM = container.workoutAnalyticsViewModel
            if !analyticsVM.insights.highlights.isEmpty {
                highlights = analyticsVM.insights.highlights
            } else {
                // Try a lightweight generation
                highlights = (try? await container.analyticsService.generateInsights().highlights) ?? []
            }

            // Fetch active plan once — reused for next session + weekly goal
            let activePlan = try await container.progressionPlanRepository.fetchActive()

            // Build next planned session
            var nextPlanned: WidgetPlannedSession? = nil
            if let plan = activePlan,
               let week = plan.currentWeek,
               let nextSession = week.sessions.first(where: { !$0.isCompleted }) {
                nextPlanned = WidgetPlannedSession(
                    sessionName: nextSession.sessionLabel,
                    exerciseNames: Array(nextSession.plannedExercises.prefix(4).map(\.exerciseName)),
                    planName: plan.name
                )
            }

            // Supplement with volume trend if room remains (rolling 7-day window)
            if highlights.count < 3 {
                let now = Date()
                let calendar = Calendar.current
                let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
                let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now)!
                let completedWorkouts = workouts.filter { $0.completedAt != nil }

                let thisWeekVol = completedWorkouts
                    .filter { let d = $0.completedAt ?? .distantPast; return d >= sevenDaysAgo && d <= now }
                    .reduce(0.0) { $0 + $1.totalVolume }
                let lastWeekVol = completedWorkouts
                    .filter { let d = $0.completedAt ?? .distantPast; return d >= fourteenDaysAgo && d < sevenDaysAgo }
                    .reduce(0.0) { $0 + $1.totalVolume }

                if thisWeekVol > 0 && lastWeekVol > 0 {
                    let pct = ((thisWeekVol - lastWeekVol) / lastWeekVol) * 100
                    if pct > 0 {
                        highlights.append(AnalyticsHighlight(
                            type: .improvement,
                            title: "Volume Up",
                            detail: "+\(Int(pct))% vs last 7 days"
                        ))
                    } else if pct < -5 {
                        highlights.append(AnalyticsHighlight(
                            type: .warning,
                            title: "Volume Down",
                            detail: "\(Int(pct))% vs last 7 days"
                        ))
                    }
                }
            }

            // Supplement with quality score if available and room remains
            if highlights.count < 3,
               let score = analyticsVM.qualityScore {
                highlights.append(AnalyticsHighlight(
                    type: .improvement,
                    title: "Quality",
                    detail: "\(Int(score.overallScore))/100"
                ))
            }

            // Weekly goal from plan's frequency (0 = no active plan)
            let weeklyGoal = activePlan?.weeklyFrequency ?? 0

            let workoutVM = container.workoutViewModel
            let restTimer = container.restTimerService
            let data = widgetService.buildWidgetData(
                workouts: workouts,
                highlights: highlights,
                activeWorkout: workoutVM.isActive ? workoutVM.currentWorkout : nil,
                isResting: restTimer.isRunning,
                restEndDate: restTimer.endDate,
                nextPlannedSession: nextPlanned,
                weeklyGoal: weeklyGoal
            )
            widgetService.updateWidgetData(data)
        } catch {
            print("[Widget] Failed to refresh widget data: \(error)")
        }
    }

}
#endif
