#if canImport(SwiftData)
import SwiftData
import Foundation

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

    // Cached ViewModels (shared across multiple views)
    public let workoutViewModel: WorkoutViewModel
    public let templateViewModel: TemplateViewModel
    public let exerciseListViewModel: ExerciseListViewModel
    public let watchWorkoutViewModel: WatchWorkoutViewModel
    public let watchWorkoutListViewModel: WatchWorkoutListViewModel

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

        // Initialize cached ViewModels
        workoutViewModel = WorkoutViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            personalRecordService: personalRecordService,
            healthKitService: healthKitService
        )
        templateViewModel = TemplateViewModel(
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository,
            connectivityManager: connectivityManager
        )
        exerciseListViewModel = ExerciseListViewModel(exerciseRepository: exerciseRepository)
        watchWorkoutViewModel = WatchWorkoutViewModel(
            workoutRepository: workoutRepository,
            healthKitService: healthKitService,
            connectivityManager: connectivityManager
        )
        watchWorkoutListViewModel = WatchWorkoutListViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository
        )
    }

    // Factory methods for ViewModels
    public func makeExerciseListViewModel() -> ExerciseListViewModel {
        exerciseListViewModel
    }

    public func makeWorkoutViewModel() -> WorkoutViewModel {
        workoutViewModel
    }

    public func makeHistoryViewModel() -> HistoryViewModel {
        HistoryViewModel(workoutRepository: workoutRepository)
    }

    public func makeTemplateViewModel() -> TemplateViewModel {
        templateViewModel
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
        watchWorkoutViewModel
    }

    public func makeWatchWorkoutListViewModel() -> WatchWorkoutListViewModel {
        watchWorkoutListViewModel
    }

    public func makePersonalRecordService() -> PersonalRecordService {
        personalRecordService
    }

    public func makeRestTimerService() -> RestTimerService {
        restTimerService
    }
}
#endif
