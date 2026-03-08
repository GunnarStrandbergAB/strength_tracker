import Foundation
import Observation

#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
import AudioToolbox
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
@Observable
public final class RestTimerService {
    public var remainingSeconds: Int = 0
    public var isRunning: Bool = false
    public var totalSeconds: Int = UserPreferencesService.defaultRestSecondsValue

    /// The date when the current timer will (or did) expire. Used for Live Activity timerInterval and notifications.
    public var endDate: Date?

    public init() {}

    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var mirrorEndTimer: Timer?
    private var startDate: Date?

    #if canImport(ActivityKit)
    private var currentActivity: Activity<RestTimerAttributes>?
    #endif

    // Live Activity context (stored when activity starts)
    private var currentExerciseName: String?
    private var currentSetNumber: Int?

    /// Start the rest timer from full duration
    /// - Parameters:
    ///   - seconds: Optional duration in seconds. If nil, uses the current totalSeconds value
    ///   - exerciseName: Name of the exercise for Live Activity
    ///   - setNumber: Set number for Live Activity
    public func start(seconds: Int? = nil, exerciseName: String? = nil, setNumber: Int? = nil) {
        stop() // Stop any existing timer

        if let seconds = seconds {
            totalSeconds = seconds
        }

        // Store Live Activity context
        if let exerciseName { currentExerciseName = exerciseName }
        if let setNumber { currentSetNumber = setNumber }

        remainingSeconds = totalSeconds
        startDate = Date()
        endDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        isRunning = true

        scheduleNotification(seconds: totalSeconds, exerciseName: currentExerciseName)

        // Start Live Activity if context is provided
        if let name = currentExerciseName, let setNum = currentSetNumber {
            startLiveActivity(exerciseName: name, setNumber: setNum)
        }

        startTicker()
    }

    /// Resume the timer from the current remainingSeconds (for un-pause)
    public func resume() {
        guard !isRunning, remainingSeconds > 0 else { return }
        startDate = Date()
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true

        scheduleNotification(seconds: remainingSeconds, exerciseName: currentExerciseName)

        // Update Live Activity with new date range
        resumeOrStartLiveActivity()

        startTicker()
    }

