import Foundation
import Observation

#if canImport(SwiftData)
import SwiftData
#endif

@Observable
@MainActor
final class WatchWorkoutListViewModel: Sendable {
    var recentWorkouts: [Workout] = []
    var templates: [WorkoutTemplate] = []
    var syncStatus: SyncStatus = .idle
    var errorMessage: String?

    enum SyncStatus: Sendable {
        case idle
        case syncing
        case synced
        case error(String)
    }

    #if canImport(SwiftData)
    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository

    init(workoutRepository: any WorkoutRepository, templateRepository: any TemplateRepository) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
    }
    #else
    init() {}
    #endif

    func loadData() async {
        #if canImport(SwiftData)
        do {
            syncStatus = .syncing

            // Load recent workouts (limit to 5 most recent)
            let allWorkouts = try await workoutRepository.fetchAll()
            recentWorkouts = allWorkouts
                .sorted { ($0.startedAt) > ($1.startedAt) }
                .prefix(5)
                .map { $0 }

            // Load all templates
            templates = try await templateRepository.fetchAll()
                .sorted { $0.sortOrder < $1.sortOrder }

            syncStatus = .synced
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .error(error.localizedDescription)
        }
        #endif
    }

    func deleteWorkout(_ workout: Workout) async {
        #if canImport(SwiftData)
        do {
            try await workoutRepository.delete(workout)
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }
}
