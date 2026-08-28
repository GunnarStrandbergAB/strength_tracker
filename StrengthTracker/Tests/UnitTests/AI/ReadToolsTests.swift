import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AI read tools")
@MainActor
struct ReadToolsTests {

    // MARK: - Fixtures

    private func makeExercise(
        name: String,
        muscle: MuscleGroup = .chest,
        category: ExerciseCategory = .barbell,
        isCustom: Bool = false,
        isArchived: Bool = false
    ) -> Exercise {
        Exercise(
            id: UUID(),
            name: name,
            primaryMuscleGroup: muscle,
            secondaryMuscleGroups: [],
            category: category,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: isCustom,
            isArchived: isArchived
        )
    }

    private func makeWorkout(
        name: String,
        daysAgo: Int,
        exercise: Exercise,
        sets: [(weight: Double, reps: Int)],
        completed: Bool = true
    ) -> Workout {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let exerciseSets = sets.enumerated().map { index, set in
            ExerciseSet(
                id: UUID(), order: index + 1, setType: .normal,
                weight: set.weight, reps: set.reps,
                durationSeconds: nil, distanceMeters: nil, rpe: nil,
                isCompleted: true, isPersonalRecord: false, completedAt: start
            )
        }
        return Workout(
            id: UUID(), name: name, startedAt: start,
            completedAt: completed ? start.addingTimeInterval(3600) : nil,
            notes: nil, templateId: nil,
            exercises: [WorkoutExercise(
                id: UUID(), exercise: exercise, order: 1,
                supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: exerciseSets
            )]
        )
    }

