import Foundation

// Workout editing tools. Each targets the active workout unless `workout_date`
// selects a completed one; every write goes through a `WorkoutEditor` (the same
// ViewModels the UI uses) and ends with `commit()`.

// MARK: - Shared argument decoding

/// Fields common to every editing tool's `Arguments`.
private protocol WorkoutTargetArguments {
    var workout_date: String? { get }
    var workout_name: String? { get }
}

private protocol ExerciseInWorkoutArguments: WorkoutTargetArguments {
    var exercise_name: String { get }
    var occurrence: Int? { get }
}

@MainActor
private struct EditContext {
    let editor: any WorkoutEditor
    let text: ReceiptText

    var workout: Workout {
        get throws { try editor.snapshot() }
    }

    init(resolver: any WorkoutTargetResolving, args: WorkoutTargetArguments, preferences: UserPreferencesService?) async throws {
        editor = try await resolver.resolve(date: args.workout_date, workoutName: args.workout_name)
        text = ReceiptText(preferences: preferences)
    }

    func exercise(_ args: ExerciseInWorkoutArguments) throws -> WorkoutExercise {
        try editor.findExercise(named: args.exercise_name, occurrence: args.occurrence ?? 1)
    }

    func receipt(symbol: String, title: String, lines: [String]) throws -> AIReceipt {
        text.receipt(for: try workout, scope: editor.scope, symbol: symbol, title: title, lines: lines)
    }

    /// Output payload common to write tools: the touched exercise plus done count.
    func exerciseOutput(action: String, exerciseId: UUID, extra: [String: JSONValue] = [:]) throws -> String {
        let workout = try self.workout
        let exercise = try editor.exercise(id: exerciseId)
        let repeats = workout.exercises.filter { $0.exercise.name == exercise.exercise.name }.count > 1
        var object: [String: JSONValue] = [
            "action": .string(action),
            "exercise": WorkoutJSON.exercise(
                exercise,
                occurrence: repeats ? WorkoutExerciseResolver.occurrence(of: exercise, in: workout) : nil
            ),
            "units": .string("kg")
        ]
        for (key, value) in extra { object[key] = value }
        return AIJSON.string(.object(object))
    }
}

// MARK: - get_workout

@MainActor
public final class GetWorkoutTool: AITool {
    private let resolver: any WorkoutTargetResolving

    public init(resolver: any WorkoutTargetResolving) {
        self.resolver = resolver
    }

