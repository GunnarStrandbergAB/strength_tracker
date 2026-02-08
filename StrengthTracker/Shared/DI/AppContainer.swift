#if canImport(SwiftData)
import SwiftData
import Foundation

// MARK: - Placeholder Protocols (will be implemented by other agents)

protocol HealthKitServiceProtocol: Sendable {
    func saveWorkout(_ workout: Workout) async throws
    func startWorkoutSession() async throws
    func endWorkoutSession(_ workout: Workout) async throws
}

final class NoOpHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    func saveWorkout(_ workout: Workout) async throws {}
    func startWorkoutSession() async throws {}
    func endWorkoutSession(_ workout: Workout) async throws {}
}

#if canImport(HealthKit)
final class DefaultHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    func saveWorkout(_ workout: Workout) async throws {
        // Implementation will be provided by Agent 2
    }
    func startWorkoutSession() async throws {
        // Implementation will be provided by Agent 2
    }
    func endWorkoutSession(_ workout: Workout) async throws {
        // Implementation will be provided by Agent 2
    }
}
#endif

#if canImport(WatchConnectivity)
import WatchConnectivity

final class ConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {
    func sendWorkoutCompleted(_ workout: Workout) {
        // Implementation will be provided by Agent 3
    }

    // WCSessionDelegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Implementation will be provided by Agent 3
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Implementation will be provided by Agent 3
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Implementation will be provided by Agent 3
    }
    #endif
}
#else
final class ConnectivityManager: NSObject, @unchecked Sendable {
    func sendWorkoutCompleted(_ workout: Workout) {
        // No-op on platforms without WatchConnectivity
    }
}
#endif

@MainActor
public final class AppContainer: Sendable {
    public let modelContainer: ModelContainer
    public let modelContext: ModelContext

    // Repositories
    public let exerciseRepository: any ExerciseRepository
    public let workoutRepository: any WorkoutRepository
    public let templateRepository: any TemplateRepository
    public let personalRecordRepository: any PersonalRecordRepository

    // Services
    public let personalRecordService: PersonalRecordService
    public let restTimerService: RestTimerService
    public let userPreferencesService: UserPreferencesService
    public let exerciseSeeder: ExerciseSeeder
    public let healthKitService: any HealthKitServiceProtocol
    public let connectivityManager: ConnectivityManager

    public init() throws {
        let schema = Schema([
            ExerciseEntity.self,
            WorkoutEntity.self,
            WorkoutExerciseEntity.self,
            ExerciseSetEntity.self,
            WorkoutTemplateEntity.self,
            TemplateExerciseEntity.self,
            PersonalRecordEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext

        // Wire up repositories
        exerciseRepository = SwiftDataExerciseRepository(modelContext: modelContext)
        workoutRepository = SwiftDataWorkoutRepository(modelContext: modelContext)
        templateRepository = SwiftDataTemplateRepository(modelContext: modelContext)
        personalRecordRepository = SwiftDataPersonalRecordRepository(modelContext: modelContext)

        // Wire up services
        personalRecordService = PersonalRecordService(
            personalRecordRepository: personalRecordRepository,
            workoutRepository: workoutRepository
        )
        restTimerService = RestTimerService()
        userPreferencesService = UserPreferencesService()
        exerciseSeeder = ExerciseSeeder(exerciseRepository: exerciseRepository)

        // Platform-specific services
        #if canImport(HealthKit)
        healthKitService = DefaultHealthKitService()
        #else
        healthKitService = NoOpHealthKitService()
        #endif
        connectivityManager = ConnectivityManager()
    }

    // Factory methods for ViewModels
    public func makeExerciseListViewModel() -> ExerciseListViewModel {
        ExerciseListViewModel(exerciseRepository: exerciseRepository)
    }

    public func makeWorkoutViewModel() -> WorkoutViewModel {
        WorkoutViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            personalRecordService: personalRecordService,
            healthKitService: healthKitService
        )
    }

    public func makeHistoryViewModel() -> HistoryViewModel {
        HistoryViewModel(workoutRepository: workoutRepository)
    }

    public func makeTemplateViewModel() -> TemplateViewModel {
        TemplateViewModel(
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository
        )
    }

    public func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(
            workoutRepository: workoutRepository,
            personalRecordRepository: personalRecordRepository
        )
    }

    public func makeProgressViewModel() -> ProgressViewModel {
        ProgressViewModel(
            exerciseRepository: exerciseRepository,
            workoutRepository: workoutRepository
        )
    }

    public func makeWatchWorkoutViewModel() -> WatchWorkoutViewModel {
        WatchWorkoutViewModel(
            workoutRepository: workoutRepository,
            healthKitService: healthKitService,
            connectivityManager: connectivityManager
        )
    }

    public func makeWatchWorkoutListViewModel() -> WatchWorkoutListViewModel {
        WatchWorkoutListViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository
        )
    }

    public func makePersonalRecordService() -> PersonalRecordService {
        personalRecordService
    }

    public func makeRestTimerService() -> RestTimerService {
        restTimerService
    }
}
#endif
