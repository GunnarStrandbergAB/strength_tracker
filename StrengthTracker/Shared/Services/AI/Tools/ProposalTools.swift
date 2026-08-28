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

private func proposalReceipt(kind: String, name: String) -> String {
    AIJSON.string(.object([
        "status": .string("proposal_presented"),
        "kind": .string(kind),
        "name": .string(name),
        "note": .string("The user sees a card with Save/Discard. Do not claim it was saved.")
    ]))
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
        if let duplicate = existing.first(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
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

    public init(
        exerciseRepository: any ExerciseRepository,
        personalRecordRepository: any PersonalRecordRepository
    ) {
        self.exerciseRepository = exerciseRepository
        self.personalRecordRepository = personalRecordRepository
    }

    public let name = "propose_training_plan"
    public let description = """
    Propose a multi-week periodized training plan. Shows the user a Save/Discard card; \
    on save the app's program generator deterministically builds blocks, weeks, and \
    sessions from these parameters. Exercises must be exact catalog names. Provide \
    estimated_1rm where you know it; otherwise the user's PRs fill it in.
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
        return AIToolRegistry.objectSchema(
            properties: [
                "name": AIToolRegistry.stringSchema("Plan name"),
                "goal": AIToolRegistry.enumSchema(TrainingGoal.self, description: "Primary training goal"),
                "program_type": AIToolRegistry.enumSchema(ProgramType.self, description: "Periodization style (omit to let the app choose)"),
                "weekly_frequency": AIToolRegistry.integerSchema("Training days per week (1-7)"),
                "training_days": AIToolRegistry.arraySchema(
                    of: AIToolRegistry.integerSchema("Calendar weekday, Sunday=1 … Saturday=7"),
                    description: "Specific training days; omit for defaults"
                ),
                "start_date": AIToolRegistry.stringSchema("Start date yyyy-MM-dd (default today)"),
                "exercises": AIToolRegistry.arraySchema(of: exerciseSchema, description: "Exercises to progress, in priority order")
            ],
            required: ["name", "goal", "weekly_frequency", "exercises"]
        )
    }

    private struct Arguments: Decodable {
        struct ExerciseEntry: Decodable {
            var exercise_name: String
            var estimated_1rm: WeightArgument?
        }

        var name: String
        var goal: String
        var program_type: String?
        var weekly_frequency: Int
        var training_days: [Int]?
        var start_date: String?
        var exercises: [ExerciseEntry]
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)

        let trimmedName = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AIToolError("Plan name must not be empty") }
        guard (1...7).contains(args.weekly_frequency) else {
            throw AIToolError("weekly_frequency must be 1-7")
        }
        guard !args.exercises.isEmpty else { throw AIToolError("A plan needs at least one exercise") }
        if let days = args.training_days {
            guard days.allSatisfy({ (1...7).contains($0) }) else {
                throw AIToolError("training_days must use calendar weekdays 1 (Sunday) to 7 (Saturday)")
            }
        }

        let goal = try parseEnum(TrainingGoal.self, args.goal, field: "goal")
        let programType = try args.program_type.map { try parseEnum(ProgramType.self, $0, field: "program_type") }
        var startDate = Date()
        if let dateString = args.start_date {
            guard let parsed = AIJSON.parseDate(dateString) else {
                throw AIToolError("start_date must be yyyy-MM-dd")
            }
            startDate = parsed
        }

        let catalog = try await exerciseRepository.fetchAll()
        var selections: [AIPlanParameters.ExerciseSelection] = []
        for entry in args.exercises {
            let exercise = try ExerciseNameResolver.resolve(name: entry.exercise_name, in: catalog)
            var oneRMKg = try entry.estimated_1rm?.kilograms()
            if oneRMKg == nil {
                // PRs store values in kg.
                let records = try await personalRecordRepository.fetchForExercise(exercise.id).bestPerType()
                oneRMKg = records.first { $0.recordType == .estimatedOneRepMax }?.value
                    ?? records.first { $0.recordType == .maxWeight }?.value
            }
            selections.append(AIPlanParameters.ExerciseSelection(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                primaryMuscleGroup: exercise.primaryMuscleGroup,
                category: exercise.category,
                estimated1RMKg: oneRMKg
            ))
        }

        let parameters = AIPlanParameters(
            name: trimmedName,
            primaryGoal: goal,
            programType: programType,
            weeklyFrequency: args.weekly_frequency,
            trainingDays: args.training_days,
            startDate: startDate,
            exercises: selections
        )

        return AIToolResult(
            outputForModel: proposalReceipt(kind: "training_plan", name: parameters.name),
            draft: .plan(parameters),
            activityLabel: "Drafted plan '\(parameters.name)'"
        )
    }
}