    public let name = "get_workout"
    public let description = """
    Full detail of one workout with 1-based set numbers: the active workout (omit workout_date) \
    or a completed workout started on workout_date. Weights in kg.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: ToolSchemas.target)
    }

    private struct Arguments: Decodable, WorkoutTargetArguments {
        var workout_date: String?
        var workout_name: String?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let editor = try await resolver.resolve(date: args.workout_date, workoutName: args.workout_name)
        let workout = try editor.snapshot()
        let label = editor.scope == .activeWorkout ? "Read active workout" : "Read workout \(AIJSON.dateString(workout.startedAt))"
        return AIToolResult(
            outputForModel: AIJSON.string(WorkoutJSON.workout(workout, scope: editor.scope)),
            activityLabel: label
        )
    }
}

// MARK: - log_set

@MainActor
public final class LogSetTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.preferences = userPreferencesService
    }

    public let name = "log_set"
    public let description = """
    Create or update ONE set of an exercise already in the workout and (by default) mark it done — \
    like tapping the checkmark: rest timer and widget update on the active workout. Omit set_number \
    for the next incomplete set (appends if none); pass count+1 to append. Unspecified fields keep \
    their values. For drop sets pass drop_segments (top set first); a drop set's weight/reps can only \
    be edited through drop_segments. Call once per set.
    """

    public var parametersSchema: JSONValue {
        var properties = ToolSchemas.target.merging(ToolSchemas.exerciseInWorkout) { $1 }
        properties["set_number"] = AIToolRegistry.integerSchema(
            "1-based set to update; count+1 appends; omit for the next incomplete set."
        )
        properties["weight"] = ToolSchemas.weight
        properties["reps"] = AIToolRegistry.integerSchema("Reps performed")
        properties["duration_seconds"] = AIToolRegistry.integerSchema("For timed exercises")
        properties["distance_meters"] = AIToolRegistry.numberSchema("For cardio")
        properties["rpe"] = AIToolRegistry.numberSchema("RPE 1-10 (not with rir)")
        properties["rir"] = AIToolRegistry.numberSchema("Reps in reserve 0-9 (not with rpe)")
        properties["to_failure"] = AIToolRegistry.boolSchema("Set was taken to failure")
        properties["set_type"] = AIToolRegistry.enumSchema(AISetType.self, description: "Default normal")
        properties["drop_segments"] = AIToolRegistry.arraySchema(
            of: ToolSchemas.dropSegment,
            description: "All segments of a drop set including the top set (at least 2); [] converts back to a plain set."
        )
        properties["completed"] = AIToolRegistry.boolSchema("Mark the set done (default true). false = plan it without completing.")
        return AIToolRegistry.objectSchema(properties: properties, required: ["exercise_name"])
    }

    private struct Arguments: Decodable, ExerciseInWorkoutArguments {
        var workout_date: String?
        var workout_name: String?
        var exercise_name: String
        var occurrence: Int?
        var set_number: Int?
        var weight: WeightArgument?
        var reps: Int?
        var duration_seconds: Int?
        var distance_meters: Double?
        var rpe: Double?
        var rir: Double?
        var to_failure: Bool?
        var set_type: String?
        var drop_segments: [DropSegmentArgument]?
        var completed: Bool?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        if let reps = args.reps, reps < 0 { throw AIToolError("reps must be 0 or more.") }
        let changes = SetChanges(
            weightKg: try args.weight?.kilograms(),
            reps: args.reps,
            durationSeconds: args.duration_seconds,
            distanceMeters: args.distance_meters,
            intensity: try ToolArguments.intensity(rpe: args.rpe, rir: args.rir),
            setType: try ToolArguments.setType(args.set_type, allowDropset: true),
            isFailure: args.to_failure,
            isCompleted: args.completed ?? true,
            dropSegments: try args.drop_segments?.map { try $0.segment() }
        )

        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        let exercise = try context.exercise(args)

        // Resolve which set: existing, or a new one appended first.
        var action = "updated"
        let target: ExerciseSet
        if let number = args.set_number {
            if number == exercise.sets.count + 1 {
                target = try await appendSet(context, exerciseId: exercise.id)
                action = "created"
            } else {
                target = try context.editor.set(in: exercise.id, number: number)
            }
        } else if let next = exercise.sets.first(where: { !$0.isCompleted }) {
            target = next
        } else {
            target = try await appendSet(context, exerciseId: exercise.id)
            action = "created"
        }

        let updated = try await context.editor.updateSet(exerciseId: exercise.id, setId: target.id, changes: changes)
        await context.editor.commit()

        let refreshed = try context.editor.exercise(id: exercise.id)
        let number = (refreshed.sets.firstIndex { $0.id == updated.id } ?? 0) + 1
        let output = try context.exerciseOutput(
            action: action, exerciseId: exercise.id,
            extra: ["set": WorkoutJSON.set(updated, number: number)]
        )
        let receipt = try context.receipt(
            symbol: updated.isCompleted ? "checkmark.circle.fill" : "pencil.circle",
            title: "\(refreshed.exercise.name) · set \(number)",
            lines: context.text.lines(for: updated)
        )
        return AIToolResult(
            outputForModel: output,
            receipt: receipt,
            activityLabel: "Logged \(refreshed.exercise.name) set \(number)"
        )
    }

    private func appendSet(_ context: EditContext, exerciseId: UUID) async throws -> ExerciseSet {
        guard let set = try await context.editor.addSets(exerciseId: exerciseId, prefills: [SetPrefill()]).first else {
            throw AIToolError("Could not add a set.")
        }
        return set
    }
}

// MARK: - add_sets

@MainActor
public final class AddSetsTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.preferences = userPreferencesService
    }

    public let name = "add_sets"
    public let description = "Append planned (not completed) sets to an exercise in the workout, optionally prefilled."

    public var parametersSchema: JSONValue {
        var properties = ToolSchemas.target.merging(ToolSchemas.exerciseInWorkout) { $1 }
        properties["count"] = AIToolRegistry.integerSchema("How many sets to add, 1-10 (default 1)")
        properties["weight"] = ToolSchemas.weight
        properties["reps"] = AIToolRegistry.integerSchema("Prefilled reps")
        properties["set_type"] = AIToolRegistry.stringSchema("normal (default), warmup or restPause")
        return AIToolRegistry.objectSchema(properties: properties, required: ["exercise_name"])
    }

    private struct Arguments: Decodable, ExerciseInWorkoutArguments {
        var workout_date: String?
        var workout_name: String?
        var exercise_name: String
        var occurrence: Int?
        var count: Int?
        var weight: WeightArgument?
        var reps: Int?
        var set_type: String?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let count = args.count ?? 1
        guard (1...10).contains(count) else { throw AIToolError("count must be between 1 and 10.") }
        let prefill = SetPrefill(
            weightKg: try args.weight?.kilograms(),
            reps: args.reps,
            setType: try ToolArguments.setType(args.set_type, allowDropset: false) ?? .normal
        )

        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        let exercise = try context.exercise(args)
        let added = try await context.editor.addSets(exerciseId: exercise.id, prefills: Array(repeating: prefill, count: count))
        await context.editor.commit()

        var line = "Added \(count) set\(count == 1 ? "" : "s")"
        if let load = context.text.load(weightKg: prefill.weightKg, reps: prefill.reps) { line += " · \(load)" }
        return AIToolResult(
            outputForModel: try context.exerciseOutput(
                action: "added_sets", exerciseId: exercise.id,
                extra: ["added": .number(Double(added.count))]
            ),
            receipt: try context.receipt(symbol: "plus.circle", title: exercise.exercise.name, lines: [line]),
            activityLabel: "Added \(count) set\(count == 1 ? "" : "s") to \(exercise.exercise.name)"
        )
    }
}

// MARK: - remove_set

@MainActor
public final class RemoveSetTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.preferences = userPreferencesService
    }

    public let name = "remove_set"
    public let description = """
    Remove one set (default: the last) from an exercise in the workout. An empty planned set is \
    removed immediately; a set with logged data shows the user a Confirm card first.
    """

    public var parametersSchema: JSONValue {
        var properties = ToolSchemas.target.merging(ToolSchemas.exerciseInWorkout) { $1 }
        properties["set_number"] = AIToolRegistry.integerSchema("1-based set to remove (default: last)")
        return AIToolRegistry.objectSchema(properties: properties, required: ["exercise_name"])
    }

    private struct Arguments: Decodable, ExerciseInWorkoutArguments {
        var workout_date: String?
        var workout_name: String?
        var exercise_name: String
        var occurrence: Int?
        var set_number: Int?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        let exercise = try context.exercise(args)
        guard !exercise.sets.isEmpty else { throw AIToolError("\(exercise.exercise.name) has no sets.") }
        let number = args.set_number ?? exercise.sets.count
        let target = try context.editor.set(in: exercise.id, number: number)
        let workout = try context.workout
        let summary = context.text.inline(target)

        if WorkoutEditGuards.setHasData(target) {
            let title = "Remove set \(number) of \(exercise.exercise.name)?"
            let lines = [summary.isEmpty ? "Set \(number)" : summary, "From \(context.text.headline(for: workout, scope: context.editor.scope))"]
            let action = AIPendingAction(
                kind: .removeSet(workoutID: workout.id, exerciseID: exercise.id, setID: target.id),
                title: title, summaryLines: lines, confirmLabel: "Remove"
            )
            return AIToolResult(
                outputForModel: confirmationReceipt(action: name, title: title, summary: lines),
                draft: .action(action),
                activityLabel: "Asked to confirm removing a set"
            )
        }

        try await context.editor.removeSet(exerciseId: exercise.id, setId: target.id)
        await context.editor.commit()
        return AIToolResult(
            outputForModel: try context.exerciseOutput(action: "removed_set", exerciseId: exercise.id, extra: ["removed_set_number": .number(Double(number))]),
            receipt: try context.receipt(symbol: "minus.circle", title: exercise.exercise.name, lines: ["Removed empty set \(number)"]),
            activityLabel: "Removed \(exercise.exercise.name) set \(number)"
        )
    }
}

// MARK: - add_exercise

@MainActor
public final class AddExerciseTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let exerciseRepository: any ExerciseRepository
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, exerciseRepository: any ExerciseRepository, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.exerciseRepository = exerciseRepository
        self.preferences = userPreferencesService
    }

    public let name = "add_exercise"
    public let description = """
    Add a catalog exercise (exact name from list_exercises) to the workout with planned sets. \
    Errors if it is already in the workout unless allow_duplicate is true.
    """

    public var parametersSchema: JSONValue {
        var properties = ToolSchemas.target
        properties["exercise_name"] = AIToolRegistry.stringSchema("Exact catalog exercise name")
        properties["sets"] = AIToolRegistry.integerSchema("Planned sets to create, 0-10 (default 3)")
        properties["weight"] = ToolSchemas.weight
        properties["reps"] = AIToolRegistry.integerSchema("Prefilled reps for every set")
        properties["rest_seconds"] = AIToolRegistry.integerSchema("Rest timer for this exercise")
        properties["notes"] = AIToolRegistry.stringSchema("Exercise note")
        properties["allow_duplicate"] = AIToolRegistry.boolSchema("Add a second block of an exercise already in the workout")
        return AIToolRegistry.objectSchema(properties: properties, required: ["exercise_name"])
    }

    private struct Arguments: Decodable, WorkoutTargetArguments {
        var workout_date: String?
        var workout_name: String?
        var exercise_name: String
        var sets: Int?
        var weight: WeightArgument?
        var reps: Int?
        var rest_seconds: Int?
        var notes: String?
        var allow_duplicate: Bool?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let count = args.sets ?? 3
        guard (0...10).contains(count) else { throw AIToolError("sets must be between 0 and 10.") }
        let catalog = try await exerciseRepository.fetchAll().filter { !$0.isArchived }
        let exercise = try ExerciseNameResolver.resolve(name: args.exercise_name, in: catalog)

        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        let workout = try context.workout
        let existing = workout.exercises.filter { $0.exercise.id == exercise.id }.count
        if existing > 0, args.allow_duplicate != true {
            throw AIToolError("\(exercise.name) is already in this workout (occurrence \(existing)). Pass allow_duplicate: true to add a second block.")
        }
        let prefill = SetPrefill(weightKg: try args.weight?.kilograms(), reps: args.reps)
        let added = try await context.editor.addExercise(
            exercise, sets: Array(repeating: prefill, count: count),
            restSeconds: args.rest_seconds, notes: args.notes
        )
        await context.editor.commit()

        var line = "\(count) planned set\(count == 1 ? "" : "s")"
        if let load = context.text.load(weightKg: prefill.weightKg, reps: prefill.reps) { line += " · \(load)" }
        return AIToolResult(
            outputForModel: try context.exerciseOutput(action: "added", exerciseId: added.id, extra: ["position": .number(Double(added.order))]),
            receipt: try context.receipt(symbol: "plus.circle", title: "Added \(exercise.name)", lines: [line]),
            activityLabel: "Added \(exercise.name)"
        )
    }
}

// MARK: - remove_exercise

@MainActor
public final class RemoveExerciseTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.preferences = userPreferencesService
    }

    public let name = "remove_exercise"
    public let description = """
    Remove an exercise from the workout. Removed immediately when none of its sets are completed; \
    otherwise the user sees a Confirm card first.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(
            properties: ToolSchemas.target.merging(ToolSchemas.exerciseInWorkout) { $1 },
            required: ["exercise_name"]
        )
    }

    private struct Arguments: Decodable, ExerciseInWorkoutArguments {
        var workout_date: String?
        var workout_name: String?
        var exercise_name: String
        var occurrence: Int?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        let exercise = try context.exercise(args)
        let workout = try context.workout
        let completed = exercise.sets.filter(\.isCompleted).count

        if WorkoutEditGuards.exerciseHasCompletedSets(exercise) {
            let title = "Remove \(exercise.exercise.name)?"
            let lines = [
                "\(completed) completed set\(completed == 1 ? "" : "s") will be deleted",
                "From \(context.text.headline(for: workout, scope: context.editor.scope))"
            ]
            let action = AIPendingAction(
                kind: .removeExercise(workoutID: workout.id, exerciseID: exercise.id),
                title: title, summaryLines: lines, confirmLabel: "Remove"
            )
            return AIToolResult(
                outputForModel: confirmationReceipt(action: name, title: title, summary: lines),
                draft: .action(action),
                activityLabel: "Asked to confirm removing \(exercise.exercise.name)"
            )
        }

        try await context.editor.removeExercise(id: exercise.id)
        await context.editor.commit()
        let remaining = try context.workout.exercises.sorted { $0.order < $1.order }.map { JSONValue.string($0.exercise.name) }
        let output = AIJSON.string(.object([
            "action": .string("removed"),
            "exercise": .string(exercise.exercise.name),
            "discarded_sets": .number(Double(exercise.sets.count)),
            "exercises": .array(remaining)
        ]))
        let line = exercise.sets.isEmpty ? "No sets" : "\(exercise.sets.count) planned set\(exercise.sets.count == 1 ? "" : "s") discarded"
        return AIToolResult(
            outputForModel: output,
            receipt: try context.receipt(symbol: "minus.circle", title: "Removed \(exercise.exercise.name)", lines: [line]),
            activityLabel: "Removed \(exercise.exercise.name)"
        )
    }
}

