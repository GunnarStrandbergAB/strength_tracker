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
            Task { @MainActor in
                let seeder = ExerciseSeeder(exerciseRepository: container.exerciseRepository)
                await seeder.seedIfNeeded()
            }
        } catch {
            fatalError("Failed to initialize app: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                dashboardViewModel: container.makeDashboardViewModel(),
                exerciseListViewModel: container.makeExerciseListViewModel(),
                progressViewModel: container.makeProgressViewModel(),
                workoutViewModel: container.makeWorkoutViewModel(),
                historyViewModel: container.makeHistoryViewModel(),
                templateViewModel: container.makeTemplateViewModel(),
                userPreferencesService: container.userPreferencesService
            )
        }
        .modelContainer(container.modelContainer)
    }
}
#endif
