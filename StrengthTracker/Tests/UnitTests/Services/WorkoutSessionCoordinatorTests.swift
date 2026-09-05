import Testing
import Foundation
@testable import StrengthTrackerShared

// MARK: - Spies

@MainActor
final class SpyRestTimer: RestTimerControlling {
    var isRunning = false
    var endDate: Date?
    var starts: [(seconds: Int?, exerciseName: String?, setNumber: Int?)] = []
    var stopCount = 0

    func start(seconds: Int?, exerciseName: String?, setNumber: Int?) {
        starts.append((seconds, exerciseName, setNumber))
        isRunning = true
        endDate = Date().addingTimeInterval(TimeInterval(seconds ?? 90))
    }

    func stop() {
        stopCount += 1
        isRunning = false
        endDate = nil
    }
}

/// Delegates state building to the pure `WidgetDataService` builder and records
/// what would have been published, without touching the App Group or WidgetCenter.
final class SpyWidgetPublisher: ActiveWorkoutWidgetPublishing, @unchecked Sendable {
    private let lock = NSLock()
    private var _published: [WidgetActiveWorkout?] = []
    var published: [WidgetActiveWorkout?] {
        lock.lock(); defer { lock.unlock() }
        return _published
    }

    func buildActiveWorkoutState(
        workout: Workout, isResting: Bool, restEndDate: Date?, activeExerciseId: UUID?
    ) -> WidgetActiveWorkout {
        WidgetDataService().buildActiveWorkoutState(
            workout: workout, isResting: isResting, restEndDate: restEndDate, activeExerciseId: activeExerciseId
        )
    }

    func updateActiveWorkoutState(_ activeWorkout: WidgetActiveWorkout?) {
        lock.lock(); defer { lock.unlock() }
        _published.append(activeWorkout)
    }
}

// MARK: - Tests

@Suite("WorkoutSessionCoordinator", .serialized)
@MainActor
struct WorkoutSessionCoordinatorTests {

    private struct Stack {
        let coordinator: WorkoutSessionCoordinator
        let vm: WorkoutViewModel
        let timer: SpyRestTimer
        let widget: SpyWidgetPublisher
        let prefs: UserPreferencesService
    }

    /// UserPreferencesService persists to UserDefaults.standard; snapshot and
    /// restore the keys this suite touches.
    private static let touchedKeys = [
        "autoStartRestTimer", "hasSetAutoStartRestTimer", "defaultRestSeconds", "deloadRestPercentage"
    ]

