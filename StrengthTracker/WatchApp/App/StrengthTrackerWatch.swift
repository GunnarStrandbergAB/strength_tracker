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

    #if canImport(HealthKit) && os(watchOS)
    let healthKitManager = WatchHealthKitManager()
    #endif

    init() {
        do {
            container = try AppContainer()

            // Wire WatchHealthKitManager into the ViewModel (Fix 5)
            #if canImport(HealthKit) && os(watchOS)
            container.watchWorkoutViewModel.setWatchSessionManager(healthKitManager)
            #endif

            // Initialize WatchConnectivity
            #if canImport(WatchConnectivity)
            if WCSession.isSupported() {
                let session = WCSession.default
                session.delegate = container.connectivityManager
                session.activate()
            }
            #endif

            // Seed exercises on Watch (same as iOS)
            container.exerciseSeeder.startSeeding()

            // Request HealthKit authorization early so prompt appears on iPhone
            // Then recover orphaned HealthKit workout session on launch (Fix 7)
            #if canImport(HealthKit) && os(watchOS)
            let hkManager = healthKitManager
            Task { @MainActor in
                do {
                    try await hkManager.requestAuthorization()
                } catch {
                    print("[Watch] HealthKit authorization failed: \(error)")
                }
                await hkManager.recoverOrphanedSession()
            }
            #endif

            // Wire template sync: when templates arrive from iPhone, replace local data
            let templateRepo = container.templateRepository
            let listVM = container.watchWorkoutListViewModel
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

            // Wire exercise sync: when exercises arrive from iPhone, upsert local data
            let exerciseRepo = container.exerciseRepository
            container.connectivityManager.onExercisesReceived = { receivedExercises in
                Task { @MainActor in
                    do {
                        let receivedIds = Set(receivedExercises.map(\.id))
                        let existing = try await exerciseRepo.fetchAll()
                        for local in existing where !receivedIds.contains(local.id) && local.isCustom {
                            try await exerciseRepo.delete(local)
                        }
                        for exercise in receivedExercises {
                            _ = try await exerciseRepo.save(exercise)
                        }
                    } catch {
                        print("Watch: Failed to sync exercises - \(error)")
                    }
                }
            }

            // Wire settings sync: when settings arrive from iPhone, apply to local preferences
            let prefs = container.userPreferencesService
            container.connectivityManager.onSettingsReceived = { settings in
                Task { @MainActor in
                    if let restSeconds = settings["defaultRestSeconds"] as? Int {
                        prefs.defaultRestSeconds = restSeconds
                    }
                    if let weightRaw = settings["weightUnit"] as? String,
                       let unit = WeightUnit(rawValue: weightRaw) {
                        prefs.weightUnit = unit
                    }
                    if let autoRest = settings["autoStartRestTimer"] as? Bool {
                        prefs.autoStartRestTimer = autoRest
                    }
                    if let distanceRaw = settings["distanceUnit"] as? String,
                       let unit = DistanceUnit(rawValue: distanceRaw) {
                        prefs.distanceUnit = unit
                    }
                }
            }

            // Process any context that arrived while app was not running (Fix 4)
            #if canImport(WatchConnectivity)
            if WCSession.isSupported() {
                let existingContext = WCSession.default.receivedApplicationContext
                if !existingContext.isEmpty {
                    container.connectivityManager.processReceivedContext(existingContext)
                }
            }
            #endif
        } catch {
            fatalError("Failed to initialize app: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView(
                workoutViewModel: container.watchWorkoutViewModel,
                listViewModel: container.watchWorkoutListViewModel,
                exerciseListViewModel: container.exerciseListViewModel
            )
        }
        .modelContainer(container.modelContainer)
    }
}
#endif
