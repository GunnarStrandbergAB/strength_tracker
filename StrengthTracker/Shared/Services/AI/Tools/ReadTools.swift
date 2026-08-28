import Foundation

// Read-only tools. Outputs are compact JSON with weights in kg (annotated once
// per payload) and ISO dates, to keep token cost low.

// MARK: - Exercise name resolution

/// Resolves model-provided exercise names against the catalog. Exact
/// case-insensitive match; misses return the closest names so the model can
/// self-correct.
@MainActor
public enum ExerciseNameResolver {
    public static func resolve(name: String, in exercises: [Exercise]) throws -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = exercises.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        let query = trimmed.lowercased()
        let suggestions = exercises
            .map { (exercise: $0, score: similarity(query: query, candidate: $0.name.lowercased())) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map(\.exercise.name)
        let hint = suggestions.isEmpty
            ? "Use list_exercises to see available names."
            : "Closest matches: \(suggestions.joined(separator: ", "))."
        throw AIToolError("No exercise named '\(trimmed)'. \(hint)")
    }

    private static func similarity(query: String, candidate: String) -> Int {
        if candidate.contains(query) || query.contains(candidate) { return 3 }
        let queryWords = Set(query.split(separator: " ").map(String.init))
        let candidateWords = Set(candidate.split(separator: " ").map(String.init))
        return queryWords.intersection(candidateWords).count
    }
}

// MARK: - list_exercises

@MainActor
public final class ListExercisesTool: AITool {
    private let exerciseRepository: any ExerciseRepository

    public init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    public let name = "list_exercises"
    public let description = """
    List the exercise catalog. Each entry is "name|primary_muscle|category|type" (custom \
    exercises end with |custom). Filter with query (substring of the name) or muscle_group.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "query": AIToolRegistry.stringSchema("Case-insensitive substring of the exercise name"),
            "muscle_group": AIToolRegistry.enumSchema(MuscleGroup.self, description: "Filter by primary muscle group"),
            "include_custom": AIToolRegistry.boolSchema("Include the user's custom exercises (default true)")
        ])
    }

    private struct Arguments: Decodable {
        var query: String?
        var muscle_group: String?
        var include_custom: Bool?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)

        var muscleGroup: MuscleGroup?
        if let raw = args.muscle_group {
            guard let parsed = MuscleGroup(rawValue: raw) else {
                throw AIToolError("Unknown muscle_group '\(raw)'. Valid values: \(MuscleGroup.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            muscleGroup = parsed
        }

        var exercises = try await exerciseRepository.fetchAll().filter { !$0.isArchived }
        if args.include_custom == false {
            exercises = exercises.filter { !$0.isCustom }
        }
        if let muscleGroup {
            exercises = exercises.filter { $0.primaryMuscleGroup == muscleGroup }
        }
        if let query = args.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            exercises = exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        let lines = exercises.map { exercise -> JSONValue in
            var line = "\(exercise.name)|\(exercise.primaryMuscleGroup.rawValue)|\(exercise.category.rawValue)|\(exercise.exerciseType.rawValue)"
            if exercise.isCustom { line += "|custom" }
            return .string(line)
        }

        let output = AIJSON.string(.object([
            "count": .number(Double(lines.count)),
            "exercises": .array(lines)
        ]))
        return AIToolResult(
            outputForModel: output,
            activityLabel: "Browsed \(lines.count) exercises"
        )
    }
}

// MARK: - get_training_history

@MainActor
public final class GetTrainingHistoryTool: AITool {
    static let maxWorkouts = 25

    private let workoutRepository: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository
    private let userPreferencesService: UserPreferencesService

    public init(
        workoutRepository: any WorkoutRepository,
        exerciseRepository: any ExerciseRepository,
        userPreferencesService: UserPreferencesService
    ) {
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
        self.userPreferencesService = userPreferencesService
    }

    public let name = "get_training_history"
    public let description = """
    Completed workouts, newest first. Sets are "weight_kg x reps" (or seconds/meters for \
    timed/cardio work). Returns at most 25 workouts — narrow with dates or exercise_name \
    when truncated is true.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "last_n": AIToolRegistry.integerSchema("Number of recent workouts (default 10, max 25)"),
            "start_date": AIToolRegistry.stringSchema("Start date yyyy-MM-dd (inclusive)"),
            "end_date": AIToolRegistry.stringSchema("End date yyyy-MM-dd (inclusive)"),
            "exercise_name": AIToolRegistry.stringSchema("Only workouts containing this exercise; only its sets are returned")
        ])
    }

    private struct Arguments: Decodable {
        var last_n: Int?
        var start_date: String?
        var end_date: String?
        var exercise_name: String?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)

        var workouts: [Workout]
        if args.start_date != nil || args.end_date != nil {
            guard let startString = args.start_date, let start = AIJSON.parseDate(startString) else {
                throw AIToolError("start_date must be yyyy-MM-dd and is required when end_date is set")
            }
            let end = args.end_date.flatMap { AIJSON.parseDate($0) } ?? Date()
            workouts = try await workoutRepository.fetchByDateRange(
                start, Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            )
        } else {
            workouts = try await workoutRepository.fetchAll()
        }

        workouts = workouts
            .filter { $0.completedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }

        var filterExercise: Exercise?
        if let exerciseName = args.exercise_name, !exerciseName.isEmpty {
            filterExercise = try ExerciseNameResolver.resolve(
                name: exerciseName, in: try await exerciseRepository.fetchAll()
            )
            workouts = workouts.filter { workout in
                workout.exercises.contains { $0.exercise.id == filterExercise?.id }
            }
        }

        let limit = min(max(args.last_n ?? 10, 1), Self.maxWorkouts)
        let truncated = workouts.count > limit
        workouts = Array(workouts.prefix(limit))

        let bodyWeight = userPreferencesService.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
        let summaries = workouts.map { workout in
            summarize(workout, bodyWeightKg: bodyWeight, only: filterExercise)
        }

        let output = AIJSON.string(.object([
            "unit": .string("kg"),
            "count": .number(Double(summaries.count)),
            "truncated": .bool(truncated),
            "workouts": .array(summaries)
        ]))
        return AIToolResult(
            outputForModel: output,
            activityLabel: "Read \(summaries.count) workout\(summaries.count == 1 ? "" : "s")"
        )
    }

    private func summarize(_ workout: Workout, bodyWeightKg: Double, only filter: Exercise?) -> JSONValue {
        let exercises = workout.exercises
            .filter { filter == nil || $0.exercise.id == filter?.id }
            .sorted { $0.order < $1.order }
            .compactMap { exercise -> JSONValue? in
                let sets = exercise.sets
                    .filter(\.isCompleted)
                    .sorted { $0.order < $1.order }
                    .map(setSummary)
                guard !sets.isEmpty else { return nil }
                return .object([
                    "n": .string(exercise.exercise.name),
                    "sets": .string(sets.joined(separator: ","))
                ])
            }

        var summary: [String: JSONValue] = [
            "d": .string(AIJSON.dateString(workout.startedAt)),
            "name": .string(workout.name),
            "vol_kg": .number(AIJSON.round1(workout.totalVolume(bodyWeightKg: bodyWeightKg))),
            "ex": .array(exercises)
        ]
        if let duration = workout.duration {
            summary["dur_min"] = .number((duration / 60).rounded())
        }
        if workout.isDeload {
            summary["deload"] = .bool(true)
        }
        return .object(summary)
    }

    private func setSummary(_ set: ExerciseSet) -> String {
        if let weight = set.weight, let reps = set.reps {
            let weightString = weight == weight.rounded()
                ? String(Int(weight)) : String(format: "%.1f", weight)
            return "\(weightString)x\(reps)"
        }
        if let reps = set.reps {
            return "x\(reps)"
        }
        if let duration = set.durationSeconds {
            return "\(duration)s"
        }
        if let distance = set.distanceMeters {
            return "\(Int(distance))m"
        }
        return "-"
    }
}