    private func withPrefs<T>(_ body: (UserPreferencesService) async throws -> T) async rethrows -> T {
        let defaults = UserDefaults.standard
        let snapshot = Self.touchedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in snapshot {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let prefs = UserPreferencesService()
        prefs.autoStartRestTimer = true
        prefs.defaultRestSeconds = 90
        prefs.deloadRestPercentage = 50
        return try await body(prefs)
    }

    private func makeStack(prefs: UserPreferencesService) -> Stack {
        let vm = WorkoutViewModel(
            workoutRepository: InMemoryWorkoutRepository(),
            templateRepository: InMemoryTemplateRepository(),
            healthKitService: NoOpHealthKitService(),
            userPreferencesService: prefs
        )
        let timer = SpyRestTimer()
        let widget = SpyWidgetPublisher()
        let coordinator = WorkoutSessionCoordinator(
            workoutViewModel: vm,
            restTimer: timer,
            widgetPublisher: widget,
            preferences: prefs,
            publishSynchronously: true
        )
        return Stack(coordinator: coordinator, vm: vm, timer: timer, widget: widget, prefs: prefs)
    }

    private func makeExercise(name: String = "Bench Press") -> Exercise {
        Exercise(
            id: UUID(), name: name, primaryMuscleGroup: .chest, secondaryMuscleGroups: [],
            category: .barbell, exerciseType: .weightedReps, instructions: nil,
            isCustom: false, isArchived: false
        )
    }

    /// Starts a workout with one exercise and one planned set; returns their ids.
    private func startWithOneSet(_ s: Stack, restSeconds: Int? = nil, isDeload: Bool = false) async throws -> (exerciseId: UUID, setId: UUID) {
        try await s.coordinator.start(.init(name: "Test", isDeload: isDeload))
        let added = await s.vm.addExercise(makeExercise(), sets: [])
        let exerciseId = try #require(added?.id)
        if let restSeconds {
            await s.vm.updateExerciseRestTimer(exerciseId: exerciseId, seconds: restSeconds)
        }
        await s.vm.addEmptySet(exerciseId: exerciseId)
        let setId = try #require(s.vm.currentWorkout?.exercises[0].sets.first?.id)
        return (exerciseId, setId)
    }

    @Test("completing a set starts the rest timer with the exercise's rest seconds")
    func testCompleteUsesExerciseRest() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            let (exerciseId, setId) = try await startWithOneSet(s, restSeconds: 120)
            try await s.coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            #expect(s.timer.starts.count == 1)
            #expect(s.timer.starts[0].seconds == 120)
            #expect(s.timer.starts[0].exerciseName == "Bench Press")
            #expect(s.timer.starts[0].setNumber == 1)
            #expect(s.vm.currentWorkout?.exercises[0].sets[0].isCompleted == true)
        }
    }

    @Test("completing a set falls back to the default rest seconds")
    func testCompleteUsesDefaultRest() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            let (exerciseId, setId) = try await startWithOneSet(s)
            try await s.coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            #expect(s.timer.starts.first?.seconds == 90)
        }
    }

    @Test("deload shortens rest, never below 15 seconds")
    func testDeloadShortensRest() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            let (exerciseId, setId) = try await startWithOneSet(s, restSeconds: 20, isDeload: true)
            try await s.coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            #expect(s.timer.starts.first?.seconds == 15)
        }
    }

    @Test("auto-start disabled never starts the timer")
    func testAutoStartDisabled() async throws {
        try await withPrefs { prefs in
            prefs.autoStartRestTimer = false
            let s = makeStack(prefs: prefs)
            let (exerciseId, setId) = try await startWithOneSet(s)
            try await s.coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            #expect(s.timer.starts.isEmpty)
            #expect(s.vm.currentWorkout?.exercises[0].sets[0].isCompleted == true)
        }
    }

    @Test("completeSet is idempotent and uncompleteSet never starts the timer")
    func testIdempotentCompletion() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            let (exerciseId, setId) = try await startWithOneSet(s)
            try await s.coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            try await s.coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            #expect(s.timer.starts.count == 1)
            try await s.coordinator.uncompleteSet(exerciseId: exerciseId, setId: setId)
            #expect(s.timer.starts.count == 1)
            #expect(s.vm.currentWorkout?.exercises[0].sets[0].isCompleted == false)
        }
    }

    @Test("completing publishes widget state; finishing publishes nil")
    func testWidgetPublishing() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            let (exerciseId, setId) = try await startWithOneSet(s)
            try await s.coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            let last = try #require(s.widget.published.last)
            #expect(last?.completedSets == 1)
            #expect(last?.isResting == true)

            try await s.coordinator.finish()
            #expect(s.timer.stopCount >= 1)
            #expect(s.widget.published.last! == nil)
            #expect(s.vm.isActive == false)
        }
    }

    @Test("start refuses while a workout is active unless replacing")
    func testStartGuard() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            try await s.coordinator.start(.init(name: "First"))
            let firstId = s.vm.currentWorkout?.id
            await #expect(throws: WorkoutSessionCoordinator.SessionError.workoutAlreadyActive(name: "First")) {
                try await s.coordinator.start(.init(name: "Second"))
            }
            #expect(s.vm.currentWorkout?.id == firstId)

            try await s.coordinator.start(.init(name: "Second"), replacingActive: true)
            #expect(s.vm.currentWorkout?.name == "Second")
            #expect(s.vm.currentWorkout?.id != firstId)
        }
    }

    @Test("start refuses while a Watch workout is in progress")
    func testStartRefusesWatchWorkout() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            s.vm.watchActiveWorkout = Workout(
                id: UUID(), name: "Watch", startedAt: Date(), completedAt: nil,
                notes: nil, templateId: nil, exercises: []
            )
            await #expect(throws: WorkoutSessionCoordinator.SessionError.watchWorkoutInProgress) {
                try await s.coordinator.start(.init(name: "Phone"))
            }
            #expect(s.vm.isActive == false)
        }
    }

    @Test("start carries planned session ids onto the workout")
    func testStartPlannedSession() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            let sessionId = UUID(), planId = UUID()
            try await s.coordinator.start(.init(name: "Day 1", plannedSessionId: sessionId, plannedPlanId: planId))
            #expect(s.vm.currentWorkout?.plannedSessionId == sessionId)
            #expect(s.vm.currentWorkout?.plannedPlanId == planId)
        }
    }

    @Test("cancel stops the timer, clears the workout and publishes nil")
    func testCancel() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            _ = try await startWithOneSet(s)
            await s.coordinator.cancel()
            #expect(s.timer.stopCount >= 1)
            #expect(s.vm.isActive == false)
            #expect(s.vm.currentWorkout == nil)
            #expect(s.widget.published.last! == nil)
        }
    }

    @Test("finish without an active workout throws")
    func testFinishWithoutWorkout() async throws {
        try await withPrefs { prefs in
            let s = makeStack(prefs: prefs)
            await #expect(throws: WorkoutSessionCoordinator.SessionError.noActiveWorkout) {
                try await s.coordinator.finish()
            }
        }
    }
}
