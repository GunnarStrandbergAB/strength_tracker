import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("propose_training_plan tool")
@MainActor
struct ProposeTrainingPlanToolTests {

    private func makeTool(
        exercises: [Exercise],
        records: [PersonalRecord] = []
    ) async throws -> ProposeTrainingPlanTool {
        let exerciseRepo = InMemoryExerciseRepository()
        for exercise in exercises { _ = try await exerciseRepo.save(exercise) }
        let recordRepo = InMemoryPersonalRecordRepository()
        for record in records { _ = try await recordRepo.save(record) }
        return ProposeTrainingPlanTool(
            exerciseRepository: exerciseRepo,
            personalRecordRepository: recordRepo
        )
    }

    private func makeExercise(name: String) -> Exercise {
        Exercise(
            id: UUID(), name: name, primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [], category: .barbell,
            exerciseType: .weightedReps, instructions: nil, isCustom: false, isArchived: false
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