    private func json(_ result: AIToolResult) throws -> [String: JSONValue] {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(result.outputForModel.utf8))
        guard case .object(let object) = decoded else {
            throw AIToolError("output was not a JSON object")
        }
        return object
    }

    // MARK: - ExerciseNameResolver

    @Test("Resolves names case-insensitively")
    func resolverExactMatch() throws {
        let exercises = [makeExercise(name: "Bench Press"), makeExercise(name: "Squat")]
        let resolved = try ExerciseNameResolver.resolve(name: "bench press", in: exercises)
        #expect(resolved.name == "Bench Press")
    }

    @Test("Miss lists closest matches in the error")
    func resolverSuggestions() {
        let exercises = [
            makeExercise(name: "Bench Press"),
            makeExercise(name: "Incline Bench Press"),
            makeExercise(name: "Squat")
        ]
        do {
            _ = try ExerciseNameResolver.resolve(name: "bench", in: exercises)
            Issue.record("expected a throw")
        } catch let error as AIToolError {
            #expect(error.message.contains("Bench Press"))
            #expect(!error.message.contains("Squat"))
        } catch {
            Issue.record("unexpected error type")
        }
    }

    // MARK: - list_exercises

    @Test("Lists catalog lines and filters archived")
    func listExercises() async throws {
        let repo = InMemoryExerciseRepository()
        _ = try await repo.save(makeExercise(name: "Bench Press"))
        _ = try await repo.save(makeExercise(name: "Leg Press", muscle: .quadriceps, category: .machine, isCustom: true))
        _ = try await repo.save(makeExercise(name: "Old Move", isArchived: true))

        let tool = ListExercisesTool(exerciseRepository: repo)
        let output = try json(try await tool.call(argumentsJSON: "{}"))

        #expect(output["count"] == .number(2))
        guard case .array(let lines)? = output["exercises"] else {
            Issue.record("missing exercises")
            return
        }
        #expect(lines.contains(.string("Bench Press|chest|barbell|weightedReps")))
        #expect(lines.contains(.string("Leg Press|quadriceps|machine|weightedReps|custom")))
    }

    @Test("Filters by muscle group and rejects bad values with the valid list")
    func listExercisesMuscleFilter() async throws {
        let repo = InMemoryExerciseRepository()
        _ = try await repo.save(makeExercise(name: "Bench Press"))
        _ = try await repo.save(makeExercise(name: "Squat", muscle: .quadriceps))
        let tool = ListExercisesTool(exerciseRepository: repo)

        let filtered = try json(try await tool.call(argumentsJSON: "{\"muscle_group\":\"quadriceps\"}"))
        #expect(filtered["count"] == .number(1))

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: "{\"muscle_group\":\"legs\"}")
        }
    }

    // MARK: - get_training_history

    private func makeHistoryTool(
        workouts: [Workout], exercises: [Exercise]
    ) async throws -> GetTrainingHistoryTool {
        let workoutRepo = InMemoryWorkoutRepository()
        for workout in workouts { _ = try await workoutRepo.save(workout) }
        let exerciseRepo = InMemoryExerciseRepository()
        for exercise in exercises { _ = try await exerciseRepo.save(exercise) }
        return GetTrainingHistoryTool(
            workoutRepository: workoutRepo,
            exerciseRepository: exerciseRepo,
            userPreferencesService: UserPreferencesService()
        )
    }

    @Test("Summarizes completed workouts with compact set strings")
    func historySummaries() async throws {
        let bench = makeExercise(name: "Bench Press")
        let tool = try await makeHistoryTool(
            workouts: [
                makeWorkout(name: "Push Day", daysAgo: 2, exercise: bench,
                            sets: [(100, 5), (102.5, 3)]),
                makeWorkout(name: "Aborted", daysAgo: 1, exercise: bench,
                            sets: [(60, 10)], completed: false)
            ],
            exercises: [bench]
        )

        let output = try json(try await tool.call(argumentsJSON: "{}"))
        #expect(output["count"] == .number(1))
        #expect(output["unit"] == .string("kg"))

        guard case .array(let workouts)? = output["workouts"],
              case .object(let workout)? = workouts.first,
              case .array(let exercises)? = workout["ex"],
              case .object(let exercise)? = exercises.first else {
            Issue.record("unexpected shape: \(output)")
            return
        }
        #expect(workout["name"] == .string("Push Day"))
        #expect(exercise["n"] == .string("Bench Press"))
        #expect(exercise["sets"] == .string("100x5,102.5x3"))
    }

    @Test("exercise_name filters workouts; unknown names throw with suggestions")
    func historyExerciseFilter() async throws {
        let bench = makeExercise(name: "Bench Press")
        let squat = makeExercise(name: "Back Squat", muscle: .quadriceps)
        let tool = try await makeHistoryTool(
            workouts: [
                makeWorkout(name: "Push", daysAgo: 3, exercise: bench, sets: [(100, 5)]),
                makeWorkout(name: "Legs", daysAgo: 1, exercise: squat, sets: [(140, 5)])
            ],
            exercises: [bench, squat]
        )

        let output = try json(try await tool.call(argumentsJSON: "{\"exercise_name\":\"back squat\"}"))
        #expect(output["count"] == .number(1))

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: "{\"exercise_name\":\"Deadlift\"}")
        }
    }

    @Test("last_n caps results and flags truncation")
    func historyTruncation() async throws {
        let bench = makeExercise(name: "Bench Press")
        let workouts = (1...5).map { day in
            makeWorkout(name: "W\(day)", daysAgo: day, exercise: bench, sets: [(100, 5)])
        }
        let tool = try await makeHistoryTool(workouts: workouts, exercises: [bench])

        let output = try json(try await tool.call(argumentsJSON: "{\"last_n\":2}"))
        #expect(output["count"] == .number(2))
        #expect(output["truncated"] == .bool(true))

        guard case .array(let items)? = output["workouts"],
              case .object(let newest)? = items.first else {
            Issue.record("unexpected shape")
            return
        }
        #expect(newest["name"] == .string("W1"))
    }

    // MARK: - get_personal_records

    @Test("Returns best records per type for a named exercise")
    func personalRecordsForExercise() async throws {
        let bench = makeExercise(name: "Bench Press")
        let exerciseRepo = InMemoryExerciseRepository()
        _ = try await exerciseRepo.save(bench)
        let recordRepo = InMemoryPersonalRecordRepository()
        _ = try await recordRepo.save(PersonalRecord(
            id: UUID(), exerciseId: bench.id, recordType: .estimatedOneRepMax,
            value: 120, setId: nil, achievedAt: Date()
        ))
        _ = try await recordRepo.save(PersonalRecord(
            id: UUID(), exerciseId: bench.id, recordType: .estimatedOneRepMax,
            value: 125.4, setId: nil, achievedAt: Date()
        ))

        let tool = GetPersonalRecordsTool(
            personalRecordRepository: recordRepo, exerciseRepository: exerciseRepo
        )
        let output = try json(try await tool.call(argumentsJSON: "{\"exercise_name\":\"Bench Press\"}"))

        guard case .array(let records)? = output["records"],
              case .object(let record)? = records.first else {
            Issue.record("unexpected shape")
            return
        }
        #expect(records.count == 1)
        #expect(record["value"] == .number(125.4))
        #expect(record["type"] == .string("estimatedOneRepMax"))
    }

    @Test("Without a name returns one headline record per exercise")
    func personalRecordsOverview() async throws {
        let bench = makeExercise(name: "Bench Press")
        let squat = makeExercise(name: "Back Squat", muscle: .quadriceps)
        let noRecords = makeExercise(name: "Cable Fly", category: .cable)
        let exerciseRepo = InMemoryExerciseRepository()
        for exercise in [bench, squat, noRecords] { _ = try await exerciseRepo.save(exercise) }

        let recordRepo = InMemoryPersonalRecordRepository()
        _ = try await recordRepo.save(PersonalRecord(
            id: UUID(), exerciseId: bench.id, recordType: .estimatedOneRepMax,
            value: 120, setId: nil, achievedAt: Date()
        ))
        _ = try await recordRepo.save(PersonalRecord(
            id: UUID(), exerciseId: squat.id, recordType: .maxWeight,
            value: 150, setId: nil, achievedAt: Date()
        ))

        let tool = GetPersonalRecordsTool(
            personalRecordRepository: recordRepo, exerciseRepository: exerciseRepo
        )
        let output = try json(try await tool.call(argumentsJSON: "{}"))
        #expect(output["count"] == .number(2))
    }

    // MARK: - get_active_plan

    @Test("No active plan returns null")
    func noActivePlan() async throws {
        let tool = GetActivePlanTool(
            progressionPlanRepository: InMemoryProgressionPlanRepository(),
            userPreferencesService: UserPreferencesService()
        )
        let output = try json(try await tool.call(argumentsJSON: "{}"))
        #expect(output["active_plan"] == .null)
    }

    @Test("Active plan summarizes goal, frequency, and exercises")
    func activePlanSummary() async throws {
        let repo = InMemoryProgressionPlanRepository()
        let bench = makeExercise(name: "Bench Press")
        let plan = ProgressionPlan(
            name: "Strength Block",
            status: .active,
            trainingStatus: .intermediate,
            programType: .linear,
            primaryGoal: .strength,
            weeklyFrequency: 4,
            exercises: [PlanExercise(
                exerciseId: bench.id,
                exerciseName: "Bench Press",
                primaryMuscleGroup: .chest,
                category: .barbell,
                estimated1RM: 120,
                oneRMSource: .estimated,
                current1RM: 120,
                isCompound: true,
                order: 1
            )]
        )
        _ = try await repo.save(plan)

        let tool = GetActivePlanTool(
            progressionPlanRepository: repo,
            userPreferencesService: UserPreferencesService()
        )
        let output = try json(try await tool.call(argumentsJSON: "{}"))

        guard case .object(let planJSON)? = output["active_plan"] else {
            Issue.record("expected plan object")
            return
        }
        #expect(planJSON["name"] == .string("Strength Block"))
        #expect(planJSON["goal"] == .string("strength"))
        #expect(planJSON["weekly_frequency"] == .number(4))
    }
}
