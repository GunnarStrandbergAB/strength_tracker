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
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Deep link handling will be implemented by other agents
        // Format: strengthtracker://workout/start?template=<uuid>
    }
}
#endif
