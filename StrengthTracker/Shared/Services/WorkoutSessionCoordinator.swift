import Foundation

// MARK: - Test seams

/// Rest-timer surface the coordinator needs. `RestTimerService` owns the Live
/// Activity and local notifications, so tests substitute a spy.
@MainActor
public protocol RestTimerControlling: AnyObject {
    var isRunning: Bool { get }
    var endDate: Date? { get }
    func start(seconds: Int?, exerciseName: String?, setNumber: Int?)
    func stop()
}

extension RestTimerService: RestTimerControlling {}

/// Widget publishing surface. `WidgetDataService` touches the App Group store and
/// `WidgetCenter`, so tests substitute a spy.
public protocol ActiveWorkoutWidgetPublishing: Sendable {
    func buildActiveWorkoutState(
        workout: Workout, isResting: Bool, restEndDate: Date?, activeExerciseId: UUID?
    ) -> WidgetActiveWorkout
    func updateActiveWorkoutState(_ activeWorkout: WidgetActiveWorkout?)
}

extension WidgetDataService: ActiveWorkoutWidgetPublishing {}

// MARK: - Coordinator

/// The single code path for the side effects of driving an active workout:
/// rest timer + Live Activity on set completion, widget state, and the
/// start/finish/cancel lifecycle. Both the UI (ActiveWorkoutView, ContentView)
/// and the AI tools go through it, so an AI-logged set behaves exactly like a tap.
@MainActor
public final class WorkoutSessionCoordinator {

    public struct StartRequest: Sendable {
        public var name: String
        public var template: WorkoutTemplate?
        public var isDeload: Bool
        public var plannedSessionId: UUID?
        public var plannedPlanId: UUID?

        public init(
            name: String,
            template: WorkoutTemplate? = nil,
            isDeload: Bool = false,
            plannedSessionId: UUID? = nil,
            plannedPlanId: UUID? = nil
        ) {
            self.name = name
            self.template = template
            self.isDeload = isDeload
            self.plannedSessionId = plannedSessionId
            self.plannedPlanId = plannedPlanId
        }
    }

    public enum SessionError: Error, LocalizedError, Equatable {
        case workoutAlreadyActive(name: String)
        case watchWorkoutInProgress
        case noActiveWorkout
        case setNotFound
        case saveFailed(String)

        public var errorDescription: String? {
            switch self {
            case .workoutAlreadyActive(let name):
                return "A workout '\(name)' is already active."
            case .watchWorkoutInProgress:
                return "A workout is in progress on Apple Watch."
            case .noActiveWorkout:
                return "No active workout."
            case .setNotFound:
                return "Set not found."
            case .saveFailed(let message):
                return message
            }
        }
    }

    public let workoutViewModel: WorkoutViewModel
    private let restTimer: any RestTimerControlling
    private let widgetPublisher: any ActiveWorkoutWidgetPublishing
    private let preferences: UserPreferencesService
    /// Tests publish inline so assertions can run right after the call.
    private let publishSynchronously: Bool

    public init(
        workoutViewModel: WorkoutViewModel,
        restTimer: any RestTimerControlling,
        widgetPublisher: any ActiveWorkoutWidgetPublishing = WidgetDataService(),
        preferences: UserPreferencesService,
        publishSynchronously: Bool = false
    ) {
        self.workoutViewModel = workoutViewModel
        self.restTimer = restTimer
        self.widgetPublisher = widgetPublisher
        self.preferences = preferences
        self.publishSynchronously = publishSynchronously
    }

    // MARK: Sets

    /// Toggles a set and, when it became completed, starts the rest timer.
    /// Returns the new completion state, or nil if the set was not found.
    @discardableResult
    public func toggleSet(exerciseId: UUID, setId: UUID) async -> Bool? {
        await workoutViewModel.toggleSetCompletion(exerciseId: exerciseId, setId: setId)
        guard let workout = workoutViewModel.currentWorkout,
              let exercise = workout.exercises.first(where: { $0.id == exerciseId }),
              let set = exercise.sets.first(where: { $0.id == setId }) else {
            refreshWidget()
            return nil
        }
        if set.isCompleted {
            startRestTimerIfNeeded(workout: workout, exercise: exercise, setId: setId)
        }
        refreshWidget()
        return set.isCompleted
    }

