#if canImport(SwiftUI) && canImport(SwiftData)
import SwiftUI
import SwiftData
import StrengthTrackerShared

@main
struct StrengthTrackerWatchApp: App {
    let container: AppContainer

    init() {
        do {
            container = try AppContainer()
        } catch {
            fatalError("Failed to initialize app: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView(viewModel: container.makeWatchWorkoutViewModel())
        }
        .modelContainer(container.modelContainer)
    }
}
#endif