// MARK: - get_analytics_insights

@MainActor
public final class GetAnalyticsInsightsTool: AITool {
    private let analyticsService: WorkoutAnalyticsService

    public init(analyticsService: WorkoutAnalyticsService) {
        self.analyticsService = analyticsService
    }

    public let name = "get_analytics_insights"
    public let description = """
    Aggregated training analytics: plateaus, muscle balance, training load (ACWR), \
    deload recommendation, and notable highlights for a recent time window.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "time_window_days": AIToolRegistry.integerSchema("Analysis window in days (default 30)")
        ])
    }

    private struct Arguments: Decodable {
        var time_window_days: Int?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let days = min(max(args.time_window_days ?? 30, 7), 365)
        let insights = try await analyticsService.generateInsights(timeWindow: TimeInterval(days) * 86_400)

        var payload: [String: JSONValue] = [
            "window_days": .number(Double(days)),
            "workout_count": .number(Double(insights.workoutCount))
        ]

        if !insights.plateaus.isEmpty {
            payload["plateaus"] = .array(insights.plateaus.map { plateau in
                .object([
                    "exercise": .string(plateau.exerciseName ?? "unknown"),
                    "weeks_stalled": .number(Double(plateau.consecutiveWeeksStalled))
                ])
            })
        }

        if let balance = insights.muscleBalance {
            payload["muscle_balance"] = .object([
                "score": .number(AIJSON.round1(balance.overallBalanceScore)),
                "imbalances": .array(balance.imbalances.map { imbalance in
                    .object([
                        "high": .string(imbalance.primaryGroup),
                        "low": .string(imbalance.comparisonGroup),
                        "ratio": .number(AIJSON.round1(imbalance.ratio)),
                        "severity": .string(String(describing: imbalance.severity))
                    ])
                })
            ])
        }

        if let load = insights.trainingLoad {
            payload["training_load"] = .object([
                "acwr": .number(AIJSON.round1(load.acwr)),
                "zone": .string(load.loadZone.rawValue)
            ])
        }

        if let deload = insights.deloadRecommendation {
            payload["deload"] = .object([
                "urgency": .number(AIJSON.round1(deload.urgencyScore)),
                "action": .string(deload.suggestedAction)
            ])
        }

        if !insights.highlights.isEmpty {
            payload["highlights"] = .array(insights.highlights.prefix(5).map { highlight in
                .object(["title": .string(highlight.title), "detail": .string(highlight.detail)])
            })
        }

        return AIToolResult(
            outputForModel: AIJSON.string(.object(payload)),
            activityLabel: "Analyzed \(insights.workoutCount) workouts"
        )
    }
}

// MARK: - get_personal_records

@MainActor
public final class GetPersonalRecordsTool: AITool {
    private let personalRecordRepository: any PersonalRecordRepository
    private let exerciseRepository: any ExerciseRepository

    public init(
        personalRecordRepository: any PersonalRecordRepository,
        exerciseRepository: any ExerciseRepository
    ) {
        self.personalRecordRepository = personalRecordRepository
        self.exerciseRepository = exerciseRepository
    }

    public let name = "get_personal_records"
    public let description = """
    Personal records. With exercise_name: all record types for that exercise. Without: \
    the best estimated 1RM (or max weight) per exercise that has records.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "exercise_name": AIToolRegistry.stringSchema("Exact exercise name (see list_exercises)")
        ])
    }

    private struct Arguments: Decodable {
        var exercise_name: String?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let exercises = try await exerciseRepository.fetchAll()

        var records: [JSONValue] = []
        if let exerciseName = args.exercise_name, !exerciseName.isEmpty {
            let exercise = try ExerciseNameResolver.resolve(name: exerciseName, in: exercises)
            let best = try await personalRecordRepository.fetchForExercise(exercise.id).bestPerType()
            records = best
                .sorted { $0.recordType.rawValue < $1.recordType.rawValue }
                .map { record in recordJSON(record, exerciseName: exercise.name) }
        } else {
            for exercise in exercises where !exercise.isArchived {
                let best = try await personalRecordRepository.fetchForExercise(exercise.id).bestPerType()
                let headline = best.first { $0.recordType == .estimatedOneRepMax }
                    ?? best.first { $0.recordType == .maxWeight }
                    ?? best.first
                if let headline {
                    records.append(recordJSON(headline, exerciseName: exercise.name))
                }
            }
        }

        let output = AIJSON.string(.object([
            "unit": .string("kg"),
            "count": .number(Double(records.count)),
            "records": .array(records)
        ]))
        return AIToolResult(
            outputForModel: output,
            activityLabel: "Checked \(records.count) record\(records.count == 1 ? "" : "s")"
        )
    }

    private func recordJSON(_ record: PersonalRecord, exerciseName: String) -> JSONValue {
        .object([
            "exercise": .string(exerciseName),
            "type": .string(record.recordType.rawValue),
            "value": .number(AIJSON.round1(record.value)),
            "date": .string(AIJSON.dateString(record.achievedAt))
        ])
    }
}