    /// Completes the set only if it is currently incomplete (never restarts the
    /// rest timer for an already-completed set).
    public func completeSet(exerciseId: UUID, setId: UUID) async throws {
        guard let set = findSet(exerciseId: exerciseId, setId: setId) else { throw SessionError.setNotFound }
        guard !set.isCompleted else { return }
        await toggleSet(exerciseId: exerciseId, setId: setId)
    }

    public func uncompleteSet(exerciseId: UUID, setId: UUID) async throws {
        guard let set = findSet(exerciseId: exerciseId, setId: setId) else { throw SessionError.setNotFound }
        guard set.isCompleted else { return }
        await toggleSet(exerciseId: exerciseId, setId: setId)
    }

    // MARK: Session lifecycle

    /// Starts a workout. Refuses while another workout is active unless
    /// `replacingActive` is set (`startWorkout` deletes every in-progress workout).
    public func start(_ request: StartRequest, replacingActive: Bool = false) async throws {
        if workoutViewModel.watchActiveWorkout != nil {
            throw SessionError.watchWorkoutInProgress
        }
        if workoutViewModel.isActive, let current = workoutViewModel.currentWorkout, !replacingActive {
            throw SessionError.workoutAlreadyActive(name: current.name)
        }
        restTimer.stop()
        workoutViewModel.plannedSessionId = request.plannedSessionId
        workoutViewModel.plannedPlanId = request.plannedPlanId
        workoutViewModel.errorMessage = nil
        await workoutViewModel.startWorkout(
            name: request.name, from: request.template, isDeload: request.isDeload
        )
        if let message = workoutViewModel.errorMessage {
            throw SessionError.saveFailed(message)
        }
        refreshWidget()
    }

    public func finish() async throws {
        guard workoutViewModel.isActive else { throw SessionError.noActiveWorkout }
        restTimer.stop()
        try await workoutViewModel.completeWorkout()
        refreshWidget()
    }

    public func cancel() async {
        restTimer.stop()
        await workoutViewModel.cancelWorkout()
        refreshWidget()
    }

    public func setActiveExercise(_ exerciseId: UUID) {
        workoutViewModel.activeExerciseId = exerciseId
        refreshWidget()
    }

    public func skipRest() {
        restTimer.stop()
        refreshWidget()
    }

    // MARK: Widget

    public func refreshWidget() {
        let state: WidgetActiveWorkout?
        if let workout = workoutViewModel.currentWorkout, workoutViewModel.isActive {
            state = widgetPublisher.buildActiveWorkoutState(
                workout: workout,
                isResting: restTimer.isRunning,
                restEndDate: restTimer.isRunning ? restTimer.endDate : nil,
                activeExerciseId: workoutViewModel.activeExerciseId
            )
        } else {
            state = nil
        }
        let publisher = widgetPublisher
        if publishSynchronously {
            publisher.updateActiveWorkoutState(state)
        } else {
            // App-Group JSON round-trip + WidgetCenter XPC — keep it off the main
            // thread so taps and set toggles render without waiting on it.
            Task.detached(priority: .utility) {
                publisher.updateActiveWorkoutState(state)
            }
        }
    }

    // MARK: Private

    private func findSet(exerciseId: UUID, setId: UUID) -> ExerciseSet? {
        workoutViewModel.currentWorkout?
            .exercises.first(where: { $0.id == exerciseId })?
            .sets.first(where: { $0.id == setId })
    }

    private func startRestTimerIfNeeded(workout: Workout, exercise: WorkoutExercise, setId: UUID) {
        guard preferences.autoStartRestTimer else { return }
        var restSeconds = exercise.restTimerSeconds ?? preferences.defaultRestSeconds
        if workout.isDeload {
            restSeconds = max(15, restSeconds * preferences.deloadRestPercentage / 100)
        }
        let setIndex = exercise.sets.firstIndex(where: { $0.id == setId }) ?? 0
        restTimer.start(
            seconds: restSeconds,
            exerciseName: exercise.exercise.name,
            setNumber: setIndex + 1
        )
    }
}
