#if canImport(HealthKit) && os(watchOS)
import Foundation
import HealthKit
import Observation
import StrengthTrackerShared

@Observable
@MainActor
public final class WatchHealthKitManager: NSObject, WatchWorkoutSessionManager, @unchecked Sendable {
    public var heartRate: Double = 0
    public var activeCalories: Double = 0
    public var elapsedTime: TimeInterval = 0
    public var isSessionActive: Bool = false
    /// UUID of the last finished HKWorkout (sent to iPhone for calorie association)
    public var finishedWorkoutUUID: UUID?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    public override init() {
        super.init()
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HealthKit] Health data not available on this device")
            return
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        print("[HealthKit] Authorization requested successfully")
    }

    public func startWorkoutSession() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HealthKit] Cannot start session — health data not available")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()

        let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        builder.dataSource = dataSource

        session.delegate = self
        builder.delegate = self

        self.workoutSession = session
        self.workoutBuilder = builder
        self.finishedWorkoutUUID = nil

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())

        isSessionActive = true
        print("[HealthKit] Workout session started successfully")
    }

    public func endWorkoutSession() async throws {
        guard let session = workoutSession, let builder = workoutBuilder else { return }

        session.end()
        try await builder.endCollection(at: Date())
        let finishedWorkout = try await builder.finishWorkout()

        // Capture the HKWorkout UUID so iPhone can attach calorie data to it
        finishedWorkoutUUID = finishedWorkout?.uuid
        print("[HealthKit] Workout session ended, HKWorkout UUID: \(finishedWorkout?.uuid.uuidString ?? "nil")")

        isSessionActive = false
        workoutSession = nil
        workoutBuilder = nil
    }

    public func discardWorkoutSession() async {
        workoutSession?.end()
        workoutSession = nil
        workoutBuilder = nil
        finishedWorkoutUUID = nil
        isSessionActive = false
        print("[HealthKit] Workout session discarded (not saved to Apple Health)")
    }

    /// Recover an orphaned HealthKit workout session (e.g. after crash or app termination)
    public func recoverOrphanedSession() async {
        do {
            // Available watchOS 10+
            guard let session = try await healthStore.recoverActiveWorkoutSession() else {
                return
            }
            let builder = session.associatedWorkoutBuilder()

            let configuration = session.workoutConfiguration
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder
            self.isSessionActive = true
        } catch {
            // No orphaned session to recover — this is expected in normal operation
        }
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WatchHealthKitManager: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("[HealthKit] Session state: \(fromState.rawValue) → \(toState.rawValue)")
        Task { @MainActor in
            isSessionActive = (toState == .running)
        }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HealthKit] Session failed: \(error)")
        Task { @MainActor in
            isSessionActive = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WatchHealthKitManager: HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }

    nonisolated public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            let statistics = workoutBuilder.statistics(for: quantityType)

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                    self.heartRate = statistics?.mostRecentQuantity()?.doubleValue(for: heartRateUnit) ?? 0

                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    let energyUnit = HKUnit.kilocalorie()
                    self.activeCalories = statistics?.sumQuantity()?.doubleValue(for: energyUnit) ?? 0

                default:
                    break
                }

                self.elapsedTime = workoutBuilder.elapsedTime
            }
        }
    }
}
#endif
