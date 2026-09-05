import Testing
import Foundation
@testable import StrengthTrackerShared

/// End-to-end over the real editors: tools → WorkoutEditorResolver →
/// ActiveWorkoutEditor (WorkoutViewModel + coordinator with spies) or
/// HistoryWorkoutEditor (HistoryViewModel) → in-memory repository.
@Suite("AI workout edit tools", .serialized)
@MainActor
struct WorkoutEditToolsTests {

    // MARK: - Stack

    @MainActor
    final class Stack {
        let repo = InMemoryWorkoutRepository()
        let exerciseRepo = InMemoryExerciseRepository()
        let prefs: UserPreferencesService
        let vm: WorkoutViewModel
        let timer = SpyRestTimer()
        let widget = SpyWidgetPublisher()
        let coordinator: WorkoutSessionCoordinator
        let resolver: WorkoutEditorResolver
        var absorbed: [Workout] = []

        init(prefs: UserPreferencesService) {
            self.prefs = prefs
            vm = WorkoutViewModel(
                workoutRepository: repo,
                templateRepository: InMemoryTemplateRepository(),
                healthKitService: NoOpHealthKitService(),
                userPreferencesService: prefs
            )
            coordinator = WorkoutSessionCoordinator(
                workoutViewModel: vm, restTimer: timer, widgetPublisher: widget,
                preferences: prefs, publishSynchronously: true
            )
            let repo = self.repo
            var absorbedRef: (Workout) -> Void = { _ in }
            resolver = WorkoutEditorResolver(
                workoutViewModel: vm,
                coordinator: coordinator,
                workoutRepository: repo,
                makeHistoryViewModel: { HistoryViewModel(workoutRepository: repo, userPreferencesService: prefs) },
                onHistoryWorkoutChanged: { absorbedRef($0) }
            )
            absorbedRef = { [weak self] in self?.absorbed.append($0) }
        }

        func exercise(_ name: String) async throws -> Exercise {
            let exercise = Exercise(
                id: UUID(), name: name, primaryMuscleGroup: .chest, secondaryMuscleGroups: [],
                category: .barbell, exerciseType: .weightedReps, instructions: nil,
                isCustom: false, isArchived: false
            )
            return try await exerciseRepo.save(exercise)
        }

        /// Active workout with one exercise and `sets` planned (weight/reps prefilled).
        @discardableResult
        func startActive(exerciseName: String = "Bench Press", sets: Int = 3, weightKg: Double? = 80, reps: Int? = 8) async throws -> WorkoutExercise {
            let exercise = try await self.exercise(exerciseName)
            try await coordinator.start(.init(name: "Push Day"))
            let built = (0..<sets).map { SetPrefill(weightKg: weightKg, reps: reps).makeSet(order: $0 + 1) }
            let added = await vm.addExercise(exercise, sets: built)
            return try #require(added)
        }

        /// Completed workout `daysAgo` with one exercise of `sets` completed sets.
        @discardableResult
        func seedHistory(name: String = "Legs", daysAgo: Int = 1, exerciseName: String = "Squat", sets: Int = 3, hour: Int = 10) async throws -> Workout {
            let exercise = try await self.exercise(exerciseName)
            var start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
            start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: start)!
            let completedAt = start.addingTimeInterval(3600)
            let built = (0..<sets).map { i in
                ExerciseSet(
                    id: UUID(), order: i + 1, setType: .normal, weight: 100, reps: 5,
                    durationSeconds: nil, distanceMeters: nil, rpe: 8,
                    isCompleted: true, isPersonalRecord: false, completedAt: completedAt
                )
            }
            let workout = Workout(
                id: UUID(), name: name, startedAt: start, completedAt: completedAt,
                notes: nil, templateId: nil,
                exercises: [WorkoutExercise(id: UUID(), exercise: exercise, order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: built)]
            )
            return try await repo.save(workout)
        }

