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

    // Callbacks for received data
    public var onExercisesReceived: (([Exercise]) -> Void)?
    public var onWorkoutReceived: ((Workout, [String: String]?) -> Void)?
    public var onSettingsReceived: (([String: Any]) -> Void)?
    public var onTemplatesReceived: (([WorkoutTemplate]) -> Void)?
    public var onPlannedSessionsReceived: (([PlannedSessionSync]) -> Void)?
    public var onWatchWorkoutSnapshot: ((Workout) -> Void)?
    public var onWatchWorkoutStarted: ((Workout) -> Void)?
    public var onWatchWorkoutEnded: (() -> Void)?
    public var onWatchRestTimerStarted: ((String, Int, Int) -> Void)?  // (exerciseName, setNumber, durationSeconds)
    public var onWatchRestTimerStopped: (() -> Void)?

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

    /// Sync planned sessions to Watch (iPhone -> Watch via applicationContext)
    public func syncPlannedSessions(_ sessions: [PlannedSessionSync]) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
            let data = try encoder.encode(sessions)
            var context = WCSession.default.applicationContext
            context["plannedSessionSync"] = [
                "type": SyncMessageType.plannedSessionSync.rawValue,
                "timestamp": Date().timeIntervalSince1970,
                "payload": data.base64EncodedString()
            ] as [String: Any]
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("ConnectivityManager: Failed to sync planned sessions - \(error)")
        }
        #endif
    }

    /// Send completed workout to iPhone (Watch -> iPhone via transferUserInfo)
    public func sendWorkoutCompleted(_ workout: Workout, metadata: [String: String]? = nil) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.activationState == .activated else { return }

        do {
            let data = try encoder.encode(workout)
            let message = SyncMessage(type: .workoutCompleted, payload: data, metadata: metadata)
            WCSession.default.transferUserInfo(message.asDictionary)
        } catch {
            print("ConnectivityManager: Failed to send workout - \(error)")
        }
        #endif
    }

    /// Send live workout snapshot to iPhone (Watch -> iPhone via sendMessage)
    public func sendWorkoutSnapshot(_ workout: Workout) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.isReachable else { return }

        do {
            let data = try encoder.encode(workout)
            let message: [String: Any] = [
                "type": SyncMessageType.workoutInProgress.rawValue,
                "payload": data.base64EncodedString()
            ]
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("ConnectivityManager: sendWorkoutSnapshot failed - \(error)")
            }
        } catch {
            print("ConnectivityManager: Failed to encode workout snapshot - \(error)")
        }
        #endif
    }

    /// Notify iPhone that a Watch workout has started
    public func sendWorkoutStarted(_ workout: Workout) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.isReachable else { return }

        do {
            let data = try encoder.encode(workout)
            let message: [String: Any] = [
                "type": "workoutStarted",
                "payload": data.base64EncodedString()
            ]
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("ConnectivityManager: sendWorkoutStarted failed - \(error)")
            }
        } catch {
            print("ConnectivityManager: Failed to encode workout start - \(error)")
        }
        #endif
    }

    /// Notify iPhone that the Watch rest timer started
    public func sendRestTimerStarted(exerciseName: String, setNumber: Int, duration: Int) {
        #if canImport(WatchConnectivity)
        guard WCSession.default.isReachable else { return }

        let message: [String: Any] = [
            "type": "restTimerStarted",
            "exerciseName": exerciseName,
            "setNumber": setNumber,
            "duration": duration
        ]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("ConnectivityManager: sendRestTimerStarted failed - \(error)")
        }
        #endif
    }

    /// Notify iPhone that the Watch rest timer stopped
    public func sendRestTimerStopped() {
        #if canImport(WatchConnectivity)
        // Fast path: immediate delivery (if reachable)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["type": "restTimerStopped"], replyHandler: nil) { error in
                print("ConnectivityManager: sendRestTimerStopped sendMessage failed - \(error)")
            }
        }
        // Guaranteed-delivery backup (queued even when unreachable)
        WCSession.default.transferUserInfo(["type": "restTimerStopped"])
        #endif
    }

    /// Notify iPhone that a Watch workout has ended
    public func sendWorkoutEnded() {
        #if canImport(WatchConnectivity)
        guard WCSession.default.isReachable else { return }

        let message: [String: Any] = [
            "type": "workoutEnded"
        ]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("ConnectivityManager: sendWorkoutEnded failed - \(error)")
        }
        #endif
    }

    /// Process received application context (used both by delegate and on-launch catch-up)
    public func processReceivedContext(_ applicationContext: [String: Any]) {
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

        var plannedSessionData: Data?
        if let dict = applicationContext["plannedSessionSync"] as? [String: Any],
           let payloadStr = dict["payload"] as? String {
            plannedSessionData = Data(base64Encoded: payloadStr)
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

            if let data = plannedSessionData,
               let sessions = try? decoder.decode([PlannedSessionSync].self, from: data) {
                self.onPlannedSessionsReceived?(sessions)
            }
        }
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

    // Receive applicationContext (multi-key: exerciseSync, templateSync, settings, plannedSessionSync)
    // Delegates to processReceivedContext — extracts Sendable data before crossing isolation boundary.
    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let decoder = JSONDecoder()

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

        var plannedSessionData: Data?
        if let dict = applicationContext["plannedSessionSync"] as? [String: Any],
           let payloadStr = dict["payload"] as? String {
            plannedSessionData = Data(base64Encoded: payloadStr)
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

            if let data = plannedSessionData,
               let sessions = try? decoder.decode([PlannedSessionSync].self, from: data) {
                self.onPlannedSessionsReceived?(sessions)
            }
        }
    }

    // Receive transferUserInfo (completed workouts + rest timer stop)
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Handle plain-dictionary rest timer stop (sent via transferUserInfo backup)
        if let type = userInfo["type"] as? String, type == "restTimerStopped" {
            Task { @MainActor in self.onWatchRestTimerStopped?() }
            return
        }

        guard let message = SyncMessage.from(dictionary: userInfo) else { return }
        let decoder = JSONDecoder()
        let metadata = message.metadata

        Task { @MainActor in
            self.lastSyncDate = Date()

            if message.type == .workoutCompleted,
               let workout = try? decoder.decode(Workout.self, from: message.payload) {
                self.onWorkoutReceived?(workout, metadata)
            }
        }
    }

    // Receive real-time messages (workout snapshots, started, ended)
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let typeStr = message["type"] as? String
        let decoder = JSONDecoder()

        var workout: Workout?
        if let payloadStr = message["payload"] as? String,
           let data = Data(base64Encoded: payloadStr) {
            workout = try? decoder.decode(Workout.self, from: data)
        }

        // Rest timer fields (for restTimerStarted messages)
        let exerciseName = message["exerciseName"] as? String
        let setNumber = message["setNumber"] as? Int
        let duration = message["duration"] as? Int

        Task { @MainActor in
            self.lastSyncDate = Date()

            switch typeStr {
            case SyncMessageType.workoutInProgress.rawValue:
                if let workout { self.onWatchWorkoutSnapshot?(workout) }
            case "workoutStarted":
                if let workout { self.onWatchWorkoutStarted?(workout) }
            case "workoutEnded":
                self.onWatchWorkoutEnded?()
            case "restTimerStarted":
                if let name = exerciseName, let setNum = setNumber, let dur = duration {
                    self.onWatchRestTimerStarted?(name, setNum, dur)
                }
            case "restTimerStopped":
                self.onWatchRestTimerStopped?()
            default:
                break
            }
        }
    }
}
#else
// Stub conformance for Linux builds
extension ConnectivityManager {
    func session(activationDidCompleteWith activationState: Int, error: Error?) {}
}
#endif
