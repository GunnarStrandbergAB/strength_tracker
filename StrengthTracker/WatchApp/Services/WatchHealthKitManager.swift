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

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    public override init() {
        super.init()
    }

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

    public func startWorkoutSession() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()

        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        session.delegate = self
        builder.delegate = self

        self.workoutSession = session
        self.workoutBuilder = builder

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())

        isSessionActive = true
    }

    public func endWorkoutSession() async throws {
        guard let session = workoutSession, let builder = workoutBuilder else { return }

        session.end()
        try await builder.endCollection(at: Date())
        try await builder.finishWorkout()

        isSessionActive = false
        workoutSession = nil
        workoutBuilder = nil
    }

    public func pauseWorkout() {
        workoutSession?.pause()
    }

    public func resumeWorkout() {
        workoutSession?.resume()
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
        Task { @MainActor in
            isSessionActive = (toState == .running)
        }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
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