        var activeExercise: WorkoutExercise { vm.currentWorkout!.exercises[0] }
    }

    private static let touchedKeys = [
        "weightUnit", "intensityMetric", "autoStartRestTimer", "hasSetAutoStartRestTimer", "defaultRestSeconds"
    ]

    private func withStack(unit: WeightUnit = .kg, metric: IntensityMetric = .rpe, _ body: (Stack) async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let snapshot = Self.touchedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in snapshot {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let prefs = UserPreferencesService()
        prefs.weightUnit = unit
        prefs.intensityMetric = metric
        prefs.autoStartRestTimer = true
        prefs.defaultRestSeconds = 90
        try await body(Stack(prefs: prefs))
    }

    private func json(_ result: AIToolResult) throws -> [String: JSONValue] {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(result.outputForModel.utf8))
        guard case .object(let object) = decoded else { throw AIToolError("output was not a JSON object") }
        return object
    }

    private func yesterday() -> String {
        AIJSON.dateString(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }

    private func expectError(_ body: () async throws -> Void, contains fragment: String) async {
        do {
            try await body()
            Issue.record("expected an error containing '\(fragment)'")
        } catch {
            #expect(error.localizedDescription.contains(fragment), "got: \(error.localizedDescription)")
        }
    }

    // MARK: - get_workout

    @Test("get_workout returns the active workout with 1-based set numbers")
    func getActiveWorkout() async throws {
        try await withStack { s in
            try await s.startActive()
            let result = try await GetWorkoutTool(resolver: s.resolver).call(argumentsJSON: "{}")
            let object = try json(result)
            #expect(object["source"] == .string("active"))
            #expect(object["units"] == .string("kg"))
            guard case .array(let exercises)? = object["exercises"], case .object(let first)? = exercises.first,
                  case .array(let sets)? = first["sets"], case .object(let set3) = sets[2] else {
                Issue.record("unexpected shape"); return
            }
            #expect(first["name"] == .string("Bench Press"))
            #expect(first["done"] == .string("0/3"))
            #expect(set3["n"] == .number(3))
            #expect(set3["weight_kg"] == .number(80))
        }
    }

    @Test("get_workout without an active workout or date errors")
    func getWorkoutNoActive() async throws {
        try await withStack { s in
            await expectError({ _ = try await GetWorkoutTool(resolver: s.resolver).call(argumentsJSON: "{}") },
                              contains: "No active workout")
        }
    }

    // MARK: - log_set

    @Test("log_set fills the next planned set, completes it, starts the rest timer, converts lbs")
    func logSetNextPlanned() async throws {
        try await withStack { s in
            try await s.startActive(weightKg: nil, reps: nil)
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"exercise_name":"bench press","weight":{"value":220.46,"unit":"lbs"},"reps":8,"rpe":9,"to_failure":true}
            """)
            let object = try json(result)
            #expect(object["action"] == .string("updated"))
            let set = s.activeExercise.sets[0]
            #expect(set.isCompleted)
            #expect(abs((set.weight ?? 0) - 100) < 0.01)
            #expect(set.reps == 8)
            #expect(set.rpe == 9)
            #expect(set.rir == 1)
            #expect(set.isFailure)
            #expect(s.timer.starts.count == 1)
            #expect(s.timer.starts[0].setNumber == 1)
            let receipt = try #require(result.receipt)
            #expect(receipt.scope == .activeWorkout)
            #expect(receipt.sections[0].title == "Bench Press · set 1")
            #expect(receipt.sections[0].lines[0] == "100 kg × 8")
            #expect(receipt.sections[0].lines[1] == "RPE 9 · to failure")
            // Persisted, not just in memory.
            let saved = try await s.repo.fetchAll().first!
            #expect(saved.exercises[0].sets[0].isCompleted)
        }
    }

    @Test("log_set appends when set_number is count+1 and errors beyond")
    func logSetAppend() async throws {
        try await withStack { s in
            try await s.startActive(sets: 1)
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"exercise_name":"Bench Press","set_number":2,"weight":{"value":85,"unit":"kg"},"reps":6}
            """)
            #expect(try json(result)["action"] == .string("created"))
            #expect(s.activeExercise.sets.count == 2)
            #expect(s.activeExercise.sets[1].order == 2)
            #expect(s.activeExercise.sets[1].weight == 85)
            await expectError({
                _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","set_number":9,"reps":6}"#)
            }, contains: "out of range")
        }
    }

    @Test("log_set with completed:false keeps the set planned and starts no timer")
    func logSetPlanned() async throws {
        try await withStack { s in
            try await s.startActive(sets: 1)
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"exercise_name":"Bench Press","set_number":1,"reps":10,"completed":false}
            """)
            let set = s.activeExercise.sets[0]
            #expect(!set.isCompleted)
            #expect(set.reps == 10)
            #expect(set.weight == 80, "unspecified fields keep their values")
            #expect(s.timer.starts.isEmpty)
            #expect(result.receipt?.sections[0].symbol == "pencil.circle")
        }
    }

    @Test("log_set rejects rpe together with rir and out-of-range values")
    func logSetIntensityValidation() async throws {
        try await withStack { s in
            try await s.startActive()
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","rpe":8,"rir":2}"#) },
                              contains: "either rpe or rir")
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","rpe":11}"#) },
                              contains: "between 1 and 10")
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","set_type":"failure"}"#) },
                              contains: "to_failure")
            #expect(s.activeExercise.sets.allSatisfy { !$0.isCompleted })
        }
    }

    @Test("log_set to_failure without intensity backfills RPE 10 / RIR 0")
    func logSetFailureBackfill() async throws {
        try await withStack { s in
            try await s.startActive()
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","to_failure":true}"#)
            let set = s.activeExercise.sets[0]
            #expect(set.isFailure && set.rpe == 10 && set.rir == 0)
        }
    }

    @Test("log_set unknown exercise lists the workout's exercises and suggests add_exercise")
    func logSetUnknownExercise() async throws {
        try await withStack { s in
            try await s.startActive()
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Deadlift","reps":5}"#) },
                              contains: "add_exercise")
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Deadlift","reps":5}"#) },
                              contains: "Bench Press")
        }
    }

    @Test("log_set drop_segments builds a drop set; parent edits then require segments")
    func logSetDropSet() async throws {
        try await withStack { s in
            try await s.startActive(sets: 1)
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"exercise_name":"Bench Press","set_number":1,"drop_segments":[
              {"weight":{"value":85,"unit":"kg"},"reps":6,"rpe":9},
              {"weight":{"value":70,"unit":"kg"},"reps":6},
              {"weight":{"value":55,"unit":"kg"},"reps":8,"to_failure":true}]}
            """)
            let set = s.activeExercise.sets[0]
            #expect(set.setType == .dropset)
            #expect(set.dropSets.count == 3)
            #expect(set.weight == 85 && set.reps == 6, "parent mirrors the top segment")
            #expect(set.dropSets[2].isFailure)
            #expect(set.isCompleted)
            #expect(result.receipt?.sections[0].lines[0] == "85 kg × 6 → 70 kg × 6 → 55 kg × 8")

            await expectError({
                _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","set_number":1,"weight":{"value":90,"unit":"kg"}}"#)
            }, contains: "drop_segments")
            await expectError({
                _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","set_number":1,"drop_segments":[{"reps":5}]}"#)
            }, contains: "at least 2")

            // [] converts back to a plain set and the parent edit applies in the same call.
            _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","set_number":1,"drop_segments":[],"weight":{"value":90,"unit":"kg"}}"#)
            let plain = s.activeExercise.sets[0]
            #expect(plain.dropSets.isEmpty && plain.setType == .normal && plain.weight == 90)
        }
    }

    @Test("receipts render in lbs and RIR when the user prefers them")
    func receiptUnits() async throws {
        try await withStack(unit: .lbs, metric: .rir) { s in
            try await s.startActive(weightKg: nil, reps: nil)
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"exercise_name":"Bench Press","weight":{"value":100,"unit":"kg"},"reps":5,"rir":2}
            """)
            let lines = try #require(result.receipt?.sections[0].lines)
            #expect(lines[0].hasSuffix("lbs × 5"))
            #expect(lines[0].hasPrefix("220"))
            #expect(lines[1] == "RIR 2")
        }
    }

    // MARK: - add_sets / remove_set

    @Test("add_sets appends prefilled planned sets and validates count")
    func addSets() async throws {
        try await withStack { s in
            try await s.startActive(sets: 1)
            let tool = AddSetsTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"exercise_name":"Bench Press","count":2,"weight":{"value":85,"unit":"kg"},"reps":8,"set_type":"warmup"}
            """)
            let sets = s.activeExercise.sets
            #expect(sets.count == 3)
            #expect(sets.map(\.order) == [1, 2, 3])
            #expect(sets[2].weight == 85 && sets[2].reps == 8 && sets[2].setType == .warmup && !sets[2].isCompleted)
            #expect(result.receipt?.sections[0].lines[0] == "Added 2 sets · 85 kg × 8")
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","count":11}"#) },
                              contains: "between 1 and 10")
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","set_type":"dropset"}"#) },
                              contains: "dropset")
        }
    }

    @Test("remove_set removes an empty set directly but asks to confirm for logged data")
    func removeSet() async throws {
        try await withStack { s in
            let exercise = try await s.startActive(sets: 2, weightKg: nil, reps: nil)
            let tool = RemoveSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let direct = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","set_number":1}"#)
            #expect(direct.draft == nil)
            #expect(s.activeExercise.sets.count == 1)
            #expect(s.activeExercise.sets[0].order == 1)

            try await s.coordinator.completeSet(exerciseId: exercise.id, setId: s.activeExercise.sets[0].id)
            let confirm = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press"}"#)
            guard case .action(let action)? = confirm.draft,
                  case .removeSet(let workoutID, let exerciseID, let setID) = action.kind else {
                Issue.record("expected a removeSet confirm draft"); return
            }
            #expect(workoutID == s.vm.currentWorkout?.id && exerciseID == exercise.id && setID == s.activeExercise.sets[0].id)
            #expect(confirm.outputForModel.contains("confirmation_presented"))
            #expect(s.activeExercise.sets.count == 1, "nothing removed until confirmed")
            #expect(action.confirmLabel == "Remove")
        }
    }

    // MARK: - add / remove / change exercise

    @Test("add_exercise resolves the catalog name and adds prefilled sets; duplicates need allow_duplicate")
    func addExercise() async throws {
        try await withStack { s in
            try await s.startActive()
            _ = try await s.exercise("Incline Dumbbell Press")
            let tool = AddExerciseTool(resolver: s.resolver, exerciseRepository: s.exerciseRepo, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"exercise_name":"incline dumbbell press","sets":2,"weight":{"value":30,"unit":"kg"},"reps":10,"rest_seconds":120,"notes":"slow eccentric"}
            """)
            let workout = try #require(s.vm.currentWorkout)
            #expect(workout.exercises.count == 2)
            let added = workout.exercises[1]
            #expect(added.exercise.name == "Incline Dumbbell Press")
            #expect(added.order == 2)
            #expect(added.sets.count == 2 && added.sets[1].weight == 30 && added.sets[1].reps == 10)
            #expect(added.restTimerSeconds == 120 && added.notes == "slow eccentric")
            #expect(try json(result)["position"] == .number(2))

            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press"}"#) },
                              contains: "allow_duplicate")
            let dup = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","sets":1,"allow_duplicate":true}"#)
            guard case .object(let exerciseJSON)? = try json(dup)["exercise"] else { Issue.record("no exercise"); return }
            #expect(exerciseJSON["occurrence"] == .number(2))
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Nonexistent Lift"}"#) },
                              contains: "No exercise named")
        }
    }

    @Test("remove_exercise removes directly without completed sets, confirms otherwise")
    func removeExercise() async throws {
        try await withStack { s in
            let exercise = try await s.startActive()
            let tool = RemoveExerciseTool(resolver: s.resolver, userPreferencesService: s.prefs)
            try await s.coordinator.completeSet(exerciseId: exercise.id, setId: exercise.sets[0].id)
            let confirm = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press"}"#)
            guard case .action(let action)? = confirm.draft, case .removeExercise = action.kind else {
                Issue.record("expected confirm draft"); return
            }
            #expect(action.summaryLines[0].contains("1 completed set"))
            #expect(s.vm.currentWorkout?.exercises.count == 1)

            try await s.coordinator.uncompleteSet(exerciseId: exercise.id, setId: exercise.sets[0].id)
            let direct = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press"}"#)
            #expect(direct.draft == nil)
            #expect(s.vm.currentWorkout?.exercises.isEmpty == true)
            #expect(direct.receipt?.sections[0].title == "Removed Bench Press")
        }
    }

    @Test("change_exercise swaps the exercise and keeps every set")
    func changeExercise() async throws {
        try await withStack { s in
            let before = try await s.startActive()
            let incline = try await s.exercise("Incline Bench Press")
            let tool = ChangeExerciseTool(resolver: s.resolver, exerciseRepository: s.exerciseRepo, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: #"{"exercise_name":"Bench Press","new_exercise_name":"Incline Bench Press"}"#)
            let after = s.activeExercise
            #expect(after.id == before.id)
            #expect(after.exercise.id == incline.id)
            #expect(after.sets.map(\.id) == before.sets.map(\.id))
            #expect(result.receipt?.sections[0].title == "Bench Press → Incline Bench Press")
            #expect(result.receipt?.sections[0].lines[0] == "3 sets kept")
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"exercise_name":"Incline Bench Press","new_exercise_name":"incline bench press"}"#) },
                              contains: "same exercise")
        }
    }

    // MARK: - notes / deload

    @Test("set_notes writes workout notes, exercise notes, appends and clears")
    func setNotes() async throws {
        try await withStack { s in
            try await s.startActive()
            let tool = SetNotesTool(resolver: s.resolver, userPreferencesService: s.prefs)
            _ = try await tool.call(argumentsJSON: #"{"notes":"Felt strong"}"#)
            #expect(s.vm.currentWorkout?.notes == "Felt strong")
            _ = try await tool.call(argumentsJSON: #"{"notes":"Elbows tucked","exercise_name":"Bench Press"}"#)
            #expect(s.activeExercise.notes == "Elbows tucked")
            let appended = try await tool.call(argumentsJSON: #"{"notes":"Pause reps","exercise_name":"Bench Press","append":true}"#)
            #expect(s.activeExercise.notes == "Elbows tucked\nPause reps")
            #expect(appended.receipt?.sections[0].title == "Note · Bench Press")
            let cleared = try await tool.call(argumentsJSON: #"{"notes":""}"#)
            #expect(s.vm.currentWorkout?.notes == nil)
            #expect(cleared.receipt?.sections[0].lines[0] == "Cleared")
        }
    }

    @Test("set_deload flips the flag on the active workout")
    func setDeload() async throws {
        try await withStack { s in
            try await s.startActive()
            let tool = SetDeloadTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let on = try await tool.call(argumentsJSON: #"{"is_deload":true}"#)
            #expect(s.vm.currentWorkout?.isDeload == true)
            #expect(on.receipt?.sections[0].lines[0] == "Marked as deload")
            _ = try await tool.call(argumentsJSON: #"{"is_deload":false}"#)
            #expect(s.vm.currentWorkout?.isDeload == false)
        }
    }

    // MARK: - History targets

    @Test("workout_date edits a completed workout, backdates completion and syncs the UI instance")
    func historyEdit() async throws {
        try await withStack { s in
            let seeded = try await s.seedHistory()
            let tool = LogSetTool(resolver: s.resolver, userPreferencesService: s.prefs)
            let result = try await tool.call(argumentsJSON: """
            {"workout_date":"\(yesterday())","exercise_name":"Squat","set_number":4,"weight":{"value":110,"unit":"kg"},"reps":3,"rpe":9}
            """)
            let receipt = try #require(result.receipt)
            #expect(receipt.scope == .historyWorkout)
            #expect(receipt.workoutID == seeded.id)
            #expect(receipt.headline.hasPrefix("Legs · "))

            let saved = try #require(try await s.repo.fetchAll().first { $0.id == seeded.id })
            let set4 = saved.exercises[0].sets[3]
            #expect(set4.weight == 110 && set4.reps == 3 && set4.rpe == 9 && set4.isCompleted)
            #expect(set4.completedAt == seeded.completedAt, "history sets are stamped inside the workout's window")
            #expect(s.timer.starts.isEmpty, "no rest timer for history edits")
            #expect(s.absorbed.last?.id == seeded.id)
            #expect(s.vm.currentWorkout == nil, "the active workout is untouched")

            let swap = ChangeExerciseTool(resolver: s.resolver, exerciseRepository: s.exerciseRepo, userPreferencesService: s.prefs)
            _ = try await s.exercise("Front Squat")
            _ = try await swap.call(argumentsJSON: #"{"workout_date":"\#(yesterday())","exercise_name":"Squat","new_exercise_name":"Front Squat"}"#)
            let swapped = try #require(try await s.repo.fetchAll().first { $0.id == seeded.id })
            #expect(swapped.exercises[0].exercise.name == "Front Squat")
            #expect(swapped.exercises[0].sets.count == 4)
        }
    }

    @Test("workout_date errors: bad format, none on date, ambiguous without workout_name")
    func historyResolution() async throws {
        try await withStack { s in
            let tool = GetWorkoutTool(resolver: s.resolver)
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"workout_date":"yesterday"}"#) }, contains: "yyyy-MM-dd")
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"workout_date":"\#(yesterday())"}"#) }, contains: "No completed workout")

            try await s.seedHistory(name: "Legs", hour: 9)
            try await s.seedHistory(name: "Cardio", exerciseName: "Row", hour: 18)
            await expectError({ _ = try await tool.call(argumentsJSON: #"{"workout_date":"\#(yesterday())"}"#) }, contains: "workout_name")
            let picked = try await tool.call(argumentsJSON: #"{"workout_date":"\#(yesterday())","workout_name":"cardio"}"#)
            #expect(try json(picked)["name"] == .string("Cardio"))
            #expect(try json(picked)["source"] == .string("history"))
        }
    }

    @Test("set_deload on history flips the flag without scaling weights")
    func historyDeload() async throws {
        try await withStack { s in
            let seeded = try await s.seedHistory()
            let tool = SetDeloadTool(resolver: s.resolver, userPreferencesService: s.prefs)
            _ = try await tool.call(argumentsJSON: #"{"workout_date":"\#(yesterday())","is_deload":true}"#)
            let saved = try #require(try await s.repo.fetchAll().first { $0.id == seeded.id })
            #expect(saved.isDeload)
            #expect(saved.exercises[0].sets.allSatisfy { $0.weight == 100 })
        }
    }
}
