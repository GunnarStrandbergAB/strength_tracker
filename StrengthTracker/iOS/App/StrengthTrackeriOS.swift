#if canImport(SwiftUI) && canImport(SwiftData)
import SwiftUI
import SwiftData
import StrengthTrackerShared

@main
struct StrengthTrackeriOSApp: App {
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
            ContentView(
                exerciseListViewModel: container.makeExerciseListViewModel(),
                workoutViewModel: container.makeWorkoutViewModel(),
                historyViewModel: container.makeHistoryViewModel(),
                templateViewModel: container.makeTemplateViewModel()
            )
        }
        .modelContainer(container.modelContainer)
    }
}
#endif
