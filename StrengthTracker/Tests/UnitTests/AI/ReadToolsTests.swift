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

    // MARK: - list_templates

    private func makeTemplate(name: String, exerciseNames: [String], isCustom: Bool = true) -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID(), name: name, notes: nil, sortOrder: 0,
            lastUsedAt: nil, timesUsed: 0,
            exercises: exerciseNames.enumerated().map { index, exerciseName in
                TemplateExercise(
                    id: UUID(), exercise: makeExercise(name: exerciseName), order: index,
                    supersetGroup: nil, notes: nil, restTimerSeconds: nil,
                    targetSets: 3, targetReps: 10, targetWeight: 0,
                    targetDurationSeconds: nil, targetDistanceMeters: nil
                )
            },
            isCustom: isCustom
        )
    }

    @Test("list_templates lists only custom templates with their exercises")
    func listTemplates() async throws {
        let repo = InMemoryTemplateRepository()
        _ = try await repo.save(makeTemplate(name: "Push Day", exerciseNames: ["Bench Press", "Overhead Press"]))
        _ = try await repo.save(makeTemplate(name: "Library Thing", exerciseNames: ["Squat"], isCustom: false))

        let tool = ListTemplatesTool(templateRepository: repo)
        let output = try json(try await tool.call(argumentsJSON: "{}"))

        #expect(output["count"] == .number(1))
        guard case .array(let templates)? = output["templates"],
              case .object(let template)? = templates.first else {
            Issue.record("unexpected shape: \(output)")
            return
        }
        #expect(template["name"] == .string("Push Day"))
        #expect(template["exercises"] == .array([.string("Bench Press"), .string("Overhead Press")]))
    }

    @Test("list_templates query filters by name")
    func listTemplatesQuery() async throws {
        let repo = InMemoryTemplateRepository()
        _ = try await repo.save(makeTemplate(name: "Push Day", exerciseNames: ["Bench Press"]))
        _ = try await repo.save(makeTemplate(name: "Pull Day", exerciseNames: ["Row"]))

        let tool = ListTemplatesTool(templateRepository: repo)
        let output = try json(try await tool.call(argumentsJSON: "{\"query\":\"push\"}"))
        #expect(output["count"] == .number(1))
    }

    @Test("TemplateNameResolver suggests close names on a miss")
    func templateResolverSuggestions() {
        let templates = [
            makeTemplate(name: "Push Day", exerciseNames: []),
            makeTemplate(name: "Pull Day", exerciseNames: [])
        ]
        #expect(throws: AIToolError.self) {
            _ = try TemplateNameResolver.resolve(name: "Push", in: templates)
        }
        let resolved = try? TemplateNameResolver.resolve(name: "push day", in: templates)
        #expect(resolved?.name == "Push Day")
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

extension ReadToolsTests {
    @Test("History pages retain source IDs and two-decimal weights")
    func structuredHistoryPagination() async throws {
        let repo = MockWorkoutRepositoryProgression()
        let exercise = makeExercise(name: "Bench")
        repo.workouts = (0..<3).map { makeWorkout(name: "Day \($0)", daysAgo: $0 + 1, exercise: exercise, sets: [(100.25, 8)]) }
        let tool = GetTrainingHistoryTool(workoutRepository: repo, exerciseRepository: InMemoryExerciseRepository(), userPreferencesService: UserPreferencesService())
        let first = try json(try await tool.call(argumentsJSON: #"{"last_n":1}"#))
        let second = try json(try await tool.call(argumentsJSON: #"{"last_n":1,"offset":1}"#))
        #expect(first["next_offset"] == .number(1))
        #expect(first["workouts"] != second["workouts"])
        guard case .array(let entries)? = first["workouts"], case .object(let workout) = entries[0],
              case .array(let exercises)? = workout["ex"], case .object(let entry) = exercises[0],
              case .array(let sets)? = entry["set_data"], case .object(let set) = sets[0] else { Issue.record("Missing structured source data"); return }
        #expect(workout["id"] == .string(repo.workouts[0].id.uuidString))
        #expect(entry["exercise_id"] == .string(exercise.id.uuidString))
        #expect(set["weight_kg"] == .number(100.25))
        #expect(set["id"] != nil)
        await #expect(throws: AIToolError.self) { try await tool.call(argumentsJSON: #"{"offset":-1}"#) }
    }

    @Test("Detailed quality and load match their app calculators before pagination")
    func detailedAnalyticsParity() async throws {
        let repo = MockWorkoutRepositoryProgression(), catalog = InMemoryExerciseRepository(), plans = InMemoryProgressionPlanRepository()
        let prefs = UserPreferencesService(), health = MockHealthKitService()
        let body = BodyWeightProvider(healthKitService: health, userPreferencesService: prefs)
        let exercise = makeExercise(name: "Bench")
        _ = try await catalog.save(exercise)
        repo.workouts = (0..<12).map { makeWorkout(name: "Day \($0)", daysAgo: ($0 + 1) * 3, exercise: exercise, sets: [(100.25, 8), (100.25, 8), (100.25, 8)]) }
        let quality = WorkoutQualityScoreService(workoutRepository: repo, muscleBalanceService: MuscleBalanceService(), healthKitService: health, userPreferencesService: prefs, bodyWeightProvider: body)
        let analytics = WorkoutAnalyticsService(analyticsRepository: MockAnalyticsRepository(), workoutRepository: repo, exerciseRepository: catalog,
            vectorizer: WorkoutVectorizer(), searchService: VectorSearchService(), plateauService: PlateauDetectionService(), muscleBalanceService: MuscleBalanceService(), recommendationService: ExerciseRecommendationService())
        func tool(_ kind: DetailedAnalyticsTool.Kind) -> DetailedAnalyticsTool {
            DetailedAnalyticsTool(kind: kind, workouts: repo, exercises: catalog, plans: plans, analytics: analytics, quality: quality,
                planAnalytics: PlanAnalyticsService(workoutRepository: repo), bodyWeight: body)
        }
        let scored = try json(try await tool(.quality).call(argumentsJSON: #"{"limit":1}"#))
        guard case .object(let aggregate)? = scored["aggregate"] else { Issue.record("Missing aggregate"); return }
        #expect(aggregate["ewmaOverall"] == .number(quality.computeAggregateScore(workouts: repo.workouts).ewmaOverall))
        let load = try json(try await tool(.load).call(argumentsJSON: #"{"limit":1}"#))
        let bests = AnalyticsCalculations.buildBestE1RMMap(from: repo.workouts, bodyWeightKg: body.current)
        let expected = TrainingLoadService.computeTrainingLoad(bodyWeightKg: body.current, workouts: repo.workouts, bestE1RM: bests)
        #expect(load["acwr"] == expected.map { .number($0.acwr) })
        let progress = try json(try await tool(.progress).call(argumentsJSON: "{\"exercise_id\":\"\(exercise.id)\",\"limit\":1}"))
        #expect(progress["exercise_id"] == .string(exercise.id.uuidString))
        guard case .object(let page)? = progress["history"] else { Issue.record("Missing history page"); return }
        #expect(page["total"] == .number(12))
        #expect(page["next_offset"] == .number(1))
        for kind in [DetailedAnalyticsTool.Kind.coverage, .patterns, .recovery, .plan] {
            let output = try json(try await tool(kind).call(argumentsJSON: "{}"))
            #expect(output["source"] != nil)
            #expect(output["status"] != nil)
        }
    }
}
