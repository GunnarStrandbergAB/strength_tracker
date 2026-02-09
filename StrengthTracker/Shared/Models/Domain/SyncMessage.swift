import Foundation

/// Messages exchanged between iPhone and Watch via WatchConnectivity
public enum SyncMessageType: String, Codable, Sendable {
    case exerciseSync       // iPhone → Watch: sync exercise library
    case templateSync       // iPhone → Watch: sync templates
    case settingsSync       // iPhone → Watch: sync user settings
    case workoutCompleted   // Watch → iPhone: completed workout
    case workoutInProgress  // Watch → iPhone: real-time set updates
}

public struct SyncMessage: Codable, Sendable {
    public static let currentVersion = 1

    public let type: SyncMessageType
    public let timestamp: Date
    public let payload: Data  // JSON-encoded payload specific to type
    public let version: Int

    public init(type: SyncMessageType, payload: Data) {
        self.type = type
        self.timestamp = Date()
        self.payload = payload
        self.version = Self.currentVersion
    }

    /// Convert to dictionary for WCSession transfer
    public var asDictionary: [String: Any] {
        [
            "type": type.rawValue,
            "timestamp": timestamp.timeIntervalSince1970,
            "payload": payload.base64EncodedString(),
            "version": version
        ]
    }

    /// Parse from WCSession dictionary
    public static func from(dictionary: [String: Any]) -> SyncMessage? {
        guard let typeStr = dictionary["type"] as? String,
              let type = SyncMessageType(rawValue: typeStr),
              let timestamp = dictionary["timestamp"] as? TimeInterval,
              let payloadStr = dictionary["payload"] as? String,
              let payload = Data(base64Encoded: payloadStr) else {
            return nil
        }
        let version = dictionary["version"] as? Int ?? 1
        return SyncMessage(type: type, timestamp: Date(timeIntervalSince1970: timestamp), payload: payload, version: version)
    }

    // Private init with all fields for reconstruction
    private init(type: SyncMessageType, timestamp: Date, payload: Data, version: Int) {
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
        self.version = version
    }
}
