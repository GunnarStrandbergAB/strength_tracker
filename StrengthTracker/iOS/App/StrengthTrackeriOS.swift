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

            // One-time effective-load migration once the library carries factors
            Task { [container] in
                await container.exerciseSeeder.ensureSeeded()
                await container.effectiveLoadMigrationService.migrateIfNeeded()
            }

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
            let progressionPlanVM = container.progressionPlanViewModel
            container.connectivityManager.onWorkoutReceived = { workout, metadata in
                Task { @MainActor in
                    do {
                        // Guard against duplicate/out-of-order transfers: never let a
                        // non-completed copy overwrite an already-completed stored workout.
                        if let existing = try await workoutRepo.fetchAll().first(where: { $0.id == workout.id }),
                           existing.completedAt != nil, workout.completedAt == nil {
                            return
                        }
                        _ = try await workoutRepo.save(workout)
                        await webhookService.send(workout)

                        // Run the adaptive completion pipeline if Watch sent session/plan IDs
                        if let sessionIdStr = metadata?["plannedSessionId"],
                           let planIdStr = metadata?["plannedPlanId"],
                           let sessionId = UUID(uuidString: sessionIdStr),
                           let planId = UUID(uuidString: planIdStr) {
                            await progressionPlanVM.handleSessionCompleted(
                                sessionId: sessionId, planId: planId, workoutId: workout.id
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
    @State private var didRestore: Bool

    init(container: AppContainer) {
        self.container = container
        // Skip the gate when no active workout is pending — normal launches stay instant.
        // When a workout is pending (cold relaunch during a rest timer), gate the first
        // frame on `restoreActiveWorkout()` so we never momentarily show Dashboard.
        _didRestore = State(initialValue: !WorkoutViewModel.hasPendingActiveWorkout)
    }

    @ViewBuilder
    private var content: some View {
        if didRestore {
            ContentView(
                dashboardViewModel: container.makeDashboardViewModel(),
                exerciseListViewModel: container.makeExerciseListViewModel(),
                progressViewModel: container.makeProgressViewModel(),
                workoutViewModel: container.makeWorkoutViewModel(),
                workoutSessionCoordinator: container.workoutSessionCoordinator,
                historyViewModel: container.makeHistoryViewModel(),
                templateViewModel: container.makeTemplateViewModel(),
                analyticsViewModel: container.makeWorkoutAnalyticsViewModel(),
                progressionPlanViewModel: container.makeProgressionPlanViewModel(),
                userPreferencesService: container.userPreferencesService,
                connectivityManager: container.connectivityManager,
                restTimerService: container.restTimerService,
                personalRecordService: container.personalRecordService,
                proFeatureGate: container.proFeatureGate,
                storeService: container.storeService,
                aiCredentialsService: container.aiCredentialsService,
                aiChatClient: container.aiChatClient,
                aiChatViewModel: container.makeAIChatViewModel(),
                aiMemoryService: container.aiMemoryService
            )
        } else {
            STColors.background.ignoresSafeArea()
        }
    }

    var body: some View {
        content
        .onOpenURL { url in
            // Handle deep links from widgets
            handleDeepLink(url)
        }
        .task {
            await container.workoutViewModel.restoreActiveWorkout()
            didRestore = true
        }
        .task {
            // Failsafe: never trap the user on a blank splash if restore hangs.
            try? await Task.sleep(for: .seconds(3))
            if !didRestore { didRestore = true }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
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
                                .filter { !$0.isClosed }
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
                                        isDeload: session.isDeload,
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
                        "distanceUnit": prefs.distanceUnit.rawValue,
                        "bodyWeightKg": prefs.bodyWeightKg ?? 0
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

        // Process any pending set completions from widget intents — stays in the app
        // layer because it mutates the live workout singleton.
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

        await container.widgetRefreshService.refresh()
    }

}
#endif
