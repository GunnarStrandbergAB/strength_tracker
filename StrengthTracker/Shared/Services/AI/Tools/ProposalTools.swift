import Foundation

// Proposal tools: validate and build real domain objects, but NEVER write.
// The draft is carded in the chat; the user's Save routes it through the same
// seams the UI uses.

/// Weight argument with an explicit unit; normalized to kg at the tool boundary.
struct WeightArgument: Decodable {
    var value: Double
    var unit: String

    func kilograms() throws -> Double {
        switch unit.lowercased() {
        case "kg": return value
        case "lbs", "lb": return WeightUnit.lbs.toKg(value)
        default: throw AIToolError("weight unit must be \"kg\" or \"lbs\", got '\(unit)'")
        }
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
                "loading_type": AIToolRegistry.enumSchema(LoadingType.self)
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
            loadingType: try args.loading_type.map { try parseEnum(LoadingType.self, $0, field: "loading_type") }
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
                targetWeightKg: try entry.target_weight?.kilograms(),
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

    public init(
        exerciseRepository: any ExerciseRepository,
        personalRecordRepository: any PersonalRecordRepository,
        templateRepository: any TemplateRepository
    ) {
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
    Use day_splits to assign exercises and/or one of the user's templates to specific \
    days (see list_templates; a linked template means that day's workout starts from \
    the full template with progression targets overlaid). Without day_splits, every \
    exercise trains on every training day. deload_days picks which weekdays deload \
    weeks use (subset of training days; advanced lifters get no scheduled deloads). \
    training_status overrides the app's automatic level detection — set it only when \
    the user states their level.
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
                "estimated_1rm": weightSchema
            ],
            required: ["exercise_name"]
        )
        let daySplitSchema = AIToolRegistry.objectSchema(
            properties: [
                "training_day": AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7"),
                "exercise_names": AIToolRegistry.arraySchema(
                    of: AIToolRegistry.stringSchema("Exercise name from this plan's exercises list (may be empty when template_name is set)")
                ),
                "template_name": AIToolRegistry.stringSchema("Exact name of one of the user's templates (see list_templates) to base this day's workout on")
            ],
            required: ["training_day"]
        )
        return AIToolRegistry.objectSchema(
            properties: [
                "name": AIToolRegistry.stringSchema("Plan name"),
                "goal": AIToolRegistry.enumSchema(TrainingGoal.self, description: "Primary training goal"),
                "program_type": AIToolRegistry.enumSchema(ProgramType.self, description: "Periodization style (omit to let the app choose)"),
                "weekly_frequency": AIToolRegistry.integerSchema("Training days per week (1-7); must equal the number of training_days when those are given"),
                "training_days": AIToolRegistry.arraySchema(
                    of: AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7"),
                    description: "Specific training days; omit for defaults"
                ),
                "deload_days": AIToolRegistry.arraySchema(
                    of: AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7"),
                    description: "Weekdays deload weeks train on — must be a subset of the training days; omit to deload on all training days"
                ),
                "training_status": AIToolRegistry.enumSchema(
                    TrainingStatus.self,
                    description: "The user's training level — set only when the user states it; omit to auto-detect"
                ),
                "start_date": AIToolRegistry.stringSchema("Start date yyyy-MM-dd (today or later; default today)"),
                "exercises": AIToolRegistry.arraySchema(of: exerciseSchema, description: "Exercises to progress, in priority order"),
                "day_splits": AIToolRegistry.arraySchema(
                    of: daySplitSchema,
                    description: "Optional split: which exercises/template each day uses. Days must be training days; unlisted training days become rest/empty sessions."
                )
            ],
            required: ["name", "goal", "weekly_frequency", "exercises"]
        )
    }

    private struct Arguments: Decodable {
        struct ExerciseEntry: Decodable {
            var exercise_name: String
            var estimated_1rm: WeightArgument?
        }

        struct DaySplitEntry: Decodable {
            var training_day: Int
            var exercise_names: [String]?
            var template_name: String?
        }

        var name: String
        var goal: String
        var program_type: String?
        var weekly_frequency: Int
        var training_days: [Int]?
        var deload_days: [Int]?
        var training_status: String?
        var start_date: String?
        var exercises: [ExerciseEntry]
        var day_splits: [DaySplitEntry]?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)

        let trimmedName = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AIToolError("Plan name must not be empty") }
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

        let catalog = try await exerciseRepository.fetchAll()
        var selections: [AIPlanParameters.ExerciseSelection] = []
        for entry in args.exercises {
            let exercise = try ExerciseNameResolver.resolve(name: entry.exercise_name, in: catalog)
            var oneRMKg = try entry.estimated_1rm?.kilograms()
            var fromPersonalRecord = false
            if oneRMKg == nil {
                // PRs store values in kg.
                let records = try await personalRecordRepository.fetchForExercise(exercise.id).bestPerType()
                oneRMKg = records.first { $0.recordType == .estimatedOneRepMax }?.value
                    ?? records.first { $0.recordType == .maxWeight }?.value
                fromPersonalRecord = oneRMKg != nil
            }
            guard let oneRMKg else {
                throw AIToolError("No 1RM known for '\(exercise.name)' (no personal records). Provide estimated_1rm for it — ask the user if needed. Without one, every set would be prescribed at 0 kg.")
            }
            selections.append(AIPlanParameters.ExerciseSelection(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                primaryMuscleGroup: exercise.primaryMuscleGroup,
                category: exercise.category,
                estimated1RMKg: oneRMKg,
                oneRMFromPersonalRecord: fromPersonalRecord
            ))
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
                guard template != nil || !names.isEmpty else {
                    throw AIToolError("Each day_splits entry needs exercise_names, a template_name, or both")
                }
                let resolved = try names.map { name -> AIPlanParameters.ExerciseSelection in
                    guard let selection = selectionsByName[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] else {
                        throw AIToolError("day_splits references '\(name)', which is not in this plan's exercises list")
                    }
                    return selection
                }
                return AIPlanParameters.DaySplit(
                    dayOfWeek: entry.training_day,
                    exerciseIDs: resolved.map(\.exerciseID),
                    exerciseNames: resolved.map(\.exerciseName),
                    templateID: template?.id,
                    templateName: template?.name
                )
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

        let parameters = AIPlanParameters(
            name: trimmedName,
            primaryGoal: goal,
            programType: programType,
            weeklyFrequency: args.weekly_frequency,
            trainingDays: trainingDays,
            startDate: startDate,
            exercises: selections,
            daySplits: daySplits,
            deloadDays: deloadDays,
            trainingStatus: trainingStatus
        )

        return AIToolResult(
            outputForModel: proposalReceipt(kind: "training_plan", name: parameters.name),
            draft: .plan(parameters),
            activityLabel: "Drafted plan '\(parameters.name)'"
        )
    }
}
