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
    public var onTemplatesReceived: (([WorkoutTemplate]) -> Void)?

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

    /// Sync exercise library to Watch (iPhone -> Watch via applicationContext)
    public func syncExercises(_ exercises: [Exercise]) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
            let data = try encoder.encode(exercises)
            var context = WCSession.default.applicationContext
            context["exerciseSync"] = [
                "type": SyncMessageType.exerciseSync.rawValue,
                "timestamp": Date().timeIntervalSince1970,
                "payload": data.base64EncodedString()
            ] as [String: Any]
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("ConnectivityManager: Failed to sync exercises - \(error)")
        }
        #endif
    }

    /// Sync templates to Watch (iPhone -> Watch via applicationContext)
    public func syncTemplates(_ templates: [WorkoutTemplate]) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
            let data = try encoder.encode(templates)
            var context = WCSession.default.applicationContext
            context["templateSync"] = [
                "type": SyncMessageType.templateSync.rawValue,
                "timestamp": Date().timeIntervalSince1970,
                "payload": data.base64EncodedString()
            ] as [String: Any]
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("ConnectivityManager: Failed to sync templates - \(error)")
        }
        #endif
    }

    /// Send completed workout to iPhone (Watch -> iPhone via transferUserInfo)
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

    /// Send real-time set update (Watch -> iPhone via sendMessage)
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

    /// Sync settings to Watch (iPhone -> Watch)
    public func syncSettings(_ settings: [String: Any]) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
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
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
        }
    }

    // iOS only
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
        }
    }

    // Receive applicationContext (multi-key: exerciseSync, templateSync, settings)
    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let decoder = JSONDecoder()

        // Extract data on the calling thread to avoid sending non-Sendable dict across isolation
        var exerciseData: Data?
        if let exerciseDict = applicationContext["exerciseSync"] as? [String: Any],
           let payloadStr = exerciseDict["payload"] as? String {
            exerciseData = Data(base64Encoded: payloadStr)
        }

        var templateData: Data?
        if let templateDict = applicationContext["templateSync"] as? [String: Any],
           let payloadStr = templateDict["payload"] as? String {
            templateData = Data(base64Encoded: payloadStr)
        }

        var settingsData: Data?
        if let settings = applicationContext["settings"] {
            settingsData = try? JSONSerialization.data(withJSONObject: settings)
        }

        Task { @MainActor in
            self.lastSyncDate = Date()

            if let data = exerciseData,
               let exercises = try? decoder.decode([Exercise].self, from: data) {
                self.onExercisesReceived?(exercises)
            }

            if let data = templateData,
               let templates = try? decoder.decode([WorkoutTemplate].self, from: data) {
                self.onTemplatesReceived?(templates)
            }

            if let data = settingsData,
               let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.onSettingsReceived?(settings)
            }
        }
    }

    // Receive transferUserInfo (completed workouts)
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
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
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
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
