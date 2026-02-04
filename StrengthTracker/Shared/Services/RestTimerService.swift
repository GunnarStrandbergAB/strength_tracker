import Foundation
import Observation

@MainActor
@Observable
final class RestTimerService {
    var remainingSeconds: Int = 0
    var isRunning: Bool = false
    var totalSeconds: Int = 90  // default rest time

    nonisolated(unsafe) private var timer: Timer?

    /// Start the rest timer
    /// - Parameter seconds: Optional duration in seconds. If nil, uses the current totalSeconds value
    func start(seconds: Int? = nil) {
        stop() // Stop any existing timer

        if let seconds = seconds {
            totalSeconds = seconds
        }

        remainingSeconds = totalSeconds
        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                } else {
                    self.timerCompleted()
                }
            }
        }
    }

    /// Stop the timer without resetting values
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Reset the timer to initial state
    func reset() {
        stop()
        remainingSeconds = totalSeconds
    }

    /// Progress from 0.0 (start) to 1.0 (complete)
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    /// Formatted time remaining as MM:SS
    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Check if timer has completed
    var isCompleted: Bool {
        remainingSeconds == 0 && !isRunning
    }

    private func timerCompleted() {
        stop()
        triggerCompletionFeedback()
    }

    private func triggerCompletionFeedback() {
        // Haptic feedback handled by the view layer
    }

    deinit {
        timer?.invalidate()
    }
}
