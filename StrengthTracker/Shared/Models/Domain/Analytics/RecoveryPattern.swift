import Foundation

/// Analysis of optimal recovery time between muscle group training sessions.
public struct RecoveryPattern: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let muscleGroup: String
    public let averageRecoveryHours: Double
    public let optimalRestDays: Int
    public let lastTrainedDate: Date?
    public let readyToTrainDate: Date?
    public let recoveryStatus: RecoveryStatus

    public init(
        id: UUID = UUID(),
        muscleGroup: String,
        averageRecoveryHours: Double,
        optimalRestDays: Int,
        lastTrainedDate: Date?,
        readyToTrainDate: Date?,
        recoveryStatus: RecoveryStatus = .ready
    ) {
        self.id = id
        self.muscleGroup = muscleGroup
        self.averageRecoveryHours = averageRecoveryHours
        self.optimalRestDays = optimalRestDays
        self.lastTrainedDate = lastTrainedDate
        self.readyToTrainDate = readyToTrainDate
        self.recoveryStatus = recoveryStatus
    }

    /// Trained within the last 36 hours. A just-trained group is trivially
    /// "fatigued"; only groups that stay fatigued past that window indicate a
    /// recovery problem.
    public func isJustTrained(asOf now: Date = Date()) -> Bool {
        guard let last = lastTrainedDate else { return false }
        return now.timeIntervalSince(last) < 36 * 3600
    }

    public var isJustTrained: Bool { isJustTrained() }
}

/// Recovery readiness status for a muscle group.
public enum RecoveryStatus: String, Codable, Sendable {
    case ready       // >= 100% recovered
    case recovering  // >= 70% recovered
    case fatigued    // < 70% recovered
}
