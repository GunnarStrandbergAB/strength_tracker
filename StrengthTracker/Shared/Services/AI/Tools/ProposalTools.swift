import Foundation

// Proposal tools: validate and build real domain objects, but NEVER write.
// The draft is carded in the chat; the user's Save routes it through the same
// seams the UI uses.

/// Weight argument with an explicit unit; normalized to kg at the tool boundary.
struct WeightArgument: Decodable {
    var value: Double
    var unit: String
    var entry: WeightRecording.WeightEntry? = nil

    func kilograms(for exercise: Exercise? = nil) throws -> Double {
        let kg: Double
        switch unit.lowercased() {
        case "kg": kg = value
        case "lbs", "lb": kg = WeightUnit.lbs.toKg(value)
        default: throw AIToolError("weight unit must be \"kg\" or \"lbs\", got '\(unit)'")
        }
        guard kg.isFinite else { throw AIToolError("Weight must be finite") }
        if let entry {
            guard let exercise else { throw AIToolError("An exercise is required to convert the weight convention.") }
            return try WeightRecordingHistory.inputWeight(kg, entry: entry, for: exercise)
        }
        return kg
    }
}

func parseEnum<T: CaseIterable & RawRepresentable>(
    _ type: T.Type, _ raw: String, field: String
) throws -> T where T.RawValue == String {
    guard let value = T(rawValue: raw) else {
        throw AIToolError("Unknown \(field) '\(raw)'. Valid values: \(T.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    return value
}


// MARK: - propose_exercise

@MainActor
public final class ProposeExerciseTool: AITool {
    private let exerciseRepository: any ExerciseRepository

    public init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    public let name = "propose_exercise"
    public let description = """
    Propose a new custom exercise. Shows the user a Save/Discard card — nothing is saved \
    until the user accepts. equipment_brand only applies to machine/cable/smithMachine, \
    loading_type only to machine, bodyweight_percent (10-150) only to bodyweightReps.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(
            properties: [
                "name": AIToolRegistry.stringSchema("Exercise name (must not already exist)"),
                "primary_muscle_group": AIToolRegistry.enumSchema(MuscleGroup.self),
                "secondary_muscle_groups": AIToolRegistry.arraySchema(of: AIToolRegistry.enumSchema(MuscleGroup.self)),
                "category": AIToolRegistry.enumSchema(ExerciseCategory.self),
                "exercise_type": AIToolRegistry.enumSchema(ExerciseType.self),
                "instructions": AIToolRegistry.stringSchema("Short how-to instructions"),
                "bodyweight_percent": AIToolRegistry.numberSchema("Percent of body weight lifted (bodyweightReps only, 10-150)"),
                "equipment_brand": AIToolRegistry.stringSchema("Machine brand, e.g. Hammer Strength"),
                "loading_type": AIToolRegistry.enumSchema(LoadingType.self),
                "weight_recording": ToolSchemas.weightRecording
            ],
            required: ["name", "primary_muscle_group", "category", "exercise_type"]
        )
    }

    private struct Arguments: Decodable {
        var name: String
        var primary_muscle_group: String
        var secondary_muscle_groups: [String]?
        var category: String
        var exercise_type: String
        var instructions: String?
        var bodyweight_percent: Double?
        var equipment_brand: String?
        var loading_type: String?
        var weight_recording: WeightRecording?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)

        let existing = try await exerciseRepository.fetchAll()
        let trimmedName = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only check against exercises the model can see (archived ones are
        // hidden from list_exercises — matching them creates an unfixable loop).
        if let duplicate = existing.first(where: {
            !$0.isArchived && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            throw AIToolError("An exercise named '\(duplicate.name)' already exists. Use it directly or pick a different name.")
        }

        let exercise = try ExerciseFactory.makeCustom(
            name: trimmedName,
            primaryMuscleGroup: try parseEnum(MuscleGroup.self, args.primary_muscle_group, field: "primary_muscle_group"),
            secondaryMuscleGroups: try (args.secondary_muscle_groups ?? []).map {
                try parseEnum(MuscleGroup.self, $0, field: "secondary_muscle_groups")
            },
            category: try parseEnum(ExerciseCategory.self, args.category, field: "category"),
            exerciseType: try parseEnum(ExerciseType.self, args.exercise_type, field: "exercise_type"),
            instructions: args.instructions,
            bodyweightPercent: args.bodyweight_percent,
            equipmentBrand: args.equipment_brand,
            loadingType: try args.loading_type.map { try parseEnum(LoadingType.self, $0, field: "loading_type") },
            weightRecording: args.weight_recording
        )

        return AIToolResult(
            outputForModel: proposalReceipt(kind: "exercise", name: exercise.name),
            draft: .exercise(exercise),
            activityLabel: "Drafted exercise '\(exercise.name)'"
        )
    }
}

// MARK: - propose_template

@MainActor
public final class ProposeTemplateTool: AITool {
    private let exerciseRepository: any ExerciseRepository
    private let userPreferencesService: UserPreferencesService

    public init(
        exerciseRepository: any ExerciseRepository,
        userPreferencesService: UserPreferencesService
    ) {
        self.exerciseRepository = exerciseRepository
        self.userPreferencesService = userPreferencesService
    }

    public let name = "propose_template"
    public let description = """
    Propose a workout template built from catalog exercises (exact names from \
    list_exercises). Shows the user a Save/Discard card — nothing is saved until the \
    user accepts. Give target weights with an explicit unit.
    """

    public var parametersSchema: JSONValue {
        let weightSchema = AIToolRegistry.objectSchema(
            properties: [
                "value": AIToolRegistry.numberSchema("Weight value"),
                "unit": .object(["type": .string("string"), "enum": .array([.string("kg"), .string("lbs")])])
            ],
            required: ["value", "unit"]
        )
        let exerciseSchema = AIToolRegistry.objectSchema(
            properties: [
                "exercise_name": AIToolRegistry.stringSchema("Exact catalog exercise name"),
                "target_sets": AIToolRegistry.integerSchema("Working sets (default 3)"),
                "target_reps": AIToolRegistry.integerSchema("Target reps per set"),
                "target_weight": weightSchema,
                "rest_seconds": AIToolRegistry.integerSchema("Rest between sets in seconds"),
                "superset_group": AIToolRegistry.integerSchema("Exercises sharing a number are supersetted"),
                "is_warmup": AIToolRegistry.boolSchema("Mark all sets as warm-up sets")
            ],
            required: ["exercise_name"]
        )
        return AIToolRegistry.objectSchema(
            properties: [
                "name": AIToolRegistry.stringSchema("Template name"),
                "notes": AIToolRegistry.stringSchema("Short description shown with the template"),
                "exercises": AIToolRegistry.arraySchema(of: exerciseSchema, description: "Exercises in order")
            ],
            required: ["name", "exercises"]
        )
    }

    private struct Arguments: Decodable {
        struct ExerciseEntry: Decodable {
            var exercise_name: String
            var target_sets: Int?
            var target_reps: Int?
            var target_weight: WeightArgument?
            var rest_seconds: Int?
            var superset_group: Int?
            var is_warmup: Bool?
        }

        var name: String
        var notes: String?
        var exercises: [ExerciseEntry]
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)

        let trimmedName = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AIToolError("Template name must not be empty") }
        guard !args.exercises.isEmpty else { throw AIToolError("A template needs at least one exercise") }

        let catalog = try await exerciseRepository.fetchAll()
        let defaultReps = userPreferencesService.defaultReps

        var templateExercises: [TemplateExercise] = []
        for (index, entry) in args.exercises.enumerated() {
            let exercise = try ExerciseNameResolver.resolve(name: entry.exercise_name, in: catalog)
            if let sets = entry.target_sets, !(1...20).contains(sets) {
                throw AIToolError("target_sets for '\(exercise.name)' must be 1-20")
            }
            if let reps = entry.target_reps, !(1...100).contains(reps) {
                throw AIToolError("target_reps for '\(exercise.name)' must be 1-100")
            }
            templateExercises.append(TemplateExerciseFactory.make(
                exercise: exercise,
                order: index,
                defaultReps: defaultReps,
                targetSets: entry.target_sets,
                targetReps: entry.target_reps,
                targetWeightKg: try entry.target_weight?.kilograms(for: exercise),
                restSeconds: entry.rest_seconds,
                supersetGroup: entry.superset_group,
                isWarmUp: entry.is_warmup ?? false
            ))
        }

        let template = WorkoutTemplate(
            id: UUID(),
            name: trimmedName,
            notes: args.notes?.isEmpty == true ? nil : args.notes,
            sortOrder: 0,   // repositioned to the end of the user's list on Save
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: templateExercises,
            isCustom: true
        )

        return AIToolResult(
            outputForModel: proposalReceipt(kind: "template", name: template.name),
            draft: .template(template),
            activityLabel: "Drafted template '\(template.name)'"
        )
    }
}

// MARK: - propose_training_plan

@MainActor
public final class ProposeTrainingPlanTool: AITool {
    private let exerciseRepository: any ExerciseRepository
    private let personalRecordRepository: any PersonalRecordRepository
    private let templateRepository: any TemplateRepository
    private let workoutRepository: (any WorkoutRepository)?

    public init(
        exerciseRepository: any ExerciseRepository,
        personalRecordRepository: any PersonalRecordRepository,
        templateRepository: any TemplateRepository,
        workoutRepository: (any WorkoutRepository)? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
        self.personalRecordRepository = personalRecordRepository
        self.templateRepository = templateRepository
    }

    public let name = "propose_training_plan"
    public let description = """
    Propose a multi-week periodized training plan. Shows the user a Save/Discard card; \
    on save the app's program generator deterministically builds blocks, weeks, and \
    sessions from these parameters. Exercises must be exact catalog names. Every \
    exercise needs a 1RM: provide estimated_1rm where you know it; otherwise the \
    user's PRs fill it in (the tool errors if neither exists — then ask the user). \
    A PLAN OWNS ITS EXERCISES: each training day is a list of exercises. day_splits \
    builds a day from any mix of: template_name (one of the user's templates, see \
    list_templates; its exercises are copied in and later changes to the template do \
    not reach the plan), exercise_names (exercises from this plan's exercises list, \
    which the plan progresses) and other_exercises (any catalog exercise at fixed \
    targets, never progressed: accessories, timed work, cardio). In a session the \
    template's exercises come first, then the progressed ones, then other_exercises. \
    Without day_splits, every exercise trains on every training day. \
    DELOAD WEEKS: deload_days keeps a subset of the training days with their normal \
    workouts. deload_schedule instead gives the deload week its own sessions on any \
    weekday, each from a template_name or same_as_day (a training day's workout); use \
    one or the other. Every deload session is done at the user's deload weight. \
    training_status overrides the app's automatic level detection — set it only when \
    the user states their level. \
    PROGRESSION: set pace to give every weighted exercise its own progression rule \
    (the wizard's presets: conservative = add a rep, then weight, after hitting each \
    target twice; standard = add a rep each session and add weight at the top of the \
    rep range; aggressive = add weight every session at fixed reps, back off after \
    three misses). A rule starts from start_weight if given, else the user's latest \
    workout, else the 1RM. Give an exercise its own rule to override the preset; call \
    preview_progression first to see what a rule asks for. Without pace or rules the \
    plan uses the percentage wave of program_type; wave_sets and wave_reps fix the \
    sets and reps of a wave exercise (the weight is then worked out from the 1RM for \
    those reps). A resistance band exercise needs no weight and no 1RM: with pace or a \
    rule it progresses on reps alone (increment_kg 0, start_weight_kg 0). \
    deload_every_weeks makes every Nth week a deload week (every 5th when omitted), \
    or 0 for none.
    """

    public var parametersSchema: JSONValue {
        let weightSchema = AIToolRegistry.objectSchema(
            properties: [
                "value": AIToolRegistry.numberSchema("Weight value"),
                "unit": .object(["type": .string("string"), "enum": .array([.string("kg"), .string("lbs")])])
            ],
            required: ["value", "unit"]
        )
        let exerciseSchema = AIToolRegistry.objectSchema(
            properties: [
                "exercise_name": AIToolRegistry.stringSchema("Exact catalog exercise name"),
                "estimated_1rm": weightSchema,
                "start_weight": weightSchema,
                "start_reps": AIToolRegistry.integerSchema("Rep target of the first session when start_weight is given; default the bottom of the rule's range"),
                "rule": ToolSchemas.progressionRule,
                "wave_sets": AIToolRegistry.integerSchema("Percentage wave only: sets asked for every session, 1–20; omit to let the wave decide"),
                "wave_reps": AIToolRegistry.integerSchema("Percentage wave only: reps asked for every session, 1–100; omit to let the wave decide")
            ],
            required: ["exercise_name"]
        )
        let otherExerciseSchema = AIToolRegistry.objectSchema(
            properties: [
                "exercise_name": AIToolRegistry.stringSchema("Exact catalog exercise name"),
                "sets": AIToolRegistry.integerSchema("1–20"),
                "reps": AIToolRegistry.integerSchema("1–100, for exercises counted in reps"),
                "weight": weightSchema,
                "duration_seconds": AIToolRegistry.integerSchema("Time target for timed and cardio exercises"),
                "distance_meters": AIToolRegistry.numberSchema("Distance target for distance and cardio exercises")
            ],
            required: ["exercise_name", "sets"]
        )
        let deloadSessionSchema = AIToolRegistry.objectSchema(
            properties: [
                "day": AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7; need not be a training day"),
                "template_name": AIToolRegistry.stringSchema("Exact name of one of the user's templates to train that day"),
                "same_as_day": AIToolRegistry.integerSchema("Train the workout of this training day (its weekday number) instead of a template")
            ],
            required: ["day"]
        )
        let daySplitSchema = AIToolRegistry.objectSchema(
            properties: [
                "training_day": AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7"),
                "exercise_names": AIToolRegistry.arraySchema(
                    of: AIToolRegistry.stringSchema("Exercise name from this plan's exercises list (may be empty when template_name is set)")
                ),
                "template_name": AIToolRegistry.stringSchema("Exact name of one of the user's templates (see list_templates) whose exercises are copied into this day"),
                "other_exercises": AIToolRegistry.arraySchema(of: otherExerciseSchema,
                    description: "Exercises this day also trains at fixed targets, without progression")
            ],
            required: ["training_day"]
        )
        return AIToolRegistry.objectSchema(
            properties: [
                "name": AIToolRegistry.stringSchema("Plan name"),
                "goal": AIToolRegistry.enumSchema(TrainingGoal.self, description: "Primary training goal"),
                "program_type": AIToolRegistry.enumSchema(ProgramType.self, description: "Periodization style (omit to let the app choose)"),
                "duration_weeks": AIToolRegistry.integerSchema("Programme length 4–52 weeks; default 12, or 10/9 for block programmes"),
                "weekly_frequency": AIToolRegistry.integerSchema("Training days per week (1-7); must equal the number of training_days when those are given"),
                "training_days": AIToolRegistry.arraySchema(
                    of: AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7"),
                    description: "Specific training days; omit for defaults"
                ),
                "deload_days": AIToolRegistry.arraySchema(
                    of: AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7"),
                    description: "Weekdays deload weeks train on — must be a subset of the training days; omit to deload on all training days. Not with deload_schedule."
                ),
                "deload_schedule": AIToolRegistry.arraySchema(
                    of: deloadSessionSchema,
                    description: "A deload week's own sessions, on any weekdays and with any workouts. Each needs template_name or same_as_day. Not with deload_days."
                ),
                "training_status": AIToolRegistry.enumSchema(
                    TrainingStatus.self,
                    description: "The user's training level — set only when the user states it; omit to auto-detect"
                ),
                "start_date": AIToolRegistry.stringSchema("Start date yyyy-MM-dd (today or later; default today)"),
                "pace": AIToolRegistry.enumSchema(PlanPace.self, description: "Preset for per-exercise progression rules; omit to use the percentage wave"),
                "deload_every_weeks": AIToolRegistry.integerSchema("Every Nth week is a deload week (2–12), or 0 for none; omit for every 5th week"),
                "exercises": AIToolRegistry.arraySchema(of: exerciseSchema, description: "Exercises to progress, in priority order"),
                "day_splits": AIToolRegistry.arraySchema(
                    of: daySplitSchema,
                    description: "Optional split: the exercises of each training day. Days must be training days; unlisted training days become rest/empty sessions."
                )
            ],
            required: ["name", "goal", "weekly_frequency", "exercises"]
        )
    }

    private struct Arguments: Decodable {
        struct ExerciseEntry: Decodable {
            var exercise_name: String
            var estimated_1rm: WeightArgument?
            var start_weight: WeightArgument?
            var start_reps: Int?
            var rule: ProgressionRuleArgument?
            var wave_sets: Int?
            var wave_reps: Int?
        }

        struct OtherExerciseEntry: Decodable {
            var exercise_name: String
            var sets: Int
            var reps: Int?
            var weight: WeightArgument?
            var duration_seconds: Int?
            var distance_meters: Double?
        }

        struct DaySplitEntry: Decodable {
            var training_day: Int
            var exercise_names: [String]?
            var template_name: String?
            var other_exercises: [OtherExerciseEntry]?
        }

        struct DeloadSessionEntry: Decodable {
            var day: Int
            var template_name: String?
            var same_as_day: Int?
        }

        var name: String
        var goal: String
        var program_type: String?
        var duration_weeks: Int?
        var weekly_frequency: Int
        var training_days: [Int]?
        var deload_days: [Int]?
        var training_status: String?
        var start_date: String?
        var exercises: [ExerciseEntry]
        var day_splits: [DaySplitEntry]?
        var pace: String?
        var deload_every_weeks: Int?
        var deload_schedule: [DeloadSessionEntry]?
    }

    /// The exercise's own rule, or the pace preset started from the best weight known:
    /// a given start_weight, then the latest workout, then the 1RM. Nil keeps the percentage wave.
    private func progressionRule(for exercise: Exercise, entry: Arguments.ExerciseEntry, pace: PlanPace?, goal: TrainingGoal,
                                 history: [Workout], oneRMKg: Double?) throws -> ProgressionRule? {
        let asked = entry.rule != nil || entry.start_weight != nil
        guard asked || pace != nil else { return nil }
        guard exercise.exerciseType == .weightedReps else {
            if asked {
                throw AIToolError("'\(exercise.name)' is not a weighted rep exercise, so it cannot take a progression rule. Leave rule and start_weight out for it.")
            }
            return nil
        }
        if let supplied = entry.rule { return try supplied.rule() }
        let isCompound = exercise.category == .barbell || exercise.category == .dumbbell
        func preset(_ start: ProgressionTarget?) -> ProgressionRule {
            ProgressionRuleEngine.defaultRule(pace: pace ?? .standard, goal: goal, category: exercise.category,
                muscle: exercise.primaryMuscleGroup, isCompound: isCompound, start: start)
        }
        let base = preset(nil)
        var start: ProgressionTarget?
        if let weight = try entry.start_weight?.kilograms(for: exercise) {
            start = .init(weightKg: weight, reps: entry.start_reps ?? base.startReps)
        } else {
            start = ProgressionRuleEngine.suggestedStart(exerciseID: exercise.id, workouts: history,
                range: base.minReps...base.maxReps, incrementKg: base.incrementKg,
                weightIsOptional: exercise.category == .resistanceBand)
        }
        // A band has no weight to estimate: it starts at the bottom of its rep range.
        if start == nil, exercise.category == .resistanceBand { start = .init(weightKg: 0, reps: base.startReps) }
        if start == nil, let oneRMKg, oneRMKg > 0 {
            // Bottom of the range with two reps in reserve.
            let step = base.incrementKg > 0 ? base.incrementKg : 2.5
            let weight = oneRMKg / (1 + Double(base.minReps + 2) / 30)
            start = .init(weightKg: max(step, (weight / step).rounded(.down) * step), reps: base.minReps)
        }
        guard let start else {
            throw AIToolError("No start weight known for '\(exercise.name)' (no workouts or records). Provide start_weight for it — ask the user if needed.")
        }
        let rule = preset(start)
        do { try rule.validate() } catch { throw AIToolError(error.localizedDescription) }
        return rule
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)

        let trimmedName = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AIToolError("Plan name must not be empty") }
        if let weeks = args.duration_weeks, !(4...52).contains(weeks) { throw AIToolError("duration_weeks must be 4–52") }
        guard (1...7).contains(args.weekly_frequency) else {
            throw AIToolError("weekly_frequency must be 1-7")
        }
        guard !args.exercises.isEmpty else { throw AIToolError("A plan needs at least one exercise") }

        // training_days drive the actual sessions per week — a mismatch with
        // weekly_frequency would make the app's weekly goal impossible to hit.
        var trainingDays = args.training_days
        if let days = trainingDays {
            guard days.allSatisfy({ (1...7).contains($0) }) else {
                throw AIToolError("training_days must use calendar weekdays 1 (Sunday) to 7 (Saturday)")
            }
            guard Set(days).count == days.count else {
                throw AIToolError("training_days must not repeat a day")
            }
            guard days.count == args.weekly_frequency else {
                throw AIToolError("weekly_frequency (\(args.weekly_frequency)) must equal the number of training_days (\(days.count))")
            }
        }

        let goal = try parseEnum(TrainingGoal.self, args.goal, field: "goal")
        let programType = try args.program_type.map { try parseEnum(ProgramType.self, $0, field: "program_type") }
        var startDate = Date()
        if let dateString = args.start_date {
            guard let parsed = AIJSON.parseDate(dateString) else {
                throw AIToolError("start_date must be yyyy-MM-dd")
            }
            let today = Calendar.current.startOfDay(for: Date())
            let horizon = Calendar.current.date(byAdding: .year, value: 2, to: today) ?? today
            guard parsed >= today else {
                throw AIToolError("start_date must be today or later — a past start would create an already-overdue plan")
            }
            guard parsed <= horizon else {
                throw AIToolError("start_date must be within the next 2 years")
            }
            startDate = parsed
        }

        let pace = try args.pace.map { try parseEnum(PlanPace.self, $0, field: "pace") }
        if let every = args.deload_every_weeks, every != 0, !(2...12).contains(every) {
            throw AIToolError("deload_every_weeks must be 2–12, or 0 for no scheduled deloads")
        }
        let catalog = try await exerciseRepository.fetchAll()
        let history = pace == nil ? [] : ((try? await workoutRepository?.fetchAll()) ?? [])
        var selections: [AIPlanParameters.ExerciseSelection] = []
        for entry in args.exercises {
            let exercise = try ExerciseNameResolver.resolve(name: entry.exercise_name, in: catalog)
            var oneRMKg = try entry.estimated_1rm?.kilograms(for: exercise)
            var fromPersonalRecord = false
            if oneRMKg == nil {
                // PRs store values in kg.
                let records = try await personalRecordRepository.fetchForExercise(exercise.id).matching(exercise).bestPerType()
                oneRMKg = records.first { $0.recordType == .estimatedOneRepMax }?.value
                    ?? records.first { $0.recordType == .maxWeight }?.value
                fromPersonalRecord = oneRMKg != nil
            }
            let rule = try progressionRule(for: exercise, entry: entry, pace: pace, goal: goal, history: history, oneRMKg: oneRMKg)
            if oneRMKg == nil, let rule {
                // A rule-driven lift still carries an estimate for the analytics that read one.
                oneRMKg = (rule.startWeightKg * (1 + Double(rule.startReps) / 30)).rounded(toNearest: 2.5)
            }
            guard let oneRMKg else {
                if exercise.category == .resistanceBand {
                    throw AIToolError("'\(exercise.name)' is a band exercise with no weight to estimate. Set pace, or give it a rule with increment_kg 0 and start_weight_kg 0: it then progresses on reps alone.")
                }
                throw AIToolError("No 1RM known for '\(exercise.name)' (no personal records). Provide estimated_1rm for it — ask the user if needed. Without one, every set would be prescribed at 0 kg.")
            }
            if entry.wave_sets != nil || entry.wave_reps != nil {
                guard rule == nil else {
                    throw AIToolError("wave_sets and wave_reps only apply to the percentage wave. '\(exercise.name)' has a progression rule: put its sets and reps in the rule.")
                }
                guard entry.wave_sets.map((1...20).contains) ?? true, entry.wave_reps.map((1...100).contains) ?? true else {
                    throw AIToolError("wave_sets must be 1–20 and wave_reps 1–100")
                }
            }
            var selection = AIPlanParameters.ExerciseSelection(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                primaryMuscleGroup: exercise.primaryMuscleGroup,
                category: exercise.category,
                estimated1RMKg: oneRMKg,
                oneRMFromPersonalRecord: fromPersonalRecord,
                weightRecording: exercise.weightRecording
            )
            selection.progression = rule
            selection.waveSets = entry.wave_sets
            selection.waveReps = entry.wave_reps
            selections.append(selection)
        }

        var daySplits: [AIPlanParameters.DaySplit]?
        if let splitEntries = args.day_splits, !splitEntries.isEmpty {
            let splitDays = splitEntries.map(\.training_day)
            guard splitDays.allSatisfy({ (1...7).contains($0) }) else {
                throw AIToolError("day_splits training_day values must be calendar weekdays 1 (Sunday) to 7 (Saturday)")
            }
            guard Set(splitDays).count == splitDays.count else {
                throw AIToolError("day_splits must not repeat a training_day")
            }
            if let days = trainingDays {
                // A partial schedule is allowed — unlisted training days become
                // rest/empty sessions, matching the app's structured flow.
                guard Set(splitDays).isSubset(of: Set(days)) else {
                    throw AIToolError("day_splits days must all be training_days")
                }
            } else {
                guard splitDays.count == args.weekly_frequency else {
                    throw AIToolError("weekly_frequency (\(args.weekly_frequency)) must equal the number of day_splits (\(splitDays.count)) when training_days is omitted")
                }
                trainingDays = splitDays.sorted()
            }

            let userTemplates = try await templateRepository.fetchAll()
            let selectionsByName = Dictionary(
                selections.map { ($0.exerciseName.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            daySplits = try splitEntries.map { entry in
                var template: WorkoutTemplate?
                if let templateName = entry.template_name, !templateName.isEmpty {
                    template = try TemplateNameResolver.resolve(name: templateName, in: userTemplates)
                }
                let names = entry.exercise_names ?? []
                let others = try (entry.other_exercises ?? []).map { other -> AIPlanParameters.FixedExercise in
                    let exercise = try ExerciseNameResolver.resolve(name: other.exercise_name, in: catalog)
                    guard (1...20).contains(other.sets) else { throw AIToolError("other_exercises sets must be 1–20") }
                    if let reps = other.reps, !(1...100).contains(reps) { throw AIToolError("other_exercises reps must be 1–100") }
                    if let seconds = other.duration_seconds, !(1...86400).contains(seconds) { throw AIToolError("duration_seconds must be 1–86,400") }
                    if let meters = other.distance_meters, !(0.1...1_000_000).contains(meters) { throw AIToolError("distance_meters must be a positive number of metres") }
                    let weight = try other.weight?.kilograms(for: exercise)
                    switch exercise.exerciseType {
                    case .weightedReps, .bodyweightReps:
                        guard let reps = other.reps, other.duration_seconds == nil, other.distance_meters == nil else {
                            throw AIToolError("'\(exercise.name)' is counted in reps: give reps (and weight if it has one), not time or distance")
                        }
                        return .init(exerciseID: exercise.id, exerciseName: exercise.name, sets: other.sets, reps: reps, weightKg: weight ?? 0)
                    case .duration:
                        guard let seconds = other.duration_seconds, other.reps == nil else {
                            throw AIToolError("'\(exercise.name)' is timed: give duration_seconds, not reps")
                        }
                        return .init(exerciseID: exercise.id, exerciseName: exercise.name, sets: other.sets, durationSeconds: seconds)
                    case .distance, .cardio, .weightedCardio:
                        guard other.duration_seconds != nil || other.distance_meters != nil, other.reps == nil else {
                            throw AIToolError("'\(exercise.name)' needs duration_seconds or distance_meters, not reps")
                        }
                        return .init(exerciseID: exercise.id, exerciseName: exercise.name, sets: other.sets,
                            weightKg: exercise.exerciseType == .weightedCardio ? (weight ?? 0) : nil,
                            durationSeconds: other.duration_seconds, distanceMeters: other.distance_meters)
                    }
                }
                guard template != nil || !names.isEmpty || !others.isEmpty else {
                    throw AIToolError("Each day_splits entry needs exercise_names, a template_name, other_exercises, or a mix")
                }
                let resolved = try names.map { name -> AIPlanParameters.ExerciseSelection in
                    guard let selection = selectionsByName[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] else {
                        throw AIToolError("day_splits references '\(name)', which is not in this plan's exercises list")
                    }
                    return selection
                }
                var split = AIPlanParameters.DaySplit(
                    dayOfWeek: entry.training_day,
                    exerciseIDs: resolved.map(\.exerciseID),
                    exerciseNames: resolved.map(\.exerciseName),
                    templateID: template?.id,
                    templateName: template?.name
                )
                split.otherExercises = others.isEmpty ? nil : others
                return split
            }
        }

        // A deload week's own schedule: any weekday, a template or a training day's workout.
        var deloadSplits: [AIPlanParameters.DeloadSplit]?
        if let entries = args.deload_schedule, !entries.isEmpty {
            guard args.deload_days?.isEmpty ?? true else { throw AIToolError("Use deload_days or deload_schedule, not both") }
            guard entries.allSatisfy({ (1...7).contains($0.day) }), Set(entries.map(\.day)).count == entries.count else {
                throw AIToolError("deload_schedule needs one entry per weekday, 1 (Sunday) to 7 (Saturday)")
            }
            let userTemplates = try await templateRepository.fetchAll()
            deloadSplits = try entries.map { entry in
                let templateName = entry.template_name.flatMap { $0.isEmpty ? nil : $0 }
                guard (templateName == nil) != (entry.same_as_day == nil) else {
                    throw AIToolError("Each deload_schedule entry needs either template_name or same_as_day")
                }
                if let source = entry.same_as_day {
                    let training = trainingDays ?? ProgressionPlanViewModel.defaultDaySpread[args.weekly_frequency] ?? []
                    guard training.contains(source) else { throw AIToolError("same_as_day \(source) is not a training day of this plan") }
                    return .init(dayOfWeek: entry.day, sameAsDay: source)
                }
                let template = try TemplateNameResolver.resolve(name: templateName ?? "", in: userTemplates)
                return .init(dayOfWeek: entry.day, templateID: template.id, templateName: template.name)
            }
        }

        var deloadDays: [Int]?
        if let days = args.deload_days, !days.isEmpty {
            guard days.allSatisfy({ (1...7).contains($0) }) else {
                throw AIToolError("deload_days must use calendar weekdays 1 (Sunday) to 7 (Saturday)")
            }
            guard Set(days).count == days.count else {
                throw AIToolError("deload_days must not repeat a day")
            }
            if let training = trainingDays {
                guard Set(days).isSubset(of: Set(training)) else {
                    throw AIToolError("deload_days must be a subset of the training days")
                }
            }
            deloadDays = days.sorted()
        }

        let trainingStatus = try args.training_status.map {
            try parseEnum(TrainingStatus.self, $0, field: "training_status")
        }

        var parameters = AIPlanParameters(
            name: trimmedName,
            primaryGoal: goal,
            programType: programType,
            weeklyFrequency: args.weekly_frequency,
            trainingDays: trainingDays,
            startDate: startDate,
            exercises: selections,
            daySplits: daySplits,
            deloadDays: deloadDays,
            trainingStatus: trainingStatus, durationWeeks: args.duration_weeks
        )
        parameters.pace = selections.contains { $0.progression != nil } ? (pace ?? .standard) : nil
        parameters.deloadEveryWeeks = args.deload_every_weeks ?? PlanConfiguration.defaultDeloadEveryWeeks
        parameters.deloadSplits = deloadSplits

        let rules = selections.compactMap { selection in
            selection.progression.map { JSONValue.string("\(selection.exerciseName): start \($0.startWeightKg) kg × \($0.startReps). \($0.summary(unit: .kg))") }
        }
        let receipt: String = rules.isEmpty
            ? proposalReceipt(kind: "training_plan", name: parameters.name)
            : AIJSON.string(.object([
                "status": .string("proposal_presented"), "kind": .string("training_plan"), "name": .string(parameters.name),
                "progression_rules": .array(rules),
                "note": .string("The user sees a card with Save/Discard and these rules. Do not claim it was saved.")
            ]))
        return AIToolResult(
            outputForModel: receipt,
            draft: .plan(parameters),
            activityLabel: "Drafted plan '\(parameters.name)'"
        )
    }
}
