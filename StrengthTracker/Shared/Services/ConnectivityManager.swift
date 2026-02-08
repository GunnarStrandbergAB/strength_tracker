import Foundation
import Observation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@Observable
@MainActor
public final class ConnectivityManager: NSObject, @unchecked Sendable {
    public var isReachable: Bool = false
    public var lastSyncDate: Date?
    public var pendingTransfers: Int = 0

    // Callbacks for received data
    public var onExercisesReceived: (([Exercise]) -> Void)?
    public var onWorkoutReceived: ((Workout) -> Void)?
    public var onSettingsReceived: (([String: Any]) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        super.init()
    }

    /// Activate WCSession - call from app entry point
    public func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    // MARK: - Send Methods

    /// Sync exercise library to Watch (iPhone → Watch via applicationContext)
    public func syncExercises(_ exercises: [Exercise]) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
            let data = try encoder.encode(exercises)
            let message = SyncMessage(type: .exerciseSync, payload: data)
            try WCSession.default.updateApplicationContext(message.asDictionary)
        } catch {
            print("ConnectivityManager: Failed to sync exercises - \(error)")
        }
        #endif
    }

    /// Send completed workout to iPhone (Watch → iPhone via transferUserInfo)
    public func sendWorkoutCompleted(_ workout: Workout) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
            let data = try encoder.encode(workout)
            let message = SyncMessage(type: .workoutCompleted, payload: data)
            WCSession.default.transferUserInfo(message.asDictionary)
            Task { @MainActor in
                self.pendingTransfers += 1
            }
        } catch {
            print("ConnectivityManager: Failed to send workout - \(error)")
        }
        #endif
    }

    /// Send real-time set update (Watch → iPhone via sendMessage)
    public func sendSetUpdate(exerciseId: UUID, setId: UUID, weight: Double?, reps: Int?, isCompleted: Bool) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.isReachable else { return }

        let update: [String: Any] = [
            "type": SyncMessageType.workoutInProgress.rawValue,
            "exerciseId": exerciseId.uuidString,
            "setId": setId.uuidString,
            "weight": weight as Any,
            "reps": reps as Any,
            "isCompleted": isCompleted
        ]

        WCSession.default.sendMessage(update, replyHandler: nil) { error in
            print("ConnectivityManager: sendMessage failed - \(error)")
        }
        #endif
    }

    /// Sync settings to Watch (iPhone → Watch)
    public func syncSettings(_ settings: [String: Any]) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
            // Merge with existing context
            var context = WCSession.default.applicationContext
            context["settings"] = settings
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("ConnectivityManager: Failed to sync settings - \(error)")
        }
        #endif
    }
}

// MARK: - WCSessionDelegate
#if canImport(WatchConnectivity)
extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // iOS only
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // Receive applicationContext (exercises, settings)
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = SyncMessage.from(dictionary: applicationContext) else { return }
        let decoder = JSONDecoder()

        Task { @MainActor in
            self.lastSyncDate = Date()

            switch message.type {
            case .exerciseSync:
                if let exercises = try? decoder.decode([Exercise].self, from: message.payload) {
                    self.onExercisesReceived?(exercises)
                }
            case .settingsSync:
                if let settings = try? JSONSerialization.jsonObject(with: message.payload) as? [String: Any] {
                    self.onSettingsReceived?(settings)
                }
            default:
                break
            }
        }
    }

    // Receive transferUserInfo (completed workouts)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = SyncMessage.from(dictionary: userInfo) else { return }
        let decoder = JSONDecoder()

        Task { @MainActor in
            self.lastSyncDate = Date()
            self.pendingTransfers = max(0, self.pendingTransfers - 1)

            if message.type == .workoutCompleted,
               let workout = try? decoder.decode(Workout.self, from: message.payload) {
                self.onWorkoutReceived?(workout)
            }
        }
    }

    // Receive real-time messages
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Handle real-time set updates on the receiving side
        Task { @MainActor in
            self.lastSyncDate = Date()
        }
    }
}
#else
// Stub conformance for Linux builds
extension ConnectivityManager {
    func session(activationDidCompleteWith activationState: Int, error: Error?) {}
}
#endif
