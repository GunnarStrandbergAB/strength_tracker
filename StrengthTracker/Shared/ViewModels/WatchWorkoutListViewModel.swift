import Foundation
import Observation

#if canImport(SwiftData)
import SwiftData
#endif

@Observable
@MainActor
public final class WatchWorkoutListViewModel: Sendable {
    public var recentWorkouts: [Workout] = []
    public var templates: [WorkoutTemplate] = []
    public var plannedSessions: [PlannedSessionSync] = []
    public var syncStatus: SyncStatus = .idle
    public var errorMessage: String?

    public enum SyncStatus: Sendable {
        case idle
        case syncing
        case synced
        case error(String)
    }

    #if canImport(SwiftData)
    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository

    public init(workoutRepository: any WorkoutRepository, templateRepository: any TemplateRepository) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
    }
    #else
    public init() {}
    #endif

    public func loadData() async {
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

    public func deleteWorkout(_ workout: Workout) async {
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
