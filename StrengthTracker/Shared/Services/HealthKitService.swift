import Foundation

// MARK: - Protocol (always available for cross-platform compatibility)

/// Protocol for HealthKit integration. Available on all platforms for compilation compatibility.
protocol HealthKitServiceProtocol: Sendable {
    /// Request authorization to read and write health data
    func requestAuthorization() async throws

    /// Check if the user has authorized health data access
    func isAuthorized() -> Bool

    /// Save a completed workout to HealthKit
    /// - Parameter workout: The workout to save
    func saveWorkout(_ workout: Workout) async throws

    /// Fetch recent workouts from HealthKit
    /// - Parameter limit: Maximum number of workouts to fetch
    /// - Returns: Array of workout summaries
    func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary]
}

// MARK: - Data Models

/// Summary of a HealthKit workout
struct HealthKitWorkoutSummary: Sendable, Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let totalEnergyBurned: Double? // kcal
    let duration: TimeInterval
}

// MARK: - Platform-Specific Implementation

#if canImport(HealthKit)
import HealthKit

/// Default HealthKit service implementation for platforms that support HealthKit
final class DefaultHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    private let healthStore = HKHealthStore()

    func requestAuthorization() async throws {
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    func isAuthorized() -> Bool {
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
    }

    func saveWorkout(_ workout: Workout) async throws {
        guard let startDate = Optional(workout.startedAt),
              let endDate = workout.completedAt else {
            return
        }

        let totalDuration = endDate.timeIntervalSince(startDate)

        // Create metadata with workout details
        var metadata: [String: Any] = [
            "StrengthTrackerWorkoutId": workout.id.uuidString,
            "WorkoutName": workout.name
        ]

        if let notes = workout.notes {
            metadata["Notes"] = notes
        }

        // Add workout statistics
        metadata["TotalVolume"] = workout.totalVolume
        metadata["ExerciseCount"] = workout.exercises.count

        let hkWorkout = HKWorkout(
            activityType: .traditionalStrengthTraining,
            start: startDate,
            end: endDate,
            duration: totalDuration,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: metadata
        )

        try await healthStore.save(hkWorkout)
    }

    func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] {
        await withCheckedContinuation { continuation in
            let workoutType = HKObjectType.workoutType()
            let predicate = HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let summaries = (samples as? [HKWorkout])?.map { workout in
                    HealthKitWorkoutSummary(
                        id: workout.uuid,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        duration: workout.duration
                    )
                } ?? []
                continuation.resume(returning: summaries)
            }

            healthStore.execute(query)
        }
    }
}
#endif

// MARK: - Non-HealthKit Platform Implementation

#if !canImport(HealthKit)
/// Fallback implementation for platforms without HealthKit support
final class DefaultHealthKitService: HealthKitServiceProtocol {
    func requestAuthorization() async throws {}

    func isAuthorized() -> Bool {
        false
    }

    func saveWorkout(_ workout: Workout) async throws {}

    func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] {
        []
    }
}
#endif

// MARK: - No-Op Implementation

/// No-op implementation for testing or when HealthKit is disabled
final class NoOpHealthKitService: HealthKitServiceProtocol {
    func requestAuthorization() async throws {}

    func isAuthorized() -> Bool {
        false
    }

    func saveWorkout(_ workout: Workout) async throws {}

    func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] {
        []
    }
}
