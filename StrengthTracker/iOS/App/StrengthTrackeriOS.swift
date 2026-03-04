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
                // Refresh widgets when app becomes active
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
                #endif

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
                                            session: session, template: linked
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
}
#endif