// MARK: - change_exercise

@MainActor
public final class ChangeExerciseTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let exerciseRepository: any ExerciseRepository
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, exerciseRepository: any ExerciseRepository, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.exerciseRepository = exerciseRepository
        self.preferences = userPreferencesService
    }

    public let name = "change_exercise"
    public let description = "Swap an exercise in the workout for another catalog exercise, keeping every logged set."

    public var parametersSchema: JSONValue {
        var properties = ToolSchemas.target.merging(ToolSchemas.exerciseInWorkout) { $1 }
        properties["new_exercise_name"] = AIToolRegistry.stringSchema("Exact catalog name of the replacement")
        return AIToolRegistry.objectSchema(properties: properties, required: ["exercise_name", "new_exercise_name"])
    }

    private struct Arguments: Decodable, ExerciseInWorkoutArguments {
        var workout_date: String?
        var workout_name: String?
        var exercise_name: String
        var occurrence: Int?
        var new_exercise_name: String
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let catalog = try await exerciseRepository.fetchAll().filter { !$0.isArchived }
        let replacement = try ExerciseNameResolver.resolve(name: args.new_exercise_name, in: catalog)

        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        let exercise = try context.exercise(args)
        guard exercise.exercise.id != replacement.id else {
            throw AIToolError("new_exercise_name is the same exercise.")
        }
        try await context.editor.replaceExercise(id: exercise.id, with: replacement)
        await context.editor.commit()

        let count = exercise.sets.count
        return AIToolResult(
            outputForModel: try context.exerciseOutput(
                action: "replaced", exerciseId: exercise.id,
                extra: ["from": .string(exercise.exercise.name), "to": .string(replacement.name)]
            ),
            receipt: try context.receipt(
                symbol: "arrow.triangle.2.circlepath",
                title: "\(exercise.exercise.name) → \(replacement.name)",
                lines: ["\(count) set\(count == 1 ? "" : "s") kept"]
            ),
            activityLabel: "Swapped \(exercise.exercise.name) → \(replacement.name)"
        )
    }
}

