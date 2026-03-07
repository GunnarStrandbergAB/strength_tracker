#if canImport(ActivityKit)
import ActivityKit
import Foundation

public struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var timerRange: ClosedRange<Date>
        public var totalSeconds: Int
        public var isRunning: Bool

        public var progress: Double {
            guard totalSeconds > 0 else { return 0 }
            let total = TimeInterval(totalSeconds)
            let remaining = max(0, timerRange.upperBound.timeIntervalSinceNow)
            return 1.0 - (remaining / total)
        }

        public var formattedTime: String {
            let remaining = max(0, Int(timerRange.upperBound.timeIntervalSinceNow))
            let minutes = remaining / 60
            let seconds = remaining % 60
            if minutes > 0 {
                return String(format: "%d:%02d", minutes, seconds)
            }
            return "\(seconds)s"
        }

        public init(timerRange: ClosedRange<Date>, totalSeconds: Int, isRunning: Bool) {
            self.timerRange = timerRange
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
