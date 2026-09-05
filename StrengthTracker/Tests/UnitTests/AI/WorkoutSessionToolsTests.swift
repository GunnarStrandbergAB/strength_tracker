import Testing
import Foundation
@testable import StrengthTrackerShared

// MARK: - Stub session controller

@MainActor
final class StubSessionController: WorkoutSessionControlling {
    var activeWorkout: Workout?
    var watchWorkoutInProgress = false
    var templates: [WorkoutTemplate] = []
    var plan: ProgressionPlan?
    var startRequests: [WorkoutSessionCoordinator.StartRequest] = []
    var finishNotes: [String?] = []
    var finished: Workout?

    func start(_ request: WorkoutSessionCoordinator.StartRequest) async throws -> Workout {
        startRequests.append(request)
        let workout = Workout(
            id: UUID(), name: request.name, startedAt: Date(), completedAt: nil, notes: nil,
            templateId: request.template?.id, isDeload: request.isDeload,
            plannedSessionId: request.plannedSessionId, plannedPlanId: request.plannedPlanId,
            exercises: request.template?.instantiateExercises() ?? []
        )
        activeWorkout = workout
        return workout
    }

    func finish(notes: String?) async throws -> Workout {
        guard var workout = activeWorkout else { throw WorkoutEditError.noActiveWorkout }
        finishNotes.append(notes)
        workout.completedAt = workout.startedAt.addingTimeInterval(3600)
        if let notes { workout.notes = notes }
        activeWorkout = nil
        finished = workout
        return workout
    }

    func allTemplates() async throws -> [WorkoutTemplate] { templates }
    func activePlan() async -> ProgressionPlan? { plan }
    func sessionTemplate(for session: PlannedSession) async -> WorkoutTemplate? {
        WorkoutTemplate(id: UUID(), name: session.sessionLabel, notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0, exercises: [])
    }
}

@Suite("AI workout session tools")
@MainActor
struct WorkoutSessionToolsTests {

    private func makeExercise(_ name: String = "Bench Press") -> Exercise {
        Exercise(id: UUID(), name: name, primaryMuscleGroup: .chest, secondaryMuscleGroups: [],
                 category: .barbell, exerciseType: .weightedReps, instructions: nil, isCustom: false, isArchived: false)
    }