// MARK: - set_notes

@MainActor
public final class SetNotesTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.preferences = userPreferencesService
    }

    public let name = "set_notes"
    public let description = """
    Set the workout's notes, or an exercise's notes when exercise_name is given. Empty notes clear; \
    append: true adds to the existing text.
    """

    public var parametersSchema: JSONValue {
        var properties = ToolSchemas.target
        properties["notes"] = AIToolRegistry.stringSchema("The note text (empty clears)")
        properties["exercise_name"] = AIToolRegistry.stringSchema("Exercise in the workout, for an exercise-level note")
        properties["occurrence"] = AIToolRegistry.integerSchema("1-based, when the exercise repeats (default 1)")
        properties["append"] = AIToolRegistry.boolSchema("Append to existing notes instead of replacing (default false)")
        return AIToolRegistry.objectSchema(properties: properties, required: ["notes"])
    }

    private struct Arguments: Decodable, WorkoutTargetArguments {
        var workout_date: String?
        var workout_name: String?
        var notes: String
        var exercise_name: String?
        var occurrence: Int?
        var append: Bool?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        let incoming = args.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        func merged(_ existing: String?) -> String? {
            if args.append == true, let existing, !existing.isEmpty, !incoming.isEmpty {
                return existing + "\n" + incoming
            }
            return incoming.isEmpty ? nil : incoming
        }

        let scopeLabel: String
        let title: String
        let finalNotes: String?
        if let exerciseName = args.exercise_name, !exerciseName.isEmpty {
            let exercise = try context.editor.findExercise(named: exerciseName, occurrence: args.occurrence ?? 1)
            finalNotes = merged(exercise.notes)
            try await context.editor.setExerciseNotes(exerciseId: exercise.id, notes: finalNotes)
            scopeLabel = "exercise"
            title = "Note · \(exercise.exercise.name)"
        } else {
            finalNotes = merged(try context.workout.notes)
            try await context.editor.setWorkoutNotes(finalNotes)
            scopeLabel = "workout"
            title = "Workout note"
        }
        await context.editor.commit()

        let display = finalNotes.map { String($0.prefix(120)) } ?? "Cleared"
        return AIToolResult(
            outputForModel: AIJSON.string(.object([
                "scope": .string(scopeLabel),
                "notes": finalNotes.map { .string($0) } ?? .null
            ])),
            receipt: try context.receipt(symbol: "note.text", title: title, lines: [display]),
            activityLabel: "Saved note"
        )
    }
}

