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
    public let calorieEstimationService: CalorieEstimationService
    public let webhookService: WebhookService

    // Analytics
    public let analyticsRepository: any AnalyticsRepository
    public let vectorizer: WorkoutVectorizer
    public let searchService: VectorSearchService
    public let plateauService: PlateauDetectionService
    public let muscleBalanceService: MuscleBalanceService
    public let recommendationService: ExerciseRecommendationService
    public let qualityScoreService: WorkoutQualityScoreService
    public let analyticsFeatureGate: AnalyticsFeatureGate
    public let analyticsService: WorkoutAnalyticsService

    // Cached ViewModels (shared across multiple views)
    public let workoutViewModel: WorkoutViewModel
    public let templateViewModel: TemplateViewModel
    public let exerciseListViewModel: ExerciseListViewModel
    public let watchWorkoutViewModel: WatchWorkoutViewModel
    public let watchWorkoutListViewModel: WatchWorkoutListViewModel
    public let workoutAnalyticsViewModel: WorkoutAnalyticsViewModel

    public init() throws {
        let schema = Schema([
            ExerciseEntity.self,
            WorkoutEntity.self,
            WorkoutExerciseEntity.self,
            ExerciseSetEntity.self,
            WorkoutTemplateEntity.self,
            TemplateExerciseEntity.self,
            PersonalRecordEntity.self,
            WorkoutVectorEntity.self
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
        calorieEstimationService = CalorieEstimationService()
        webhookService = WebhookService(preferencesService: userPreferencesService)

        // Analytics repository (vector-only, no workoutRepository dependency -- ADR-011)
        analyticsRepository = SwiftDataAnalyticsRepository(modelContext: modelContext)

        // Analytics services (stateless -- ADR-012)
        vectorizer = WorkoutVectorizer()
        searchService = VectorSearchService()
        plateauService = PlateauDetectionService()
        muscleBalanceService = MuscleBalanceService()
        recommendationService = ExerciseRecommendationService()
        qualityScoreService = WorkoutQualityScoreService(
            workoutRepository: workoutRepository,
            muscleBalanceService: muscleBalanceService,
            healthKitService: healthKitService,
            userPreferencesService: userPreferencesService
        )
        analyticsFeatureGate = AnalyticsFeatureGate(workoutRepository: workoutRepository)
        analyticsService = WorkoutAnalyticsService(
            analyticsRepository: analyticsRepository,
            workoutRepository: workoutRepository,
            exerciseRepository: exerciseRepository,
            vectorizer: vectorizer,
            searchService: searchService,
            plateauService: plateauService,
            muscleBalanceService: muscleBalanceService,
            recommendationService: recommendationService
        )

        // Initialize cached ViewModels
        workoutViewModel = WorkoutViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            personalRecordService: personalRecordService,
            healthKitService: healthKitService,
            calorieEstimationService: calorieEstimationService,
            userPreferencesService: userPreferencesService,
            analyticsService: analyticsService,
            webhookService: webhookService
        )
        templateViewModel = TemplateViewModel(
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository,
            connectivityManager: connectivityManager
        )
        exerciseListViewModel = ExerciseListViewModel(exerciseRepository: exerciseRepository, exerciseSeeder: exerciseSeeder)
        watchWorkoutViewModel = WatchWorkoutViewModel(
            workoutRepository: workoutRepository,
            healthKitService: healthKitService,
            connectivityManager: connectivityManager,
            userPreferencesService: userPreferencesService,
            analyticsService: analyticsService
        )
        watchWorkoutListViewModel = WatchWorkoutListViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository
        )
        workoutAnalyticsViewModel = WorkoutAnalyticsViewModel(
            analyticsService: analyticsService,
            qualityScoreService: qualityScoreService,
            featureGate: analyticsFeatureGate
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
            personalRecordRepository: personalRecordRepository,
            qualityScoreService: qualityScoreService
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

    public func makeWorkoutAnalyticsViewModel() -> WorkoutAnalyticsViewModel {
        workoutAnalyticsViewModel
    }
}
#endif
