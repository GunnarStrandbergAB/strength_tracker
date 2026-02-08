#if canImport(ActivityKit)
import ActivityKit
import Foundation

public struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var remainingSeconds: Int
        public var totalSeconds: Int
        public var isRunning: Bool

        public var progress: Double {
            guard totalSeconds > 0 else { return 0 }
            return 1.0 - (Double(remainingSeconds) / Double(totalSeconds))
        }

        public var formattedTime: String {
            let minutes = remainingSeconds / 60
            let seconds = remainingSeconds % 60
            if minutes > 0 {
                return String(format: "%d:%02d", minutes, seconds)
            }
            return "\(seconds)s"
        }

        public init(remainingSeconds: Int, totalSeconds: Int, isRunning: Bool) {
            self.remainingSeconds = remainingSeconds
            self.totalSeconds = totalSeconds
            self.isRunning = isRunning
        }
    }

    // Fixed properties (set when activity starts)
    public var exerciseName: String
    public var setNumber: Int

    public init(exerciseName: String, setNumber: Int) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
    }
}
#endif
