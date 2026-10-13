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
                await container.workoutFinalizer.migrateAnalyticsModelIfNeeded()
                await container.weightRecordingService.resume()
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
            let finalizer = container.workoutFinalizer
            container.connectivityManager.onWorkoutReceived = { workout, metadata in
                Task { @MainActor in
                    // One pipeline for every completed workout: plan session, vector,
                    // PRs, caches, webhook, revision, widgets (HealthKit stays Watch-side).
                    await finalizer.workoutReceivedFromWatch(workout, metadata: metadata)
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
        .environment(container.bodyWeightProvider)
        .environment(container.dataRevision)
        .environment(container.weightRecordingService)
    }

}

struct ContentViewWrapper: View {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRestore: Bool
    @State private var navigation = AppNavigationState()

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
                navigation: navigation,
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
        .modifier(AppNavigationLifecycle(navigation: navigation,
            hasActiveWorkout: container.workoutViewModel.isActive,
            hasProAccess: container.workoutAnalyticsViewModel.hasProAccess))
        .onOpenURL { url in
            guard let link = AppLink(url) else { return }
            navigation.receive(link, hasProAccess: container.workoutAnalyticsViewModel.hasProAccess)
            if link == .restTimer {
                container.restTimerService.handleForegroundReturn()
                container.restTimerService.endAllStaleActivities()
            }
        }
        .task {
            await container.workoutViewModel.restoreActiveWorkout()
            navigation.restorationFinished(hasActiveWorkout: container.workoutViewModel.isActive,
                workoutID: container.workoutViewModel.currentWorkout?.id,
                hasProAccess: container.workoutAnalyticsViewModel.hasProAccess)
            didRestore = true
        }
        .task {
            // Failsafe: never trap the user on a blank splash if restore hangs.
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            if !didRestore {
                // Show usable content, but keep links queued until the restore
                // result is known. Do not let the fallback consume a launch URL.
                didRestore = true
            }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            if newPhase == .active {
                // End stale mirrored Live Activity if watch timer expired while iPhone was backgrounded
                container.restTimerService.handleForegroundReturn()
                container.restTimerService.endAllStaleActivities()

                // Body weight first (HealthKit may have a newer sample), then widgets.
                Task { @MainActor in
                    await container.bodyWeightProvider.refresh()
                    await refreshWidgetData()
                }

                // Sync templates, exercises, settings, and planned sessions to Watch when app becomes active
                Task { @MainActor in
                    do {
                        let allTemplates = try await container.templateRepository.fetchAll()
                        // Only sync user-created templates to Watch (not seed/library templates)
                        let exercises = try await container.exerciseRepository.fetchAll()
                        container.connectivityManager.syncTemplates(allTemplates.filter { $0.isCustom }.map { $0.resolvingBodyweight(from: exercises) })
                        container.connectivityManager.syncExercises(exercises)

                        await container.syncActivePlanToWatch()
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
