import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("propose_training_plan tool")
@MainActor
struct ProposeTrainingPlanToolTests {

    private func makeTool(
        exercises: [Exercise],
        records: [PersonalRecord] = [],
        templates: [WorkoutTemplate] = []
    ) async throws -> ProposeTrainingPlanTool {
        let exerciseRepo = InMemoryExerciseRepository()
        for exercise in exercises { _ = try await exerciseRepo.save(exercise) }
        let recordRepo = InMemoryPersonalRecordRepository()
        for record in records { _ = try await recordRepo.save(record) }
        let templateRepo = InMemoryTemplateRepository()
        for template in templates { _ = try await templateRepo.save(template) }
        return ProposeTrainingPlanTool(
            exerciseRepository: exerciseRepo,
            personalRecordRepository: recordRepo,
            templateRepository: templateRepo
        )
    }

    private func makeExercise(name: String) -> Exercise {
        Exercise(
            id: UUID(), name: name, primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [], category: .barbell,
            exerciseType: .weightedReps, instructions: nil, isCustom: false, isArchived: false
        )
    }

    private func makeTemplate(name: String, exercises: [Exercise]) -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID(), name: name, notes: nil, sortOrder: 0,
            lastUsedAt: nil, timesUsed: 0,
            exercises: exercises.enumerated().map { index, exercise in
                TemplateExercise(
                    id: UUID(), exercise: exercise, order: index,
                    supersetGroup: nil, notes: nil, restTimerSeconds: nil,
                    targetSets: 3, targetReps: 10, targetWeight: 0,
                    targetDurationSeconds: nil, targetDistanceMeters: nil
                )
            },
            isCustom: true
        )
    }

    @Test("Builds a plan draft with PR-backed 1RMs when the model gives none")
    func planDraftWithPRFallback() async throws {
        let bench = makeExercise(name: "Bench Press")
        let squat = makeExercise(name: "Back Squat")
        let tool = try await makeTool(
            exercises: [bench, squat],
            records: [PersonalRecord(
                id: UUID(), exerciseId: bench.id, recordType: .estimatedOneRepMax,
                value: 110, setId: nil, achievedAt: Date()
            )]
        )

        let result = try await tool.call(argumentsJSON: """
        {"name":"Strength Cycle","goal":"strength","weekly_frequency":4,
         "training_days":[2,3,5,6],
         "exercises":[
           {"exercise_name":"bench press"},
           {"exercise_name":"Back Squat","estimated_1rm":{"value":330,"unit":"lbs"}}
         ]}
        """)

        guard case .plan(let parameters)? = result.draft else {
            Issue.record("expected plan draft")
            return
        }
        #expect(parameters.name == "Strength Cycle")
        #expect(parameters.primaryGoal == .strength)
        #expect(parameters.weeklyFrequency == 4)
        #expect(parameters.trainingDays == [2, 3, 5, 6])
        #expect(parameters.exercises.count == 2)
        #expect(parameters.exercises[0].estimated1RMKg == 110)          // from PR (kg)
        #expect(abs((parameters.exercises[1].estimated1RMKg ?? 0) - 149.7) < 0.1) // 330 lbs → kg
        #expect(result.outputForModel.contains("proposal_presented"))
    }

    @Test("Frequency must match training day count; duplicate days rejected")
    func frequencyDayMismatch() async throws {
        let bench = makeExercise(name: "Bench Press")
        let record = PersonalRecord(
            id: UUID(), exerciseId: bench.id, recordType: .estimatedOneRepMax,
            value: 100, setId: nil, achievedAt: Date()
        )
        let tool = try await makeTool(exercises: [bench], records: [record])

        // frequency 4 but only 2 days
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":4,"training_days":[2,4],
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
        }
        // duplicated day
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":2,"training_days":[2,2],
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
        }
    }

    @Test("Past start dates are rejected; today is allowed")
    func startDateValidation() async throws {
        let bench = makeExercise(name: "Bench Press")
        let record = PersonalRecord(
            id: UUID(), exerciseId: bench.id, recordType: .estimatedOneRepMax,
            value: 100, setId: nil, achievedAt: Date()
        )
        let tool = try await makeTool(exercises: [bench], records: [record])

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":3,"start_date":"2020-01-01",
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
        }
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":3,"start_date":"2093-01-01",
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let result = try await tool.call(argumentsJSON: """
        {"name":"P","goal":"strength","weekly_frequency":3,"start_date":"\(today)",
         "exercises":[{"exercise_name":"Bench Press"}]}
        """)
        #expect(result.draft != nil)
    }

    @Test("An exercise with no resolvable 1RM is rejected, naming the exercise")
    func missing1RMRejected() async throws {
        let bench = makeExercise(name: "Bench Press")
        let tool = try await makeTool(exercises: [bench])   // no PRs, no estimated_1rm

        do {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":3,
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
            Issue.record("expected throw")
        } catch let error as AIToolError {
            #expect(error.message.contains("Bench Press"))
            #expect(error.message.contains("estimated_1rm"))
        }
    }

    @Test("day_splits resolve to ids and derive training days")
    func daySplits() async throws {
        let bench = makeExercise(name: "Bench Press")
        let squat = makeExercise(name: "Back Squat")
        let tool = try await makeTool(exercises: [bench, squat])

        let result = try await tool.call(argumentsJSON: """
        {"name":"PPL-ish","goal":"strength","weekly_frequency":2,
         "exercises":[
           {"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}},
           {"exercise_name":"Back Squat","estimated_1rm":{"value":140,"unit":"kg"}}
         ],
         "day_splits":[
           {"training_day":2,"exercise_names":["Bench Press"]},
           {"training_day":5,"exercise_names":["back squat"]}
         ]}
        """)

        guard case .plan(let parameters)? = result.draft else {
            Issue.record("expected plan draft")
            return
        }
        #expect(parameters.trainingDays == [2, 5])
        #expect(parameters.daySplits?.count == 2)
        #expect(parameters.daySplits?[0].exerciseIDs == [bench.id])
        #expect(parameters.daySplits?[1].exerciseIDs == [squat.id])
        #expect(parameters.daySplits?[1].exerciseNames == ["Back Squat"])
    }

    @Test("day_splits validation: day mismatches and unknown exercises throw")
    func daySplitsValidation() async throws {
        let bench = makeExercise(name: "Bench Press")
        let tool = try await makeTool(exercises: [bench])

        // Split days must match training_days
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":1,"training_days":[2],
             "exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}],
             "day_splits":[{"training_day":3,"exercise_names":["Bench Press"]}]}
            """)
        }
        // Split references an exercise not in the plan
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":1,
             "exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}],
             "day_splits":[{"training_day":2,"exercise_names":["Deadlift"]}]}
            """)
        }
        // Split count must match weekly_frequency when training_days omitted
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":3,
             "exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}],
             "day_splits":[{"training_day":2,"exercise_names":["Bench Press"]}]}
            """)
        }
    }

    @Test("deload_days must be a subset of training days; valid ones carry through")
    func deloadDays() async throws {
        let bench = makeExercise(name: "Bench Press")
        let tool = try await makeTool(exercises: [bench])
        let base = """
        "goal":"strength","weekly_frequency":3,"training_days":[2,4,6],
        "exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}]
        """

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: "{\"name\":\"P\",\(base),\"deload_days\":[3]}")
        }
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: "{\"name\":\"P\",\(base),\"deload_days\":[2,2]}")
        }

        let result = try await tool.call(argumentsJSON: "{\"name\":\"P\",\(base),\"deload_days\":[6,2]}")
        guard case .plan(let parameters)? = result.draft else {
            Issue.record("expected plan draft")
            return
        }
        #expect(parameters.deloadDays == [2, 6])
    }

    @Test("training_status override carries through; bad values throw")
    func trainingStatusOverride() async throws {
        let bench = makeExercise(name: "Bench Press")
        let tool = try await makeTool(exercises: [bench])
        let base = """
        "goal":"strength","weekly_frequency":3,
        "exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}]
        """

        let result = try await tool.call(argumentsJSON: "{\"name\":\"P\",\(base),\"training_status\":\"advanced\"}")
        guard case .plan(let parameters)? = result.draft else {
            Issue.record("expected plan draft")
            return
        }
        #expect(parameters.trainingStatus == .advanced)

        let noOverride = try await tool.call(argumentsJSON: "{\"name\":\"P\",\(base)}")
        guard case .plan(let plain)? = noOverride.draft else {
            Issue.record("expected plan draft")
            return
        }
        #expect(plain.trainingStatus == nil)

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: "{\"name\":\"P\",\(base),\"training_status\":\"elite\"}")
        }
    }

    @Test("day_splits can link templates, including template-only days and partial schedules")
    func templateSplits() async throws {
        let bench = makeExercise(name: "Bench Press")
        let squat = makeExercise(name: "Back Squat")
        let pushDay = makeTemplate(name: "Push Day", exercises: [bench])
        let tool = try await makeTool(exercises: [bench, squat], templates: [pushDay])

        let result = try await tool.call(argumentsJSON: """
        {"name":"Split","goal":"strength","weekly_frequency":3,"training_days":[2,4,6],
         "exercises":[
           {"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}},
           {"exercise_name":"Back Squat","estimated_1rm":{"value":140,"unit":"kg"}}
         ],
         "day_splits":[
           {"training_day":2,"exercise_names":["Bench Press"],"template_name":"push day"},
           {"training_day":4,"template_name":"Push Day"}
         ]}
        """)

        guard case .plan(let parameters)? = result.draft else {
            Issue.record("expected plan draft")
            return
        }
        // Partial schedule: day 6 unlisted is fine.
        #expect(parameters.trainingDays == [2, 4, 6])
        #expect(parameters.daySplits?.count == 2)
        #expect(parameters.daySplits?[0].templateID == pushDay.id)
        #expect(parameters.daySplits?[0].templateName == "Push Day")
        #expect(parameters.daySplits?[0].exerciseIDs == [bench.id])
        // Template-only day: no exercises required.
        #expect(parameters.daySplits?[1].exerciseIDs.isEmpty == true)
        #expect(parameters.daySplits?[1].templateID == pushDay.id)
    }

    @Test("Unknown template names and empty split entries throw")
    func templateSplitValidation() async throws {
        let bench = makeExercise(name: "Bench Press")
        let pushDay = makeTemplate(name: "Push Day", exercises: [bench])
        let tool = try await makeTool(exercises: [bench], templates: [pushDay])
        let base = """
        "goal":"strength","weekly_frequency":1,
        "exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}]
        """

        do {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P",\(base),"day_splits":[{"training_day":2,"template_name":"Pull Day"}]}
            """)
            Issue.record("expected throw")
        } catch let error as AIToolError {
            #expect(error.message.contains("Pull Day") || error.message.contains("list_templates"))
        }

        // Neither exercises nor template.
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P",\(base),"day_splits":[{"training_day":2}]}
            """)
        }
    }

    @Test("PR-sourced 1RMs are marked as personal-record provenance")
    func oneRMProvenance() async throws {
        let bench = makeExercise(name: "Bench Press")
        let squat = makeExercise(name: "Back Squat")
        let tool = try await makeTool(
            exercises: [bench, squat],
            records: [PersonalRecord(
                id: UUID(), exerciseId: bench.id, recordType: .estimatedOneRepMax,
                value: 110, setId: nil, achievedAt: Date()
            )]
        )

        let result = try await tool.call(argumentsJSON: """
        {"name":"P","goal":"strength","weekly_frequency":3,
         "exercises":[
           {"exercise_name":"Bench Press"},
           {"exercise_name":"Back Squat","estimated_1rm":{"value":140,"unit":"kg"}}
         ]}
        """)
        guard case .plan(let parameters)? = result.draft else {
            Issue.record("expected plan draft")
            return
        }
        #expect(parameters.exercises[0].oneRMFromPersonalRecord == true)
        #expect(parameters.exercises[1].oneRMFromPersonalRecord == false)
    }

    @Test("Old persisted drafts without the new fields still decode")
    func draftBackwardCompatibility() throws {
        let json = """
        {"name":"Old Plan","primaryGoal":"strength","weeklyFrequency":3,
         "startDate":700000000,
         "exercises":[{"exerciseID":"\(UUID().uuidString)","exerciseName":"Bench Press",
                       "primaryMuscleGroup":"chest","category":"barbell","estimated1RMKg":100}],
         "daySplits":[{"dayOfWeek":2,"exerciseIDs":[],"exerciseNames":[]}]}
        """
        let decoded = try JSONDecoder().decode(AIPlanParameters.self, from: Data(json.utf8))
        #expect(decoded.deloadDays == nil)
        #expect(decoded.trainingStatus == nil)
        #expect(decoded.daySplits?.first?.templateID == nil)
        #expect(decoded.exercises.first?.oneRMFromPersonalRecord == nil)
    }

    @Test("Validates frequency, weekdays, goal, and exercise names")
    func planValidation() async throws {
        let tool = try await makeTool(exercises: [makeExercise(name: "Bench Press")])

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":9,
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
        }
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":3,"training_days":[0,8],
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
        }
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"getting huge","weekly_frequency":3,
             "exercises":[{"exercise_name":"Bench Press"}]}
            """)
        }
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"P","goal":"strength","weekly_frequency":3,
             "exercises":[{"exercise_name":"Deadlift"}]}
            """)
        }
    }
}

@Suite("ProgressionPlanViewModel.createPlan")
@MainActor
struct CreatePlanTests {

    private func makeViewModel() -> (ProgressionPlanViewModel, InMemoryProgressionPlanRepository) {
        let planRepo = InMemoryProgressionPlanRepository()
        let workoutRepo = MockWorkoutRepositoryProgression()
        let vm = ProgressionPlanViewModel(
            progressionPlanRepository: planRepo,
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: workoutRepo),
            programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: workoutRepo),
            exerciseRepository: InMemoryExerciseRepository(),
            templateRepository: InMemoryTemplateRepository(),
            workoutRepository: workoutRepo,
            sessionExecutionService: SessionExecutionService(),
            adaptiveAdjustmentService: nil,
            coachingCommunicationService: CoachingCommunicationService()
        )
        return (vm, planRepo)
    }

    @Test("Creates an active plan with generated blocks and an end date")
    func createsActivePlan() async throws {
        let (vm, repo) = makeViewModel()
        let request = ProgressionPlanViewModel.PlanCreationRequest(
            name: "AI Strength Plan",
            trainingStatus: .intermediate,
            programType: .linear,
            primaryGoal: .strength,
            weeklyFrequency: 3,
            trainingDays: [2, 4, 6],
            exercises: [ProgressionTestHelpers.makeTestPlanExercise(current1RM: 100)],
            creationSource: .naturalLanguage
        )

        let plan = try await vm.createPlan(from: request)

        #expect(plan.status == .active)
        #expect(plan.creationSource == .naturalLanguage)
        #expect(!plan.blocks.isEmpty)
        #expect(plan.targetEndDate != nil)
        #expect(plan.trainingDays?.count == 3)
        #expect(vm.activePlan?.id == plan.id)
        let saved = try await repo.fetchActive()
        #expect(saved?.id == plan.id)
    }

    @Test("Empty names fall back to a default")
    func defaultName() async throws {
        let (vm, _) = makeViewModel()
        let plan = try await vm.createPlan(from: ProgressionPlanViewModel.PlanCreationRequest(
            name: "",
            trainingStatus: .beginner,
            programType: .linear,
            primaryGoal: .hypertrophy,
            weeklyFrequency: 3,
            exercises: [ProgressionTestHelpers.makeTestPlanExercise(current1RM: 80)],
            creationSource: .structuredFlow
        ))
        #expect(plan.name == "Training Plan")
    }
}

extension CreatePlanTests {
    @Test("Plan edit preview writes nothing; applying twice is idempotent and refreshes once")
    func editPreviewApply() async throws {
        let (vm, repo) = makeViewModel()
        let plan = try await vm.createPlan(from: .init(name: "Editable", trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, trainingDays: [2,4,6],
            exercises: [ProgressionTestHelpers.makeTestPlanExercise()], creationSource: .structuredFlow, durationWeeks: 8))
        var refreshes = 0; vm.onPlanChanged = { refreshes += 1 }
        let preview = try await vm.previewPlanEdit(.init(operation: .insertDeload, week: 5))
        #expect(try await repo.fetchActive()?.totalWeeks == plan.totalWeeks)
        let stored = try JSONDecoder().decode(PlanEditPreview.self, from: JSONEncoder().encode(preview))
        try await vm.applyPlanEdit(stored)
        try await vm.applyPlanEdit(stored)
        #expect(vm.activePlan?.totalWeeks == plan.totalWeeks + 1)
        #expect(vm.activePlan?.adjustments.filter { $0.id == stored.id }.count == 1)
        #expect(refreshes == 1)
    }

    @Test("Stale preview and changed Pro access prevent saving")
    func staleEditPreview() async throws {
        let (vm, repo) = makeViewModel()
        var plan = try await vm.createPlan(from: .init(name: "Editable", trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, exercises: [ProgressionTestHelpers.makeTestPlanExercise()], creationSource: .structuredFlow))
        let preview = try await vm.previewPlanEdit(.init(operation: .convertDeload, week: 5))
        plan.notes = "Changed after preview"; plan.updatedAt = Date()
        try await repo.save(plan)
        await #expect(throws: PlanEditError.self) { try await vm.applyPlanEdit(preview) }
        #expect(try await repo.fetchActive()?.notes == "Changed after preview")
        let fresh = try await vm.previewPlanEdit(.init(operation: .convertDeload, week: 5))
        vm.canEditPlan = { false }
        await #expect(throws: PlanEditError.self) { try await vm.applyPlanEdit(fresh) }
    }

    @Test("Grok plan edit returns an Apply card and does not mutate the active plan")
    func grokPlanEditTool() async throws {
        let (vm, repo) = makeViewModel()
        let plan = try await vm.createPlan(from: .init(name: "Editable", trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, exercises: [ProgressionTestHelpers.makeTestPlanExercise()], creationSource: .structuredFlow))
        let result = try await ProposePlanEditTool(viewModel: vm).call(argumentsJSON: #"{"operation":"insertDeload","week":5,"weeks":3}"#)
        guard case .action(let action) = result.draft, case .editPlan(let preview) = action.kind else { Issue.record("Expected edit preview card"); return }
        #expect(preview.request.weeks == 3)
        #expect(action.confirmLabel == "Apply changes")
        #expect(result.outputForModel.contains("confirmation_presented"))
        #expect(try await repo.fetchActive()?.totalWeeks == plan.totalWeeks)
    }

    @Test("A workout becoming active after preview is protected on Apply")
    func newlyActiveSession() async throws {
        let (vm, _) = makeViewModel()
        let plan = try await vm.createPlan(from: .init(name: "Editable", trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, exercises: [ProgressionTestHelpers.makeTestPlanExercise()], creationSource: .structuredFlow))
        let target = try #require(plan.blocks.flatMap(\.weeks).first { $0.absoluteWeekNumber == 5 }?.sessions.first)
        let preview = try await vm.previewPlanEdit(.init(operation: .convertDeload, week: 5))
        vm.protectedPlanSessions = { [target.id] }
        await #expect(throws: PlanEditError.self) { try await vm.applyPlanEdit(preview) }
    }

    @Test("Creation rejects unsupported duration")
    func invalidDuration() async {
        let (vm, _) = makeViewModel()
        await #expect(throws: PlanEditError.self) {
            try await vm.createPlan(from: .init(name: "Too short", trainingStatus: .beginner, programType: .block,
                primaryGoal: .strength, weeklyFrequency: 3, exercises: [], creationSource: .structuredFlow, durationWeeks: 2))
        }
    }
}

extension CreatePlanTests {
    @Test("A structural batch is one frozen preview; exact IDs survive Apply and retries")
    func structuralPreview() async throws {
        let (vm, repo) = makeViewModel()
        let plan = try await vm.createPlan(from: .init(name: "Batch", trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, trainingDays: [2,4,6], exercises: [ProgressionTestHelpers.makeTestPlanExercise()],
            creationSource: .structuredFlow, durationWeeks: 12))
        let source = try #require(plan.blocks.flatMap(\.weeks).first { $0.absoluteWeekNumber == 5 }?.sessions.first)
        let newDate = Calendar.current.date(byAdding: .day, value: 1, to: source.scheduledDate!)!
        let json = """
        {"operation":"batch","plan_id":"\(plan.id)","expected_version":"\(PlanEditingService.version(plan))","operations":[
          {"operation":"duplicateSession","session_id":"\(source.id)","new_date":"\(AIJSON.dateString(newDate))","label":"Extra"},
          {"operation":"updateSession","session_id":"\(source.id)","label":"Main"}]}
        """
        let result = try await ProposePlanEditTool(viewModel: vm).call(argumentsJSON: json)
        guard case .action(let action) = result.draft, case .editPlan(let preview) = action.kind else { Issue.record("Expected preview"); return }
        #expect(try await repo.fetchActive()?.blocks == plan.blocks)
        #expect(result.outputForModel.contains("resulting_schedule"))
        try await vm.applyPlanEdit(preview)
        let saved = try #require(try await repo.fetchActive())
        #expect(PlanScheduleSnapshot(saved) == preview.changeRecord?.after)
        #expect(saved.adjustments.filter { $0.id == preview.id }.count == 1)
        try await vm.applyPlanEdit(preview)
        #expect(try await repo.fetchActive()?.adjustments.count == saved.adjustments.count)
        #expect(vm.lastAppliedPlanEditContext?.contains("Extra") == true)
    }

    @Test("Structural tools require a fresh plan binding and reject unknown fields")
    func toolBinding() async throws {
        let (vm, _) = makeViewModel()
        let p = try await vm.createPlan(from: .init(name: "Bound", trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, exercises: [ProgressionTestHelpers.makeTestPlanExercise()], creationSource: .structuredFlow))
        let tool = ProposePlanEditTool(viewModel: vm)
        await #expect(throws: (any Error).self) { try await tool.call(argumentsJSON: #"{"operation":"setWeekSchedule","week":5,"schedule":[]}"#) }
        await #expect(throws: (any Error).self) { try await tool.call(argumentsJSON: """
        {"operation":"setWeekSchedule","plan_id":"\(p.id)","expected_version":"stale","week":5,"schedule":[]}
        """) }
        await #expect(throws: (any Error).self) { try await tool.call(argumentsJSON: #"{"operation":"convertDeload","week":5,"delete_everything":true}"#) }
        await #expect(throws: (any Error).self) { try await tool.call(argumentsJSON: #"{"operation":"rescheduleSession","new_date":"2026-02-30"}"#) }
        for binding in [#""plan_id":"not-a-uuid""#, #""plan_id":12"#, #""expected_version":42"#, #""expected_version":" ""#] {
            await #expect(throws: (any Error).self) { try await tool.call(argumentsJSON: "{\"operation\":\"convertDeload\",\"week\":5,\(binding)}") }
        }
    }

    @Test("Read tool exposes actual counts, rest weeks and bounded edit history")
    func structuralRead() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await vm.createPlan(from: .init(name: "Read", trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 3, exercises: [ProgressionTestHelpers.makeTestPlanExercise()], creationSource: .structuredFlow))
        let preview = try await vm.previewPlanEdit(.init(operation: .setWeekSchedule, week: 5, schedule: []))
        try await vm.applyPlanEdit(preview)
        let read = GetActivePlanTool(progressionPlanRepository: repo, userPreferencesService: UserPreferencesService(), viewModel: vm)
        let result = try await read.call(argumentsJSON: #"{"week":5}"#)
        let json = try JSONSerialization.jsonObject(with: Data(result.outputForModel.utf8)) as! [String: Any]
        let plan = json["active_plan"] as! [String: Any]
        #expect(plan["schedule_total"] as? Int == 0)
        let summary = (plan["week_summaries"] as! [[String: Any]]).first { $0["week"] as? Int == 5 }
        #expect(summary?["restWeek"] as? Bool == true)
        #expect(result.outputForModel.contains("removed_sessions"))
        #expect(!result.outputForModel.contains("normalExercises"))
    }
}

/// The assistant must be able to do what the plan screens do: every edit operation
/// and field, progression rules at creation, and a simulation before proposing.
@Suite("Assistant plan parity")
@MainActor
struct AssistantPlanParityTests {
    private func exercise(_ name: String, type: ExerciseType = .weightedReps) -> Exercise {
        Exercise(id: UUID(), name: name, primaryMuscleGroup: .chest, secondaryMuscleGroups: [], category: type == .weightedReps ? .barbell : .bodyweight,
            exerciseType: type, instructions: nil, isCustom: false, isArchived: false)
    }

    private func workout(_ exercise: Exercise, weight: Double, reps: Int) -> Workout {
        let date = Date().addingTimeInterval(-2 * 86_400)
        let sets = (0..<3).map { ExerciseSet(id: UUID(), order: $0, setType: .normal, weight: weight, reps: reps, durationSeconds: nil,
            distanceMeters: nil, rpe: nil, isCompleted: true, isPersonalRecord: false, completedAt: date) }
        return Workout(id: UUID(), name: "Push", startedAt: date, completedAt: date, notes: nil, templateId: nil,
            exercises: [WorkoutExercise(id: UUID(), exercise: exercise, order: 0, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: sets)])
    }

    private func proposalTool(_ exercises: [Exercise], workouts: [Workout] = []) async throws -> ProposeTrainingPlanTool {
        let exerciseRepo = InMemoryExerciseRepository()
        for item in exercises { _ = try await exerciseRepo.save(item) }
        let workoutRepo = MockWorkoutRepositoryProgression()
        workoutRepo.workouts = workouts
        return ProposeTrainingPlanTool(exerciseRepository: exerciseRepo, personalRecordRepository: InMemoryPersonalRecordRepository(),
            templateRepository: InMemoryTemplateRepository(), workoutRepository: workoutRepo)
    }

    private func viewModel() -> (ProgressionPlanViewModel, InMemoryProgressionPlanRepository) {
        let planRepo = InMemoryProgressionPlanRepository()
        let workoutRepo = MockWorkoutRepositoryProgression()
        let vm = ProgressionPlanViewModel(progressionPlanRepository: planRepo,
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: workoutRepo), programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: workoutRepo), exerciseRepository: InMemoryExerciseRepository(),
            templateRepository: InMemoryTemplateRepository(), workoutRepository: workoutRepo)
        return (vm, planRepo)
    }

    /// An eight-week, two-day plan with one bench exercise on a 6–10 rule from 80 kg.
    private func rulePlan(_ vm: ProgressionPlanViewModel) async throws -> ProgressionPlan {
        var bench = ProgressionTestHelpers.makeTestPlanExercise(name: "Bench Press", current1RM: 100)
        bench.progression = ProgressionRule(kind: .repsThenWeight, sets: 3, minReps: 6, maxReps: 10, incrementKg: 2.5, startWeightKg: 80)
        return try await vm.createPlan(from: .init(name: "Rules", trainingStatus: .advanced, programType: .linear, primaryGoal: .hypertrophy,
            weeklyFrequency: 2, trainingDays: [2, 5], exercises: [bench], creationSource: .structuredFlow, durationWeeks: 8,
            pace: .standard, deloadEveryWeeks: 0))
    }

    @Test("A pace gives every weighted exercise a rule: its own, a given start, or the latest workout")
    func paceBuildsRules() async throws {
        let bench = exercise("Bench Press"), squat = exercise("Back Squat"), curl = exercise("Barbell Curl")
        let tool = try await proposalTool([bench, squat, curl], workouts: [workout(bench, weight: 80, reps: 8)])
        let result = try await tool.call(argumentsJSON: """
        {"name":"Rules","goal":"hypertrophy","weekly_frequency":2,"training_days":[2,5],"pace":"standard","deload_every_weeks":6,
         "exercises":[
           {"exercise_name":"Bench Press"},
           {"exercise_name":"Back Squat","start_weight":{"value":100,"unit":"kg"},"start_reps":7},
           {"exercise_name":"Barbell Curl","rule":{"kind":"fixedSteps","sets":4,"max_reps":12,"increment_kg":1,"start_weight_kg":30,"misses_before_backoff":2}}
         ]}
        """)
        guard case .plan(let parameters)? = result.draft else { Issue.record("expected a plan draft"); return }
        #expect(parameters.pace == .standard)
        #expect(parameters.deloadEveryWeeks == 6)
        let rules = parameters.exercises.map(\.progression)
        #expect(rules[0]?.kind == .repsThenWeight)
        #expect(rules[0]?.startWeightKg == 80 && rules[0]?.startReps == 8)
        #expect(rules[1]?.startWeightKg == 100 && rules[1]?.startReps == 7)
        #expect(rules[2]?.kind == .fixedSteps && rules[2]?.minReps == 12 && rules[2]?.missesBeforeBackoff == 2)
        // A lift on a rule needs no 1RM from the model; an estimate is derived from its start.
        #expect((parameters.exercises[1].estimated1RMKg ?? 0) > 100)
        #expect(result.outputForModel.contains("progression_rules"))
    }

    @Test("Without a pace the proposal is the percentage wave, as before")
    func noPaceKeepsWave() async throws {
        let bench = exercise("Bench Press")
        let tool = try await proposalTool([bench])
        let result = try await tool.call(argumentsJSON: """
        {"name":"Wave","goal":"strength","weekly_frequency":3,"exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}]}
        """)
        guard case .plan(let parameters)? = result.draft else { Issue.record("expected a plan draft"); return }
        #expect(parameters.pace == nil)
        #expect(parameters.exercises[0].progression == nil)
    }

    @Test("A rule needs a start, and only weighted rep exercises take one")
    func ruleValidation() async throws {
        let bench = exercise("Bench Press"), pullUp = exercise("Pull-Up", type: .bodyweightReps)
        let tool = try await proposalTool([bench, pullUp])
        await #expect(throws: AIToolError.self) {
            try await tool.call(argumentsJSON: #"{"name":"P","goal":"hypertrophy","weekly_frequency":2,"pace":"standard","exercises":[{"exercise_name":"Bench Press"}]}"#)
        }
        await #expect(throws: AIToolError.self) {
            try await tool.call(argumentsJSON: #"{"name":"P","goal":"hypertrophy","weekly_frequency":2,"exercises":[{"exercise_name":"Pull-Up","start_weight":{"value":10,"unit":"kg"}}]}"#)
        }
        await #expect(throws: AIToolError.self) {
            try await tool.call(argumentsJSON: #"{"name":"P","goal":"hypertrophy","weekly_frequency":2,"deload_every_weeks":1,"exercises":[{"exercise_name":"Bench Press","estimated_1rm":{"value":100,"unit":"kg"}}]}"#)
        }
        await #expect(throws: AIToolError.self) {
            try await tool.call(argumentsJSON: #"{"name":"P","goal":"hypertrophy","weekly_frequency":2,"exercises":[{"exercise_name":"Bench Press","rule":{"kind":"repsThenWeight","sets":3,"min_reps":12,"max_reps":8,"increment_kg":2.5,"start_weight_kg":60}}]}"#)
        }
    }

    @Test("The assistant reads each exercise's rule and next target from the active plan")
    func activePlanReportsRules() async throws {
        let (vm, repo) = viewModel()
        _ = try await rulePlan(vm)
        let tool = GetActivePlanTool(progressionPlanRepository: repo, userPreferencesService: UserPreferencesService(), viewModel: vm)
        let output = try await tool.call(argumentsJSON: #"{"limit":1}"#).outputForModel
        #expect(output.contains(#""progression_summary":"3 × 6–10."#) || output.contains("3 × 6–10"))
        #expect(output.contains(#""next_target""#))
        #expect(output.contains(#""increment_kg":2.5"#))
        #expect(output.contains(#""pace":"standard""#))
    }

    @Test("The assistant changes a rule and renames the plan in one Apply card")
    func editsRuleAndName() async throws {
        let (vm, repo) = viewModel()
        let plan = try await rulePlan(vm)
        let exerciseID = plan.exercises[0].exerciseId
        let json = """
        {"plan_id":"\(plan.id.uuidString)","expected_version":"\(PlanEditingService.version(plan))","operation":"batch","operations":[
          {"operation":"setProgression","exercise_id":"\(exerciseID.uuidString)",
           "progression":{"kind":"fixedSteps","sets":5,"max_reps":5,"increment_kg":2.5,"start_weight_kg":90,"misses_before_backoff":3}},
          {"operation":"renamePlan","label":"Strength block"}]}
        """
        let result = try await ProposePlanEditTool(viewModel: vm).call(argumentsJSON: json)
        guard case .action(let action) = result.draft, case .editPlan(let preview) = action.kind else { Issue.record("expected an Apply card"); return }
        #expect(action.summaryLines.contains { $0.contains("Bench Press: 5 × 5") })
        #expect(try await repo.fetchActive()?.name == "Rules", "A preview writes nothing")

        try await vm.applyPlanEdit(preview)
        let saved = try #require(try await repo.fetchActive())
        #expect(saved.name == "Strength block")
        #expect(saved.exercises[0].progression?.kind == .fixedSteps)
        let targets = saved.blocks.flatMap(\.weeks).flatMap(\.sessions).sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
            .prefix(3).map { "\($0.plannedExercises[0].targetWeight)x\($0.plannedExercises[0].targetReps)" }
        #expect(targets == ["90.0x5", "92.5x5", "95.0x5"])
    }

    @Test("An invalid rule from the assistant is refused before any preview")
    func refusesInvalidRule() async throws {
        let (vm, _) = viewModel()
        let plan = try await rulePlan(vm)
        let json = """
        {"plan_id":"\(plan.id.uuidString)","expected_version":"\(PlanEditingService.version(plan))","operation":"setProgression",
         "exercise_id":"\(plan.exercises[0].exerciseId.uuidString)","progression":{"kind":"fixedSteps","sets":5,"max_reps":5,"increment_kg":0,"start_weight_kg":90}}
        """
        await #expect(throws: AIToolError.self) { try await ProposePlanEditTool(viewModel: vm).call(argumentsJSON: json) }
    }

    @Test("A rule can be simulated before it is proposed, from its start or from the plan's current target")
    func simulatesRule() async throws {
        let (vm, repo) = viewModel()
        let plan = try await rulePlan(vm)
        let tool = PreviewProgressionTool(progressionPlanRepository: repo)
        let fresh = try await tool.call(argumentsJSON: #"{"rule":{"kind":"fixedSteps","sets":5,"max_reps":5,"increment_kg":5,"start_weight_kg":100},"sessions":3}"#).outputForModel
        #expect(fresh.contains(#""weight_kg":110"#))
        #expect(fresh.contains("Nothing was changed"))
        let continued = try await tool.call(argumentsJSON: """
        {"rule":{"kind":"fixedSteps","sets":5,"max_reps":8,"increment_kg":5,"start_weight_kg":40},"sessions":2,"exercise_id":"\(plan.exercises[0].exerciseId.uuidString)"}
        """).outputForModel
        // The plan's bench stands at 80 kg, so the simulation starts there, not at the rule's 40.
        #expect(continued.contains(#""weight_kg":80"#) && continued.contains(#""weight_kg":85"#))
        #expect(try await repo.fetchActive() == plan)
    }

    @Test("Every plan edit operation and field the app has is offered to the assistant")
    func editToolCoversTheEngine() throws {
        let (vm, _) = viewModel()
        guard case .object(let schema) = ProposePlanEditTool(viewModel: vm).parametersSchema, case .object(let properties)? = schema["properties"],
              case .object(let operation)? = properties["operation"], case .array(let offered)? = operation["enum"] else {
            Issue.record("unexpected schema shape"); return
        }
        let offeredOperations = Set(offered.compactMap { value -> String? in if case .string(let name) = value { return name } else { return nil } })
        #expect(offeredOperations == Set(PlanEditRequest.Operation.allCases.map(\.rawValue)))

        // Field names as the tool spells them: snake_case, with two shortened names.
        let renamed = ["deloadWeightPercentage": "deload_weight_percent", "deloadRestPercentage": "deload_rest_percent"]
        func toolName(_ field: String) -> String {
            if let name = renamed[field] { return name }
            let normalised = field.replacingOccurrences(of: "IDs", with: "Ids").replacingOccurrences(of: "ID", with: "Id").replacingOccurrences(of: "RPE", with: "Rpe")
            return normalised.reduce(into: "") { result, character in
                if character.isUppercase { result += "_" + character.lowercased() } else { result.append(character) }
            }
        }
        let fields = Mirror(reflecting: PlanEditRequest(operation: .batch)).children.compactMap(\.label)
        #expect(fields.count >= 30)
        let missing = fields.map(toolName).filter { properties[$0] == nil }
        #expect(missing.isEmpty, "Plan edit fields the assistant cannot set: \(missing)")
    }
}
