#if canImport(SwiftUI) && canImport(SwiftData)
import SwiftUI
import SwiftData
import StrengthTrackerShared

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@main
struct StrengthTrackerWatchApp: App {
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
        } catch {
            fatalError("Failed to initialize app: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView(
                workoutViewModel: container.makeWatchWorkoutViewModel(),
                listViewModel: container.makeWatchWorkoutListViewModel()
            )
        }
        .modelContainer(container.modelContainer)
    }
}
#endif
