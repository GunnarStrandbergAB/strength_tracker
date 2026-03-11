#if canImport(ActivityKit)
import ActivityKit
#endif
import StrengthTrackerShared

/// Wires up ActivityKit Live Activity lifecycle on the WatchWorkoutViewModel.
/// This file lives in the WatchApp Xcode target (not SPM) so ActivityKit is importable.
enum WatchLiveActivityManager {

    #if canImport(ActivityKit)
    /// Shared reference so we can end the activity later.
    @MainActor private static var currentActivity: Activity<RestTimerAttributes>?
    #endif

    /// Call once after creating the view model to attach Live Activity handlers.
    @MainActor
    static func attach(to viewModel: WatchWorkoutViewModel) {
        #if canImport(ActivityKit)
        print("[WatchLiveActivityManager] attach(to:) — setting Live Activity closures")
        viewModel.onStartLiveActivity = { exerciseName, setNumber, duration in
            startActivity(exerciseName: exerciseName, setNumber: setNumber, duration: duration)
        }
        viewModel.onEndLiveActivity = {
            endActivity()
        }
        #else
        print("[WatchLiveActivityManager] attach(to:) — ActivityKit NOT available, closures NOT set")
        #endif
    }

    // MARK: - ActivityKit implementation

    #if canImport(ActivityKit)
    @MainActor
    private static func startActivity(exerciseName: String, setNumber: Int, duration: Int) {
        guard #available(watchOS 11.0, iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any previous activity first
        endActivity()

        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(duration))
        let attributes = RestTimerAttributes(exerciseName: exerciseName, setNumber: setNumber)
        let state = RestTimerAttributes.ContentState(
            timerRange: now...end,
            totalSeconds: duration,
            isRunning: true
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: end)
            )
            print("[WatchLiveActivityManager] Started activity id=\(currentActivity?.id ?? "nil") exercise=\(exerciseName) set=\(setNumber) duration=\(duration)s")
        } catch {
            print("[WatchLiveActivityManager] Failed to start activity: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func endActivity() {
        guard #available(watchOS 11.0, iOS 16.1, *) else { return }
        guard let activity = currentActivity else { return }

        let now = Date()
        let finalState = RestTimerAttributes.ContentState(
            timerRange: now...now,
            totalSeconds: 0,
            isRunning: false
        )

        print("[WatchLiveActivityManager] Ending activity id=\(activity.id)")
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
    #endif
}
