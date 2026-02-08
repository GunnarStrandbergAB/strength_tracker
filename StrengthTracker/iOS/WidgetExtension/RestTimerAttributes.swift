#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var remainingSeconds: Int
        var totalSeconds: Int
        var isRunning: Bool

        var progress: Double {
            guard totalSeconds > 0 else { return 0 }
            return 1.0 - (Double(remainingSeconds) / Double(totalSeconds))
        }

        var formattedTime: String {
            let minutes = remainingSeconds / 60
            let seconds = remainingSeconds % 60
            if minutes > 0 {
                return String(format: "%d:%02d", minutes, seconds)
            }
            return "\(seconds)s"
        }
    }

    // Fixed properties (set when activity starts)
    var exerciseName: String
    var setNumber: Int
}
#endif
