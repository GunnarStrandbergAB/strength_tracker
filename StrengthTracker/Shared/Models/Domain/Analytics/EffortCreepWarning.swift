import Foundation

/// Warning when RPE is trending upward while strength is flat or declining.
public struct EffortCreepWarning: Sendable {
    public let exerciseName: String
    public let rpeIncrease: Double      // e.g., 7.0 → 8.5 over 3 sessions
    public let sessionsTracked: Int
    public let message: String

    public init(exerciseName: String, rpeIncrease: Double, sessionsTracked: Int, message: String) {
        self.exerciseName = exerciseName
        self.rpeIncrease = rpeIncrease
        self.sessionsTracked = sessionsTracked
        self.message = message
    }
}
