import Foundation

/// Repository for WorkoutVectorEntity only (DDD: one repository per aggregate/entity type).
/// Workout queries belong on WorkoutRepository, not here.
@MainActor
public protocol AnalyticsRepository: Sendable {
    func storeVector(_ vector: WorkoutVector, totalVolume: Double, workoutDate: Date, primaryMuscleGroups: [String]) async throws
    func fetchVector(for workoutId: UUID) async throws -> WorkoutVector?
    func fetchAllVectors() async throws -> [WorkoutVector]
    func fetchVectorsByDateRange(_ start: Date, _ end: Date) async throws -> [WorkoutVector]
    func deleteVector(for workoutId: UUID) async throws
}
