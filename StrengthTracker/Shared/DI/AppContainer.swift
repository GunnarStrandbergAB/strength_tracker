#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
final class AppContainer: Sendable {
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    // Repositories
    let exerciseRepository: any ExerciseRepository
    let workoutRepository: any WorkoutRepository
    let templateRepository: any TemplateRepository
    let personalRecordRepository: any PersonalRecordRepository

    // Services
    let personalRecordService: PersonalRecordService
    let restTimerService: RestTimerService
    let userPreferencesService: UserPreferencesService
    let exerciseSeeder: ExerciseSeeder

    init() throws {
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
    }

    // Factory methods for ViewModels
    func makeExerciseListViewModel() -> ExerciseListViewModel {
        ExerciseListViewModel(exerciseRepository: exerciseRepository)
    }

    func makeWorkoutViewModel() -> WorkoutViewModel {
        WorkoutViewModel(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            personalRecordService: personalRecordService
        )
    }

    func makeHistoryViewModel() -> HistoryViewModel {
        HistoryViewModel(workoutRepository: workoutRepository)
    }

    func makeTemplateViewModel() -> TemplateViewModel {
        TemplateViewModel(
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository
        )
    }

    func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(
            workoutRepository: workoutRepository,
            personalRecordRepository: personalRecordRepository
        )
    }

    func makeProgressViewModel() -> ProgressViewModel {
        ProgressViewModel(
            exerciseRepository: exerciseRepository,
            workoutRepository: workoutRepository
        )
    }

    func makeWatchWorkoutViewModel() -> WatchWorkoutViewModel {
        WatchWorkoutViewModel(workoutRepository: workoutRepository)
    }

    func makePersonalRecordService() -> PersonalRecordService {
        personalRecordService
    }

    func makeRestTimerService() -> RestTimerService {
        restTimerService
    }
}
#endif
