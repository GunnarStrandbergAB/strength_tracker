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

            // Seed exercises on Watch (same as iOS)
            let seeder = container.exerciseSeeder
            Task { @MainActor in
                await seeder.seedIfNeeded()
            }

            // Wire template sync: when templates arrive from iPhone, replace local data
            let templateRepo = container.templateRepository
            let listVM = container.makeWatchWorkoutListViewModel()
            container.connectivityManager.onTemplatesReceived = { receivedTemplates in
                Task { @MainActor in
                    do {
                        // Full replace: save all received, delete any not in set
                        let receivedIds = Set(receivedTemplates.map(\.id))
                        let existing = try await templateRepo.fetchAll()
                        for local in existing where !receivedIds.contains(local.id) {
                            try await templateRepo.delete(local)
                        }
                        for template in receivedTemplates {
                            _ = try await templateRepo.save(template)
                        }
                        // Refresh the list view
                        await listVM.loadData()
                    } catch {
                        print("Watch: Failed to sync templates - \(error)")
                    }
                }
            }
        } catch {
            fatalError("Failed to initialize app: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView(
                workoutViewModel: container.makeWatchWorkoutViewModel(),
                listViewModel: container.makeWatchWorkoutListViewModel(),
                exerciseListViewModel: container.exerciseListViewModel
            )
        }
        .modelContainer(container.modelContainer)
    }
}
#endif
