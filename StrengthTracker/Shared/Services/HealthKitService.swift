import Foundation

// MARK: - Protocol (always available for cross-platform compatibility)

/// Protocol for HealthKit integration. Available on all platforms for compilation compatibility.
public protocol HealthKitServiceProtocol: Sendable {
    /// Request authorization to read and write health data
    func requestAuthorization() async throws

    /// Save a completed workout with custom calorie estimation
    /// - Parameters:
    ///   - workout: The workout to save
    ///   - calories: Estimated total calories burned
    ///   - bodyWeightKg: Body weight for effective-load volume metadata
    func saveWorkout(_ workout: Workout, calories: Double, bodyWeightKg: Double) async throws

    /// Fetch the user's latest body weight from HealthKit
    func fetchBodyWeightKg() async -> Double?

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
    func discardWorkoutSession() async
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

    public func saveWorkout(_ workout: Workout, calories: Double, bodyWeightKg: Double) async throws {
        guard let endDate = workout.completedAt else { return }
        let startDate = workout.startedAt
        let totalDuration = endDate.timeIntervalSince(startDate)

        var metadata: [String: Any] = [
            "StrengthTrackerWorkoutId": workout.id.uuidString,
            "WorkoutName": workout.name,
            "TotalVolume": workout.totalVolume(bodyWeightKg: bodyWeightKg),
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
        // On iOS the completion pipeline saves the workout with calories and the
        // resolved body weight; nothing to do here.
    }

}
#endif

// MARK: - Non-HealthKit Platform Implementation

#if !canImport(HealthKit)
/// Fallback implementation for platforms without HealthKit support
public final class DefaultHealthKitService: HealthKitServiceProtocol {
    public init() {}

    public func requestAuthorization() async throws {}
    public func saveWorkout(_ workout: Workout, calories: Double, bodyWeightKg: Double) async throws {}
    public func fetchBodyWeightKg() async -> Double? { nil }
    public func startWorkoutSession() async throws {}
    public func endWorkoutSession(_ workout: Workout) async throws {}
}
#endif

// MARK: - No-Op Implementation

/// No-op implementation for testing or when HealthKit is disabled
public final class NoOpHealthKitService: HealthKitServiceProtocol {
    public init() {}

    public func requestAuthorization() async throws {}
    public func saveWorkout(_ workout: Workout) async throws {}
    public func saveWorkout(_ workout: Workout, calories: Double, bodyWeightKg: Double) async throws {}
    public func fetchBodyWeightKg() async -> Double? { nil }
    public func startWorkoutSession() async throws {}
    public func endWorkoutSession(_ workout: Workout) async throws {}
}