// MARK: - get_active_plan

@MainActor
public final class GetActivePlanTool: AITool {
    private let progressionPlanRepository: any ProgressionPlanRepository
    private let userPreferencesService: UserPreferencesService

    public init(
        progressionPlanRepository: any ProgressionPlanRepository,
        userPreferencesService: UserPreferencesService
    ) {
        self.progressionPlanRepository = progressionPlanRepository
        self.userPreferencesService = userPreferencesService
    }

    public let name = "get_active_plan"
    public let description = "The user's active progression plan (goal, week, frequency, exercises with current 1RMs), or null if none."

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [:])
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        guard let plan = try await progressionPlanRepository.fetchActive() else {
            return AIToolResult(
                outputForModel: #"{"active_plan":null}"#,
                activityLabel: "No active plan"
            )
        }

        let currentWeekNumber = plan.currentWeek?.absoluteWeekNumber
        // PlanExercise 1RM values are stored in the user's display unit.
        let unit = userPreferencesService.weightUnit.rawValue
        let exercises = plan.exercises.sorted { $0.order < $1.order }.map { exercise -> JSONValue in
            .object([
                "n": .string(exercise.exerciseName),
                "current_1rm": .number(AIJSON.round1(exercise.current1RM))
            ])
        }

        var payload: [String: JSONValue] = [
            "name": .string(plan.name),
            "goal": .string(plan.primaryGoal.rawValue),
            "program_type": .string(plan.programType.rawValue),
            "weekly_frequency": .number(Double(plan.weeklyFrequency)),
            "total_weeks": .number(Double(plan.totalWeeks)),
            "start_date": .string(AIJSON.dateString(plan.startDate)),
            "unit_for_1rm": .string(unit),
            "exercises": .array(exercises)
        ]
        if let currentWeekNumber {
            payload["current_week"] = .number(Double(currentWeekNumber))
        }
        if let trainingDays = plan.trainingDays {
            payload["training_days"] = .array(trainingDays.map { .number(Double($0)) })
        }

        return AIToolResult(
            outputForModel: AIJSON.string(.object(["active_plan": .object(payload)])),
            activityLabel: "Checked plan '\(plan.name)'"
        )
    }
}
