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

            let exerciseRepo = container.exerciseRepository
            Task { @MainActor in
                let seeder = ExerciseSeeder(exerciseRepository: exerciseRepo)
                await seeder.seedIfNeeded()
            }

            // Wire up Watch → iPhone workout sync
            let workoutRepo = container.workoutRepository
            container.connectivityManager.onWorkoutReceived = { workout in
                Task { @MainActor in
                    do {
                        _ = try await workoutRepo.save(workout)
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
            userPreferencesService: container.userPreferencesService
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

                // Sync templates and exercises to Watch when app becomes active
                Task { @MainActor in
                    do {
                        let templates = try await container.templateRepository.fetchAll()
                        container.connectivityManager.syncTemplates(templates)

                        let exercises = try await container.exerciseRepository.fetchAll()
                        container.connectivityManager.syncExercises(exercises)
                    } catch {
                        print("Failed to sync data on activation: \(error)")
                    }
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
