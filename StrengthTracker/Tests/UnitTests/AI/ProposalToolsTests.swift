import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AI proposal tools")
@MainActor
struct ProposalToolsTests {

    private func makeExercise(
        name: String,
        muscle: MuscleGroup = .chest,
        type: ExerciseType = .weightedReps
    ) -> Exercise {
        Exercise(
            id: UUID(), name: name, primaryMuscleGroup: muscle,
            secondaryMuscleGroups: [], category: .barbell,
            exerciseType: type, instructions: nil, isCustom: false, isArchived: false
        )
    }

    // MARK: - propose_exercise

    @Test("Builds an exercise draft without writing")
    func proposeExercise() async throws {
        let repo = InMemoryExerciseRepository()
        let tool = ProposeExerciseTool(exerciseRepository: repo)

        let result = try await tool.call(argumentsJSON: """
        {"name":"Machine Chest Press","primary_muscle_group":"chest",
         "secondary_muscle_groups":["triceps"],"category":"machine",
         "exercise_type":"weightedReps","equipment_brand":"Hammer Strength",
         "loading_type":"plateLoaded"}
        """)

        guard case .exercise(let exercise)? = result.draft else {
            Issue.record("expected exercise draft")
            return
        }
        #expect(exercise.name == "Machine Chest Press")
        #expect(exercise.isCustom)
        #expect(exercise.equipmentBrand == "Hammer Strength")
        #expect(exercise.loadingType == .plateLoaded)
        #expect(result.outputForModel.contains("proposal_presented"))

        // Nothing written to the repository.
        #expect(try await repo.fetchAll().isEmpty)
    }

    @Test("Duplicate names are rejected with a helpful error")
    func proposeExerciseDuplicate() async throws {
        let repo = InMemoryExerciseRepository()
        _ = try await repo.save(makeExercise(name: "Bench Press"))
        let tool = ProposeExerciseTool(exerciseRepository: repo)

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"bench press","primary_muscle_group":"chest",
             "category":"barbell","exercise_type":"weightedReps"}
            """)
        }
    }

    @Test("Invalid enum values name the field and list valid options")
    func proposeExerciseBadEnum() async throws {
        let tool = ProposeExerciseTool(exerciseRepository: InMemoryExerciseRepository())
        do {
            _ = try await tool.call(argumentsJSON: """
            {"name":"New Move","primary_muscle_group":"pecs",
             "category":"barbell","exercise_type":"weightedReps"}
            """)
            Issue.record("expected throw")
        } catch let error as AIToolError {
            #expect(error.message.contains("primary_muscle_group"))
            #expect(error.message.contains("chest"))
        }
    }

    // MARK: - propose_template

    private func makeTemplateTool(
        exercises: [Exercise]
    ) async throws -> ProposeTemplateTool {
        let repo = InMemoryExerciseRepository()
        for exercise in exercises { _ = try await repo.save(exercise) }
        return ProposeTemplateTool(
            exerciseRepository: repo,
            userPreferencesService: UserPreferencesService()
        )
    }

    @Test("Builds a template draft with resolved exercises and kg-normalized weights")
    func proposeTemplate() async throws {
        let squat = makeExercise(name: "Back Squat", muscle: .quadriceps)
        let lunge = makeExercise(name: "Walking Lunge", muscle: .quadriceps)
        let tool = try await makeTemplateTool(exercises: [squat, lunge])

        let result = try await tool.call(argumentsJSON: """
        {"name":"Quad Focus","notes":"Leg day",
         "exercises":[
           {"exercise_name":"back squat","target_sets":5,"target_reps":5,
            "target_weight":{"value":220,"unit":"lbs"},"rest_seconds":180},
           {"exercise_name":"Walking Lunge","target_reps":12}
         ]}
        """)

        guard case .template(let template)? = result.draft else {
            Issue.record("expected template draft")
            return
        }
        #expect(template.name == "Quad Focus")
        #expect(template.isCustom)
        #expect(template.exercises.count == 2)

        let first = template.exercises[0]
        #expect(first.exercise.id == squat.id)
        #expect(first.targetSets == 5)
        #expect(first.targetReps == 5)
        #expect(abs((first.targetWeight ?? 0) - 99.79) < 0.1)   // 220 lbs → kg
        #expect(first.restTimerSeconds == 180)

        let second = template.exercises[1]
        #expect(second.targetSets == 3)   // default
        #expect(second.targetReps == 12)
        #expect(second.order == 1)
    }

    @Test("Unknown exercise names fail with suggestions and produce no draft")
    func proposeTemplateUnknownExercise() async throws {
        let tool = try await makeTemplateTool(exercises: [makeExercise(name: "Back Squat")])
        do {
            _ = try await tool.call(argumentsJSON: """
            {"name":"Legs","exercises":[{"exercise_name":"Front Squat"}]}
            """)
            Issue.record("expected throw")
        } catch let error as AIToolError {
            #expect(error.message.contains("Back Squat"))
        }
    }

    @Test("Bad weight units and empty exercise lists are rejected")
    func proposeTemplateValidation() async throws {
        let tool = try await makeTemplateTool(exercises: [makeExercise(name: "Back Squat")])

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: "{\"name\":\"Legs\",\"exercises\":[]}")
        }
        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: """
            {"name":"Legs","exercises":[{"exercise_name":"Back Squat",
             "target_weight":{"value":100,"unit":"stone"}}]}
            """)
        }
    }
}
