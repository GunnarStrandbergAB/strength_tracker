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
    public let progressionPlanRepository: any ProgressionPlanRepository

    // Store
    public let storeService: StoreService
    public let proFeatureGate: ProFeatureGate

    // Services
    public let personalRecordService: PersonalRecordService
    public let restTimerService: RestTimerService
    public let userPreferencesService: UserPreferencesService
    public let exerciseSeeder: ExerciseSeeder
    public let templateSeedService: TemplateSeedService
    public let effectiveLoadMigrationService: EffectiveLoadMigrationService
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
    public let coachingInsightService: CoachingInsightService
    public let weightSuggestionService: WeightSuggestionService
    public let adherenceAnalysisService: AdherenceAnalysisService
    public let workoutArchetypeService: WorkoutArchetypeService
    public let changePointDetectionService: ChangePointDetectionService

    // Progression
    public let trainingStatusDetector: TrainingStatusDetector
    public let coachingCommunicationService: CoachingCommunicationService
    public let programDesignService: ProgramDesignService
    public let sessionExecutionService: SessionExecutionService
    public let adaptiveAdjustmentService: AdaptiveAdjustmentService
    public let planAnalyticsService: PlanAnalyticsService

    // Cached ViewModels (shared across multiple views)
    public let widgetRefreshService: WidgetRefreshService

    public let workoutViewModel: WorkoutViewModel
    public let templateViewModel: TemplateViewModel
    public let exerciseListViewModel: ExerciseListViewModel
    public let watchWorkoutViewModel: WatchWorkoutViewModel
    public let watchWorkoutListViewModel: WatchWorkoutListViewModel
    public let workoutAnalyticsViewModel: WorkoutAnalyticsViewModel
    public let progressionPlanViewModel: ProgressionPlanViewModel

    public init() throws {
        let schema = Schema([
            ExerciseEntity.self,
            WorkoutEntity.self,
            WorkoutExerciseEntity.self,
            ExerciseSetEntity.self,
            WorkoutTemplateEntity.self,
            TemplateExerciseEntity.self,
            PersonalRecordEntity.self,
            WorkoutVectorEntity.self,
            ProgressionPlanEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext

        // Wire up repositories
        exerciseRepository = SwiftDataExerciseRepository(modelContext: modelContext)
        workoutRepository = SwiftDataWorkoutRepository(modelContext: modelContext)
        templateRepository = SwiftDataTemplateRepository(modelContext: modelContext)
        personalRecordRepository = SwiftDataPersonalRecordRepository(modelContext: modelContext)
        progressionPlanRepository = SwiftDataProgressionPlanRepository(modelContext: modelContext)

        // Store
        storeService = StoreService()
        proFeatureGate = ProFeatureGate(storeService: storeService)

        // Wire up services
        userPreferencesService = UserPreferencesService()
        personalRecordService = PersonalRecordService(
            personalRecordRepository: personalRecordRepository,
            workoutRepository: workoutRepository,
            userPreferencesService: userPreferencesService
        )
        restTimerService = RestTimerService()
        exerciseSeeder = ExerciseSeeder(exerciseRepository: exerciseRepository)
        templateSeedService = TemplateSeedService(templateRepository: templateRepository, exerciseSeeder: exerciseSeeder)
        effectiveLoadMigrationService = EffectiveLoadMigrationService(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository,
            personalRecordService: personalRecordService,
            userPreferencesService: userPreferencesService
        )

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

        // Progression: TrainingStatusDetector needed by VolumeLandmarkService
        trainingStatusDetector = TrainingStatusDetector(workoutRepository: workoutRepository, userPreferencesService: userPreferencesService)

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

        // Advanced Insights services
        let volumeLandmark = VolumeLandmarkService(
            workoutRepository: workoutRepository,
            trainingStatusDetector: trainingStatusDetector
        )
        let recoveryEstimation = RecoveryEstimationService(workoutRepository: workoutRepository)
        let driftSvc = TrainingDriftService(searchService: searchService)
        let phaseDetection = PhaseDetectionService(searchService: searchService)
        let blockComparison = BlockComparisonService(searchService: searchService)
        let anomalyDetection = AnomalyDetectionService(searchService: searchService)

        let insightGen: any InsightTextGenerating
        if #available(iOS 26, macOS 26, *) {
            insightGen = AppleIntelligenceInsightGenerator(fallback: TemplateInsightGenerator())
        } else {
            insightGen = TemplateInsightGenerator()
        }

        workoutArchetypeService = WorkoutArchetypeService(searchService: searchService)
        changePointDetectionService = ChangePointDetectionService()

        analyticsService = WorkoutAnalyticsService(
            analyticsRepository: analyticsRepository,
            workoutRepository: workoutRepository,
            exerciseRepository: exerciseRepository,
            vectorizer: vectorizer,
            searchService: searchService,
            plateauService: plateauService,
            muscleBalanceService: muscleBalanceService,
            recommendationService: recommendationService,
            trainingStatusDetector: trainingStatusDetector,
            userPreferencesService: userPreferencesService,
            volumeLandmarkService: volumeLandmark,
            recoveryEstimationService: recoveryEstimation,
            driftService: driftSvc,
            phaseDetectionService: phaseDetection,
            blockComparisonService: blockComparison,
            anomalyDetectionService: anomalyDetection,
            insightGenerator: insightGen,
            archetypeService: workoutArchetypeService,
            changePointService: changePointDetectionService,
            qualityScoreService: qualityScoreService
        )

        coachingInsightService = CoachingInsightService(
            searchService: searchService,
            qualityScoreService: qualityScoreService,
            insightGenerator: insightGen
        )

        weightSuggestionService = WeightSuggestionService()
        adherenceAnalysisService = AdherenceAnalysisService()

        // Remaining progression services (stateless -- ADR-014)
        programDesignService = ProgramDesignService()
        sessionExecutionService = SessionExecutionService()
        adaptiveAdjustmentService = AdaptiveAdjustmentService(workoutRepository: workoutRepository, userPreferencesService: userPreferencesService)
        planAnalyticsService = PlanAnalyticsService(workoutRepository: workoutRepository, userPreferencesService: userPreferencesService)
        coachingCommunicationService = CoachingCommunicationService()

        // Initialize cached ViewModels
        workoutViewModel = WorkoutViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            personalRecordService: personalRecordService,
            healthKitService: healthKitService,
            calorieEstimationService: calorieEstimationService,
            userPreferencesService: userPreferencesService,
            analyticsService: analyticsService,
            webhookService: webhookService,
            progressionPlanRepository: progressionPlanRepository,
            coachingInsightService: coachingInsightService,
            weightSuggestionService: weightSuggestionService
        )
        templateViewModel = TemplateViewModel(
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository,
            connectivityManager: connectivityManager,
            userPreferencesService: userPreferencesService
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
            featureGate: analyticsFeatureGate,
            workoutRepository: workoutRepository,
            proFeatureGate: proFeatureGate,
            adherenceService: adherenceAnalysisService,
            coachingInsightService: coachingInsightService,
            userPreferencesService: userPreferencesService
        )
        widgetRefreshService = WidgetRefreshService(
            workoutRepository: workoutRepository,
            progressionPlanRepository: progressionPlanRepository,
            healthKitService: healthKitService,
            userPreferencesService: userPreferencesService,
            analyticsService: analyticsService,
            qualityScoreService: qualityScoreService,
            workoutAnalyticsViewModel: workoutAnalyticsViewModel,
            workoutViewModel: workoutViewModel,
            restTimerService: restTimerService
        )
        progressionPlanViewModel = ProgressionPlanViewModel(
            progressionPlanRepository: progressionPlanRepository,
            trainingStatusDetector: trainingStatusDetector,
            programDesignService: programDesignService,
            planAnalyticsService: planAnalyticsService,
            exerciseRepository: exerciseRepository,
            templateRepository: templateRepository,
            userPreferencesService: userPreferencesService,
            workoutRepository: workoutRepository,
            sessionExecutionService: sessionExecutionService,
            adaptiveAdjustmentService: adaptiveAdjustmentService,
            coachingCommunicationService: coachingCommunicationService
        )

        // Route planned-session completions through the adaptive progression
        // pipeline (APRE + 1RM updates + adviser proposals) instead of the
        // plain markSessionCompleted repository call.
        let planVM = progressionPlanViewModel
        workoutViewModel.onPlannedSessionCompleted = { [weak planVM] sessionId, planId, workoutId in
            await planVM?.handleSessionCompleted(
                sessionId: sessionId, planId: planId, workoutId: workoutId
            )
        }
    }

    // Factory methods for ViewModels
    public func makeExerciseListViewModel() -> ExerciseListViewModel {
        exerciseListViewModel
    }

    public func makeWorkoutViewModel() -> WorkoutViewModel {
        workoutViewModel
    }

    public func makeHistoryViewModel() -> HistoryViewModel {
        HistoryViewModel(
            workoutRepository: workoutRepository,
            userPreferencesService: userPreferencesService,
            templateRepository: templateRepository,
            analyticsService: analyticsService,
            personalRecordService: personalRecordService,
            healthKitService: healthKitService,
            calorieEstimationService: calorieEstimationService,
            webhookService: webhookService,
            widgetRefreshService: widgetRefreshService,
            qualityScoreService: qualityScoreService
        )
    }

    public func makeTemplateViewModel() -> TemplateViewModel {
        templateViewModel
    }

    public func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(
            workoutRepository: workoutRepository,
            personalRecordRepository: personalRecordRepository,
            qualityScoreService: qualityScoreService,
            healthKitService: healthKitService,
            userPreferencesService: userPreferencesService
        )
    }

    public func makeProgressViewModel() -> ProgressViewModel {
        ProgressViewModel(
            exerciseRepository: exerciseRepository,
            workoutRepository: workoutRepository,
            userPreferencesService: userPreferencesService
        )
    }

    public func makeWorkoutAnalyticsViewModel() -> WorkoutAnalyticsViewModel {
        workoutAnalyticsViewModel
    }

    public func makeProgressionPlanViewModel() -> ProgressionPlanViewModel {
        progressionPlanViewModel
    }
}
#endif
