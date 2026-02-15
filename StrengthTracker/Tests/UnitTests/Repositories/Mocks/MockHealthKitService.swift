import Foundation
@testable import StrengthTrackerShared

/// Mock HealthKit service for testing
final class MockHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    // MARK: - Test Properties

    var isAuthorizedResult = false
    var authorizationRequested = false
    var saveWorkoutCalled = false
    var savedWorkout: Workout?
    var savedCalories: Double?
    var fetchRecentWorkoutsCalled = false
    var fetchLimit: Int?
    var mockRecentWorkouts: [HealthKitWorkoutSummary] = []
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

    func isAuthorized() -> Bool {
        isAuthorizedResult
    }

    func saveWorkout(_ workout: Workout) async throws {
        saveWorkoutCalled = true
        savedWorkout = workout
        if let error = saveWorkoutError {
            throw error
        }
    }

    func saveWorkout(_ workout: Workout, calories: Double) async throws {
        saveWorkoutCalled = true
        savedWorkout = workout
        savedCalories = calories
        if let error = saveWorkoutError {
            throw error
        }
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

    func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] {
        fetchRecentWorkoutsCalled = true
        fetchLimit = limit
        return mockRecentWorkouts
    }

    // MARK: - Test Helpers

    func reset() {
        isAuthorizedResult = false
        authorizationRequested = false
        saveWorkoutCalled = false
        savedWorkout = nil
        savedCalories = nil
        fetchRecentWorkoutsCalled = false
        fetchLimit = nil
        mockRecentWorkouts = []
        mockBodyWeightKg = nil
        addCaloriesCalled = false
        addCaloriesWorkoutId = nil
        authorizationError = nil
        saveWorkoutError = nil
    }
}
