import Foundation
@testable import StrengthTrackerShared

/// Mock HealthKit service for testing
final class MockHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    // MARK: - Test Properties

    var authorizationRequested = false
    var saveWorkoutCalled = false
    var savedWorkout: Workout?
    var savedCalories: Double?
    var mockBodyWeightKg: Double?
    var addCaloriesCalled = false
    var addCaloriesWorkoutId: UUID?

    // MARK: - Error Simulation

    var authorizationError: Error?
    var saveWorkoutError: Error?

    // MARK: - HealthKitServiceProtocol

    func requestAuthorization() async throws {
        authorizationRequested = true
        if let error = authorizationError {
            throw error
        }
    }

    var savedWorkoutIds: [UUID] = []
    var deletedWorkoutIds: [UUID] = []

    @discardableResult
    func saveWorkout(_ workout: Workout, calories: Double, bodyWeightKg: Double) async throws -> UUID? {
        saveWorkoutCalled = true
        savedWorkout = workout
        savedCalories = calories
        savedWorkoutIds.append(workout.id)
        if let error = saveWorkoutError {
            throw error
        }
        return UUID()
    }

    func deleteWorkout(appWorkoutId: UUID) async throws {
        deletedWorkoutIds.append(appWorkoutId)
    }

    func addCaloriesToExistingWorkout(healthKitWorkoutId: UUID, calories: Double, workout: Workout) async throws {
        addCaloriesCalled = true
        addCaloriesWorkoutId = healthKitWorkoutId
        savedCalories = calories
    }

    func fetchBodyWeightKg() async -> Double? {
        mockBodyWeightKg
    }

    func startWorkoutSession() async throws {}

    func endWorkoutSession(_ workout: Workout) async throws {}

    // MARK: - Test Helpers

    func reset() {
        authorizationRequested = false
        saveWorkoutCalled = false
        savedWorkout = nil
        savedCalories = nil
        mockBodyWeightKg = nil
        addCaloriesCalled = false
        addCaloriesWorkoutId = nil
        authorizationError = nil
        saveWorkoutError = nil
    }
}
