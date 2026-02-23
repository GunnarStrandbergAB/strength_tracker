import Foundation
import Observation

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
@Observable
public final class RestTimerService {
    public var remainingSeconds: Int = 0
    public var isRunning: Bool = false
    public var totalSeconds: Int = UserPreferencesService.defaultRestSecondsValue

    public init() {}

    nonisolated(unsafe) private var timer: Timer?
    private var startDate: Date?

    #if canImport(ActivityKit)
    private var currentActivity: Activity<RestTimerAttributes>?
    #endif

    // Live Activity context (stored when activity starts)
    private var currentExerciseName: String?
    private var currentSetNumber: Int?

    /// Start the rest timer
    /// - Parameters:
    ///   - seconds: Optional duration in seconds. If nil, uses the current totalSeconds value
    ///   - exerciseName: Name of the exercise for Live Activity
    ///   - setNumber: Set number for Live Activity
    public func start(seconds: Int? = nil, exerciseName: String? = nil, setNumber: Int? = nil) {
        stop() // Stop any existing timer

        if let seconds = seconds {
            totalSeconds = seconds
        }

        remainingSeconds = totalSeconds
        startDate = Date()
        isRunning = true

        // Store Live Activity context
        currentExerciseName = exerciseName
        currentSetNumber = setNumber

        // Start Live Activity if context is provided
        if let exerciseName = exerciseName, let setNumber = setNumber {
            startLiveActivity(exerciseName: exerciseName, setNumber: setNumber)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startDate = self.startDate else { return }

                let elapsed = Int(Date().timeIntervalSince(startDate))
                let remaining = max(0, self.totalSeconds - elapsed)
                self.remainingSeconds = remaining

                if remaining > 0 {
                    self.updateLiveActivity()
                } else {
                    self.timerCompleted()
                }
            }
        }
    }

    /// Stop the timer without resetting values
    public func stop() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        isRunning = false
        endLiveActivity()
    }

    /// Reset the timer to initial state
    public func reset() {
        stop()
        remainingSeconds = totalSeconds
    }

    /// Progress from 0.0 (start) to 1.0 (complete)
    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    /// Formatted time remaining as MM:SS
    public var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Check if timer has completed
    public var isCompleted: Bool {
        remainingSeconds == 0 && !isRunning
    }

    private func timerCompleted() {
        endLiveActivity()
        stop()
        triggerCompletionFeedback()
    }

    private func triggerCompletionFeedback() {
        // Haptic feedback handled by the view layer
    }

    // MARK: - Live Activity Management

    /// Start a Live Activity for the rest timer
    /// - Parameters:
    ///   - exerciseName: Name of the exercise
    ///   - setNumber: Set number
    private func startLiveActivity(exerciseName: String, setNumber: Int) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = RestTimerAttributes(
            exerciseName: exerciseName,
            setNumber: setNumber
        )
        let state = RestTimerAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            isRunning: true
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            print("RestTimerService: Failed to start Live Activity - \(error)")
        }
        #endif
    }

    /// Update the Live Activity with current state
    private func updateLiveActivity() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        let state = RestTimerAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            isRunning: isRunning
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    /// End the Live Activity
    private func endLiveActivity() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        let finalState = RestTimerAttributes.ContentState(
            remainingSeconds: 0,
            totalSeconds: totalSeconds,
            isRunning: false
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
        #endif
    }

    deinit {
        timer?.invalidate()
    }
}
