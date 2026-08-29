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
