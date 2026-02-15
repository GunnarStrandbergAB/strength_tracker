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

    /// Save a completed workout with custom calorie estimation
    /// - Parameters:
    ///   - workout: The workout to save
    ///   - calories: Estimated total calories burned
    func saveWorkout(_ workout: Workout, calories: Double) async throws

    /// Add calorie data to an existing HealthKit workout (Watch-originated)
    /// - Parameters:
    ///   - healthKitWorkoutId: UUID of the existing HKWorkout from Apple Watch
    ///   - calories: Estimated calories to attach
    ///   - workout: The workout data (for date range)
    func addCaloriesToExistingWorkout(healthKitWorkoutId: UUID, calories: Double, workout: Workout) async throws

    /// Fetch the user's latest body weight from HealthKit
    func fetchBodyWeightKg() async -> Double?

    /// Fetch recent workouts from HealthKit
    /// - Parameter limit: Maximum number of workouts to fetch
    /// - Returns: Array of workout summaries
    func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary]

    /// Start an active workout session (used on watchOS)
    func startWorkoutSession() async throws

    /// End an active workout session (used on watchOS)
    func endWorkoutSession(_ workout: Workout) async throws
}

// MARK: - Watch Workout Session Protocol

/// Protocol for real-time Watch workout session management (heart rate, calories, etc.)
/// WatchHealthKitManager in the Watch target conforms to this.
@MainActor
public protocol WatchWorkoutSessionManager: AnyObject {
    var heartRate: Double { get }
    var activeCalories: Double { get }
    var elapsedTime: TimeInterval { get }
    var isSessionActive: Bool { get }
    /// UUID of the finished HKWorkout (available after endWorkoutSession)
    var finishedWorkoutUUID: UUID? { get }

    func requestAuthorization() async throws
    func startWorkoutSession() async throws
    func endWorkoutSession() async throws
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
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    public func isAuthorized() -> Bool {
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
    }

    public func saveWorkout(_ workout: Workout) async throws {
        try await saveWorkout(workout, calories: 0)
    }

    public func saveWorkout(_ workout: Workout, calories: Double) async throws {
        guard let endDate = workout.completedAt else { return }
        let startDate = workout.startedAt
        let totalDuration = endDate.timeIntervalSince(startDate)

        var metadata: [String: Any] = [
            "StrengthTrackerWorkoutId": workout.id.uuidString,
            "WorkoutName": workout.name,
            "TotalVolume": workout.totalVolume,
            "ExerciseCount": workout.exercises.count,
            "CalorieMethod": "StrengthTracker-v1"
        ]

        if let notes = workout.notes {
            metadata["Notes"] = notes
        }

        let energyBurned: HKQuantity? = calories > 0
            ? HKQuantity(unit: .kilocalorie(), doubleValue: calories)
            : nil

        let hkWorkout = HKWorkout(
            activityType: .traditionalStrengthTraining,
            start: startDate,
            end: endDate,
            duration: totalDuration,
            totalEnergyBurned: energyBurned,
            totalDistance: nil,
            metadata: metadata
        )

        try await healthStore.save(hkWorkout)

        // Associate an active energy burned sample so it counts toward the Move ring
        if calories > 0 {
            let energySample = HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: startDate,
                end: endDate
            )
            try await healthStore.addSamples([energySample], to: hkWorkout)
        }
    }

    public func addCaloriesToExistingWorkout(healthKitWorkoutId: UUID, calories: Double, workout: Workout) async throws {
        guard calories > 0, let endDate = workout.completedAt else { return }

        // Find the existing HKWorkout by UUID
        let predicate = HKQuery.predicateForObject(with: healthKitWorkoutId)
        let workoutType = HKObjectType.workoutType()

        let hkWorkout: HKWorkout? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }

        guard let existingWorkout = hkWorkout else {
            // Watch workout not yet synced to iPhone's HealthKit — fall back to creating new
            try await saveWorkout(workout, calories: calories)
            return
        }

        // Add calorie sample associated with the Watch's workout
        let energySample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
            start: workout.startedAt,
            end: endDate
        )
        try await healthStore.addSamples([energySample], to: existingWorkout)
    }

    public func fetchBodyWeightKg() async -> Double? {
        await withCheckedContinuation { continuation in
            let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                let kg = sample?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            healthStore.execute(query)
        }
    }

    public func startWorkoutSession() async throws {
        // No-op: on watchOS, workout sessions are managed by WatchHealthKitManager
        // On iOS, workout sessions are not needed (we only save completed workouts)
    }

    public func endWorkoutSession(_ workout: Workout) async throws {
        // On iOS, save the workout to HealthKit when it completes
        #if os(iOS)
        try await saveWorkout(workout)
        #endif
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
    public func isAuthorized() -> Bool { false }
    public func saveWorkout(_ workout: Workout) async throws {}
    public func saveWorkout(_ workout: Workout, calories: Double) async throws {}
    public func addCaloriesToExistingWorkout(healthKitWorkoutId: UUID, calories: Double, workout: Workout) async throws {}
    public func fetchBodyWeightKg() async -> Double? { nil }
    public func startWorkoutSession() async throws {}
    public func endWorkoutSession(_ workout: Workout) async throws {}
    public func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] { [] }
}
#endif

// MARK: - No-Op Implementation

/// No-op implementation for testing or when HealthKit is disabled
public final class NoOpHealthKitService: HealthKitServiceProtocol {
    public init() {}

    public func requestAuthorization() async throws {}
    public func isAuthorized() -> Bool { false }
    public func saveWorkout(_ workout: Workout) async throws {}
    public func saveWorkout(_ workout: Workout, calories: Double) async throws {}
    public func addCaloriesToExistingWorkout(healthKitWorkoutId: UUID, calories: Double, workout: Workout) async throws {}
    public func fetchBodyWeightKg() async -> Double? { nil }
    public func startWorkoutSession() async throws {}
    public func endWorkoutSession(_ workout: Workout) async throws {}
    public func fetchRecentWorkouts(limit: Int) async -> [HealthKitWorkoutSummary] { [] }
}