// MARK: - set_deload

@MainActor
public final class SetDeloadTool: AITool {
    private let resolver: any WorkoutTargetResolving
    private let preferences: UserPreferencesService?

    public init(resolver: any WorkoutTargetResolving, userPreferencesService: UserPreferencesService?) {
        self.resolver = resolver
        self.preferences = userPreferencesService
    }

    public let name = "set_deload"
    public let description = """
    Mark or unmark the workout as a deload. On the active workout this also scales the remaining \
    planned weights (per the user's deload settings); deload workouts are excluded from PRs.
    """

    public var parametersSchema: JSONValue {
        var properties = ToolSchemas.target
        properties["is_deload"] = AIToolRegistry.boolSchema("true to mark as deload, false to unmark")
        return AIToolRegistry.objectSchema(properties: properties, required: ["is_deload"])
    }

    private struct Arguments: Decodable, WorkoutTargetArguments {
        var workout_date: String?
        var workout_name: String?
        var is_deload: Bool
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let context = try await EditContext(resolver: resolver, args: args, preferences: preferences)
        try await context.editor.setDeload(args.is_deload)
        await context.editor.commit()
        let workout = try context.workout
        return AIToolResult(
            outputForModel: AIJSON.string(.object([
                "name": .string(workout.name),
                "is_deload": .bool(workout.isDeload)
            ])),
            receipt: try context.receipt(
                symbol: "arrow.down.circle",
                title: workout.name,
                lines: [workout.isDeload ? "Marked as deload" : "Deload removed"]
            ),
            activityLabel: "Updated deload flag"
        )
    }
}
