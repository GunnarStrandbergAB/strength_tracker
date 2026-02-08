import Foundation

// MARK: - Protocol (always available for cross-platform compatibility)

/// Protocol for HealthKit integration. Available on all platforms for compilation compatibility.
public protocol HealthKitServiceProtocol: Sendable {
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

    /// Start an active workout session (used on watchOS)
    func startWorkoutSession() async throws

    /// End an active workout session (used on watchOS)
    func endWorkoutSession(_ workout: Workout) async throws
}

// MARK: - Data Models

/// Summary of a HealthKit workout
public struct HealthKitWorkoutSummary: Sendable, Identifiable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let totalEnergyBurned: Double? // kcal
    public let duration: TimeInterval

    public init(id: UUID, startDate: Date, endDate: Date, totalEnergyBurned: Double?, duration: TimeInterval) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.totalEnergyBurned = totalEnergyBurned
        self.duration = duration
    }
}

// MARK: - Platform-Specific Implementation

#if canImport(HealthKit)
import HealthKit

/// Default HealthKit service implementation for platforms that support HealthKit
public final class DefaultHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    private let healthStore = HKHealthStore()

    public init() {}

    public func requestAuthorization() async throws {
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

    public func isAuthorized() -> Bool {
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
    }

    public func saveWorkout(_ workout: Workout) async throws {
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

    public func startWorkoutSession() async throws {
        // Workout sessions on watchOS are managed by WatchHealthKitManager
    }

    public func endWorkoutSession(_ workout: Workout) async throws {
        // Workout sessions on watchOS are managed by WatchHealthKitManager
    }

    public func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] {
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
public final class DefaultHealthKitService: HealthKitServiceProtocol {
    public init() {}

    public func requestAuthorization() async throws {}

    public func isAuthorized() -> Bool {
        false
    }

    public func saveWorkout(_ workout: Workout) async throws {}

    public func startWorkoutSession() async throws {}

    public func endWorkoutSession(_ workout: Workout) async throws {}

    public func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] {
        []
    }
}
#endif

// MARK: - No-Op Implementation

/// No-op implementation for testing or when HealthKit is disabled
public final class NoOpHealthKitService: HealthKitServiceProtocol {
    public init() {}

    public func requestAuthorization() async throws {}

    public func isAuthorized() -> Bool {
        false
    }

    public func saveWorkout(_ workout: Workout) async throws {}

    public func startWorkoutSession() async throws {}

    public func endWorkoutSession(_ workout: Workout) async throws {}

    public func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] {
        []
    }
}
