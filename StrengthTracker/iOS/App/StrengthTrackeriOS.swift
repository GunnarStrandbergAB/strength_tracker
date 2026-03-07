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

@main
struct StrengthTrackeriOSApp: App {
    let container: AppContainer

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
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

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
        // Deep link handling will be implemented by other agents
        // Format: strengthtracker://workout/start?template=<uuid>
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

            // Build next planned session
            var nextPlanned: WidgetPlannedSession? = nil
            if let plan = try await container.progressionPlanRepository.fetchActive(),
               let week = plan.currentWeek,
               let nextSession = week.sessions.first(where: { !$0.isCompleted }) {
                nextPlanned = WidgetPlannedSession(
                    sessionName: nextSession.sessionLabel,
                    exerciseNames: Array(nextSession.plannedExercises.prefix(4).map(\.exerciseName)),
                    planName: plan.name
                )
            }

            let workoutVM = container.workoutViewModel
            let restTimer = container.restTimerService
            let data = widgetService.buildWidgetData(
                workouts: workouts,
                highlights: highlights,
                activeWorkout: workoutVM.isActive ? workoutVM.currentWorkout : nil,
                isResting: restTimer.isRunning,
                restEndDate: restTimer.endDate,
                nextPlannedSession: nextPlanned,
                weeklyGoal: 4
            )
            widgetService.updateWidgetData(data)
        } catch {
            print("[Widget] Failed to refresh widget data: \(error)")
        }
    }
}
#endif
