import Foundation
@testable import StrengthTrackerShared

/// Mock HealthKit service for testing
final class MockHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    // MARK: - Test Properties

    var isAuthorizedResult = false
    var authorizationRequested = false
    var saveWorkoutCalled = false
    var savedWorkout: Workout?
    var fetchRecentWorkoutsCalled = false
    var fetchLimit: Int?
    var mockRecentWorkouts: [HealthKitWorkoutSummary] = []

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
        fetchRecentWorkoutsCalled = false
        fetchLimit = nil
        mockRecentWorkouts = []
        authorizationError = nil
        saveWorkoutError = nil
    }
}