    /// Pause the timer without resetting values
    public func pause() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        endDate = nil
        isRunning = false
        cancelNotification()
        updateLiveActivity()
    }

    /// Stop the timer completely and reset
    public func stop() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        endDate = nil
        isRunning = false
        remainingSeconds = 0
        cancelNotification()
        endLiveActivity()
    }

    /// Reset the timer to initial state
    public func reset() {
        stop()
        remainingSeconds = totalSeconds
    }

    /// Add extra time to a running or paused timer
    public func addTime(seconds: Int) {
        remainingSeconds += seconds
        totalSeconds += seconds
        if let end = endDate {
            endDate = end.addingTimeInterval(TimeInterval(seconds))
        }
        if isRunning {
            // Reschedule notification with new remaining time
            cancelNotification()
            scheduleNotification(seconds: remainingSeconds, exerciseName: currentExerciseName)
            updateLiveActivity()
        }
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

    /// Called when the app returns to foreground — check if timer expired while backgrounded
    public func handleForegroundReturn() {
        guard isRunning, let endDate = endDate else { return }
        if Date() >= endDate {
            remainingSeconds = 0
            if startDate == nil {
                // Mirror mode (watch timer): just end activity, no feedback
                endLiveActivityOnly()
            } else {
                // Local mode: normal completion with feedback
                timerCompleted()
            }
        } else {
            // Timer still running — resync remainingSeconds
            remainingSeconds = max(0, Int(endDate.timeIntervalSinceNow))
        }
    }

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startDate = self.startDate else { return }

                let elapsed = Int(Date().timeIntervalSince(startDate))
                let remaining = max(0, self.totalSeconds - elapsed)
                self.remainingSeconds = remaining

                if remaining <= 0 {
                    self.timerCompleted()
                }
                // Note: No per-second Live Activity update — the system renders the countdown via timerInterval
            }
        }
    }

    private func timerCompleted() {
        mirrorEndTimer?.invalidate()
        mirrorEndTimer = nil
        endLiveActivity()
        timer?.invalidate()
        timer = nil
        startDate = nil
        endDate = nil
        isRunning = false
        remainingSeconds = 0
        triggerCompletionFeedback()
        // Notification already scheduled and will fire on its own
    }

    private func triggerCompletionFeedback() {
        #if os(iOS)
        AudioServicesPlayAlertSound(1007) // tri-tone system sound
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    // MARK: - Notifications

    private func scheduleNotification(seconds: Int, exerciseName: String?) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Rest Complete"
        content.body = exerciseName.map { "Time for your next set of \($0)" } ?? "Time for your next set"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, TimeInterval(seconds)), repeats: false)
        let request = UNNotificationRequest(identifier: "rest-timer", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    private func cancelNotification() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest-timer"])
        #endif
    }

    // MARK: - Live Activity Management

    /// Resume existing Live Activity or start a new one
    private func resumeOrStartLiveActivity() {
        #if canImport(ActivityKit)
        if currentActivity != nil {
            updateLiveActivity()
        } else if let name = currentExerciseName, let setNum = currentSetNumber {
            startLiveActivity(exerciseName: name, setNumber: setNum)
        }
        #endif
    }

    /// Start a Live Activity for the rest timer
    private func startLiveActivity(exerciseName: String, setNumber: Int) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let endDate = endDate else { return }

        let attributes = RestTimerAttributes(
            exerciseName: exerciseName,
            setNumber: setNumber
        )
        let now = Date()
        let state = RestTimerAttributes.ContentState(
            timerRange: now...endDate,
            totalSeconds: totalSeconds,
            isRunning: true
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: endDate)
            )
        } catch {
            print("RestTimerService: Failed to start Live Activity - \(error)")
        }
        #endif
    }

    /// Update the Live Activity with current state (only on pause/resume/add-time, NOT per-second)
    private func updateLiveActivity() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        let now = Date()
        let end = endDate ?? now
        let state = RestTimerAttributes.ContentState(
            timerRange: now...max(now, end),
            totalSeconds: totalSeconds,
            isRunning: isRunning
        )

        Task {
            await activity.update(.init(state: state, staleDate: isRunning ? end : nil))
        }
        #endif
    }

    /// End the Live Activity
    private func endLiveActivity() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        let now = Date()
        let finalState = RestTimerAttributes.ContentState(
            timerRange: now...now,
            totalSeconds: totalSeconds,
            isRunning: false
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
        #endif
    }

    // MARK: - Live Activity Only (for mirroring Watch rest timer on iPhone)

    /// Start ONLY a Live Activity — no internal Timer, no haptic, no notification.
    /// Used when the Watch sends a rest timer start message to the iPhone.
    public func startLiveActivityOnly(exerciseName: String, setNumber: Int, duration: Int) {
        endLiveActivity()
        mirrorEndTimer?.invalidate()

        totalSeconds = duration
        endDate = Date().addingTimeInterval(TimeInterval(duration))
        currentExerciseName = exerciseName
        currentSetNumber = setNumber
        isRunning = true
        remainingSeconds = duration

        startLiveActivity(exerciseName: exerciseName, setNumber: setNumber)

        // Layer 3: iPhone notification (fires via OS even when suspended)
        scheduleNotification(seconds: duration, exerciseName: exerciseName)

        // Layer 2: Safety-net timer ends activity if watch stop message never arrives
        // +2s buffer so the real message has priority; fires immediately on app wake if overdue
        mirrorEndTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(duration) + 2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.endLiveActivityOnly() }
        }
    }

    /// End any Live Activities left over from a previous launch (currentActivity is nil but system activity persists)
    public func endAllStaleActivities() {
        #if canImport(ActivityKit)
        for activity in Activity<RestTimerAttributes>.activities {
            let now = Date()
            let finalState = RestTimerAttributes.ContentState(
                timerRange: now...now,
                totalSeconds: 0,
                isRunning: false
            )
            Task {
                await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        #endif
    }

    /// End ONLY the Live Activity (no timer/notification cleanup needed).
    /// Used when the Watch sends a rest timer stop message to the iPhone.
    public func endLiveActivityOnly() {
        mirrorEndTimer?.invalidate()
        mirrorEndTimer = nil
        cancelNotification()
        endLiveActivity()
        isRunning = false
        remainingSeconds = 0
        endDate = nil
    }

    deinit {
        timer?.invalidate()
        mirrorEndTimer?.invalidate()
    }
}