    private func makeTemplate(_ name: String, isCustom: Bool) -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID(), name: name, notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0,
            exercises: [TemplateExercise(
                id: UUID(), exercise: makeExercise(), order: 1, supersetGroup: nil, notes: nil,
                restTimerSeconds: 90, targetSets: 3, targetReps: 8, targetWeight: 80,
                targetDurationSeconds: nil, targetDistanceMeters: nil
            )],
            isCustom: isCustom
        )
    }

    private func makeActiveWorkout(completedSets: Int = 2) -> Workout {
        let sets = (0..<3).map { i in
            ExerciseSet(id: UUID(), order: i + 1, setType: .normal, weight: 80, reps: 8, durationSeconds: nil,
                        distanceMeters: nil, rpe: nil, isCompleted: i < completedSets, isPersonalRecord: false,
                        completedAt: i < completedSets ? Date() : nil)
        }
        return Workout(
            id: UUID(), name: "Legs", startedAt: Date().addingTimeInterval(-1500), completedAt: nil,
            notes: nil, templateId: nil,
            exercises: [WorkoutExercise(id: UUID(), exercise: makeExercise("Squat"), order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: sets)]
        )
    }

    private func makePlan(sessions: [(label: String, daysFromNow: Int, closed: Bool)], weekIsDeload: Bool = false) -> ProgressionPlan {
        let planned = sessions.map { spec in
            PlannedSession(
                scheduledDate: Calendar.current.date(byAdding: .day, value: spec.daysFromNow, to: Date()),
                sessionLabel: spec.label,
                completedWorkoutId: spec.closed ? UUID() : nil
            )
        }
        let week = TrainingWeek(weekNumber: 1, absoluteWeekNumber: 3, sessions: planned, isDeload: weekIsDeload)
        let block = TrainingBlock(name: "Block", order: 1, durationWeeks: 4, weeks: [week])
        return ProgressionPlan(
            name: "PPL", status: .active, trainingStatus: .intermediate, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, exercises: [], blocks: [block]
        )
    }

    private func json(_ result: AIToolResult) throws -> [String: JSONValue] {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(result.outputForModel.utf8))
        guard case .object(let object) = decoded else { throw AIToolError("output was not a JSON object") }
        return object
    }

    private func expectError(_ body: () async throws -> Void, contains fragment: String) async {
        do {
            try await body()
            Issue.record("expected an error containing '\(fragment)'")
        } catch {
            #expect(error.localizedDescription.contains(fragment), "got: \(error.localizedDescription)")
        }
    }

    // MARK: - start_workout

    @Test("start_workout with no arguments starts an empty Quick Workout")
    func startEmpty() async throws {
        let session = StubSessionController()
        let tool = StartWorkoutTool(session: session, userPreferencesService: nil)
        let result = try await tool.call(argumentsJSON: "{}")
        #expect(session.startRequests.count == 1)
        #expect(session.startRequests[0].name == "Quick Workout")
        #expect(session.startRequests[0].template == nil)
        #expect(try json(result)["status"] == .string("started"))
        #expect(result.receipt?.headline == "Started Quick Workout")
        #expect(result.draft == nil)
    }

    @Test("start_workout resolves library templates too, custom first")
    func startFromTemplate() async throws {
        let session = StubSessionController()
        session.templates = [makeTemplate("Push A", isCustom: false), makeTemplate("Full Body", isCustom: true)]
        let tool = StartWorkoutTool(session: session, userPreferencesService: nil)
        let result = try await tool.call(argumentsJSON: #"{"template_name":"push a"}"#)
        #expect(session.startRequests.count == 1)
        #expect(session.startRequests.first?.template?.name == "Push A")
        #expect(session.startRequests.first?.name == "Push A")
        #expect(result.receipt?.sections.first?.lines.first == "1 exercise · From template 'Push A'")

        session.activeWorkout = nil  // the stub keeps the started workout active
        _ = try await tool.call(argumentsJSON: #"{"template_name":"Full Body","name":"Monday"}"#)
        #expect(session.startRequests.count == 2)
        #expect(session.startRequests.last?.name == "Monday")
        await expectError({ _ = try await tool.call(argumentsJSON: #"{"template_name":"Pull Z"}"#) }, contains: "No template named")
    }

    @Test("start_workout plan_session next picks the earliest open session and inherits the week's deload")
    func startFromPlanNext() async throws {
        let session = StubSessionController()
        session.plan = makePlan(sessions: [("Day 1", -2, true), ("Day 2", 0, false), ("Day 3", 2, false)], weekIsDeload: true)
        let tool = StartWorkoutTool(session: session, userPreferencesService: nil)
        let result = try await tool.call(argumentsJSON: #"{"plan_session":"next"}"#)
        let request = session.startRequests[0]
        #expect(request.name == "Day 2")
        #expect(request.isDeload)
        #expect(request.plannedPlanId == session.plan?.id)
        #expect(request.plannedSessionId == session.plan?.blocks[0].weeks[0].sessions[1].id)
        #expect(result.receipt?.sections[0].lines.contains("Deload") == true)
        #expect(result.receipt?.sections[0].lines[0].contains("Plan PPL · week 3 · Day 2") == true)
    }

    @Test("start_workout plan_session by date and its error cases")
    func startFromPlanDate() async throws {
        let session = StubSessionController()
        let tool = StartWorkoutTool(session: session, userPreferencesService: nil)
        await expectError({ _ = try await tool.call(argumentsJSON: #"{"plan_session":"next"}"#) }, contains: "No active training plan")

        session.plan = makePlan(sessions: [("Day 1", 0, false), ("Day 2", 2, false)])
        let inTwoDays = AIJSON.dateString(Calendar.current.date(byAdding: .day, value: 2, to: Date())!)
        _ = try await tool.call(argumentsJSON: #"{"plan_session":"\#(inTwoDays)"}"#)
        #expect(session.startRequests[0].name == "Day 2")

        let inTenDays = AIJSON.dateString(Calendar.current.date(byAdding: .day, value: 10, to: Date())!)
        await expectError({ _ = try await tool.call(argumentsJSON: #"{"plan_session":"\#(inTenDays)"}"#) }, contains: "Open sessions")
        await expectError({ _ = try await tool.call(argumentsJSON: #"{"plan_session":"next","template_name":"X"}"#) }, contains: "not both")
    }

    @Test("start_workout while a workout is active returns a confirm draft and starts nothing")
    func startWhileActive() async throws {
        let session = StubSessionController()
        session.activeWorkout = makeActiveWorkout()
        session.templates = [makeTemplate("Push A", isCustom: true)]
        let tool = StartWorkoutTool(session: session, userPreferencesService: nil)
        let result = try await tool.call(argumentsJSON: #"{"template_name":"Push A"}"#)
        guard case .action(let action)? = result.draft,
              case .startWorkout(let name, let templateID, _, _, _, let replacing) = action.kind else {
            Issue.record("expected a startWorkout confirm draft"); return
        }
        #expect(name == "Push A")
        #expect(templateID == session.templates[0].id)
        #expect(replacing == session.activeWorkout?.id)
        #expect(action.confirmLabel == "Discard & Start")
        #expect(action.summaryLines[0].contains("2 completed sets"))
        #expect(session.startRequests.isEmpty)
        #expect(result.outputForModel.contains("confirmation_presented"))
    }

    @Test("start_workout refuses while a Watch workout is in progress")
    func startWatchGuard() async throws {
        let session = StubSessionController()
        session.watchWorkoutInProgress = true
        let tool = StartWorkoutTool(session: session, userPreferencesService: nil)
        await expectError({ _ = try await tool.call(argumentsJSON: "{}") }, contains: "Apple Watch")
    }

    // MARK: - finish_workout

    @Test("finish_workout finishes, appends notes and summarizes")
    func finish() async throws {
        let session = StubSessionController()
        session.activeWorkout = makeActiveWorkout(completedSets: 2)
        let tool = FinishWorkoutTool(session: session, userPreferencesService: nil)
        let result = try await tool.call(argumentsJSON: #"{"notes":"Good session"}"#)
        #expect(session.finishNotes == ["Good session"])
        let object = try json(result)
        #expect(object["status"] == .string("completed"))
        #expect(object["sets_completed"] == .number(2))
        #expect(object["incomplete_sets"] == .number(1))
        #expect(object["duration_min"] == .number(60))
        #expect(object["volume_kg"] == .number(1280))
        let receipt = try #require(result.receipt)
        #expect(receipt.scope == .session)
        #expect(receipt.headline == "Finished Legs")
        #expect(receipt.sections[0].lines[0] == "60 min · 2 sets · 1280 kg")
        #expect(receipt.sections[0].lines[1] == "1 planned set left incomplete")

        await expectError({ _ = try await tool.call(argumentsJSON: "{}") }, contains: "No active workout")
    }

    // MARK: - cancel_workout

    @Test("cancel_workout always asks to confirm")
    func cancel() async throws {
        let session = StubSessionController()
        let tool = CancelWorkoutTool(session: session)
        await expectError({ _ = try await tool.call(argumentsJSON: "{}") }, contains: "No active workout")

        session.activeWorkout = makeActiveWorkout(completedSets: 3)
        let result = try await tool.call(argumentsJSON: "{}")
        guard case .action(let action)? = result.draft, case .cancelWorkout(let id) = action.kind else {
            Issue.record("expected a cancel confirm draft"); return
        }
        #expect(id == session.activeWorkout?.id)
        #expect(action.summaryLines[0].hasPrefix("3 logged sets"))
        #expect(session.activeWorkout != nil)
    }

    // MARK: - Executor

    @Test("executor runs confirmed actions through the coordinator and editor")
    func executor() async throws {
        let repo = InMemoryWorkoutRepository()
        let vm = WorkoutViewModel(workoutRepository: repo, templateRepository: InMemoryTemplateRepository(), healthKitService: NoOpHealthKitService())
        let prefs = UserPreferencesService()
        let timer = SpyRestTimer()
        let coordinator = WorkoutSessionCoordinator(workoutViewModel: vm, restTimer: timer, widgetPublisher: SpyWidgetPublisher(), preferences: prefs, publishSynchronously: true)
        let resolver = WorkoutEditorResolver(
            workoutViewModel: vm, coordinator: coordinator, workoutRepository: repo,
            makeHistoryViewModel: { HistoryViewModel(workoutRepository: repo) }
        )
        let planVM = ProgressionPlanViewModel(
            progressionPlanRepository: InMemoryProgressionPlanRepository(),
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: repo),
            programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: repo),
            exerciseRepository: InMemoryExerciseRepository(),
            templateRepository: InMemoryTemplateRepository(),
            workoutRepository: repo,
            sessionExecutionService: SessionExecutionService(),
            adaptiveAdjustmentService: nil,
            coachingCommunicationService: CoachingCommunicationService()
        )
        let executor = AIPendingActionExecutor(coordinator: coordinator, resolver: resolver, templateRepository: InMemoryTemplateRepository(), progressionPlanViewModel: planVM)

        try await coordinator.start(.init(name: "First"))
        let added = try #require(await vm.addExercise(makeExercise(), sets: [SetPrefill(weightKg: 80, reps: 8).makeSet(order: 1), SetPrefill().makeSet(order: 2)]))
        let firstId = try #require(vm.currentWorkout?.id)

        // removeSet
        try await executor.execute(AIPendingAction(kind: .removeSet(workoutID: firstId, exerciseID: added.id, setID: added.sets[0].id), title: "", summaryLines: [], confirmLabel: ""))
        #expect(vm.currentWorkout?.exercises[0].sets.count == 1)

        // removeExercise
        try await executor.execute(AIPendingAction(kind: .removeExercise(workoutID: firstId, exerciseID: added.id), title: "", summaryLines: [], confirmLabel: ""))
        #expect(vm.currentWorkout?.exercises.isEmpty == true)

        // startWorkout replacing the active one; stale id is refused
        await expectError({
            try await executor.execute(AIPendingAction(kind: .startWorkout(name: "Second", templateID: nil, plannedSessionID: nil, plannedPlanID: nil, isDeload: true, replacingWorkoutID: UUID()), title: "", summaryLines: [], confirmLabel: ""))
        }, contains: "changed since")
        try await executor.execute(AIPendingAction(kind: .startWorkout(name: "Second", templateID: nil, plannedSessionID: nil, plannedPlanID: nil, isDeload: true, replacingWorkoutID: firstId), title: "", summaryLines: [], confirmLabel: ""))
        #expect(vm.currentWorkout?.name == "Second")
        #expect(vm.currentWorkout?.isDeload == true)
        #expect(vm.currentWorkout?.id != firstId)

        // cancelWorkout
        let secondId = try #require(vm.currentWorkout?.id)
        await expectError({
            try await executor.execute(AIPendingAction(kind: .cancelWorkout(workoutID: UUID()), title: "", summaryLines: [], confirmLabel: ""))
        }, contains: "no longer active")
        try await executor.execute(AIPendingAction(kind: .cancelWorkout(workoutID: secondId), title: "", summaryLines: [], confirmLabel: ""))
        #expect(vm.isActive == false)
        #expect(timer.stopCount >= 1)
    }
}
