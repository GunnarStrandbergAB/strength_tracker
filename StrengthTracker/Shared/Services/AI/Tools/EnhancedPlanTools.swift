import Foundation

public enum AIToolData {
    /// ISO timestamps and native numeric precision across all detailed read tools.
    public static func json<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }
    public static func optional(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }
}

@MainActor
public final class ProposePlanEditTool: AITool {
    private let viewModel: ProgressionPlanViewModel
    public init(viewModel: ProgressionPlanViewModel) { self.viewModel = viewModel }
    public let name = "propose_plan_edit"
    public let description = "Preview an edit to the active plan; Apply/Cancel card, no write. Read get_active_plan first. Week numbers are displayed calendar weeks. convertDeload replaces training in place; insertDeload extends the schedule without losing sessions. Normal targets use kg, including on deload weeks. Completed/in-progress/past sessions are protected."
    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "operation": AIToolRegistry.enumSchema(PlanEditRequest.Operation.self),
            "scope": AIToolRegistry.enumSchema(PlanEditRequest.Scope.self, description: "session, week (default), or remaining from week"),
            "week": AIToolRegistry.integerSchema("Calendar week from get_active_plan"),
            "destination_week": AIToolRegistry.integerSchema("Destination for moveDeload"),
            "weeks": AIToolRegistry.integerSchema("Number of inserted/repeated weeks, 1–12, default 1"),
            "session_id": AIToolRegistry.stringSchema("Stable planned session UUID"),
            "new_date": AIToolRegistry.stringSchema("Reschedule date yyyy-MM-dd"),
            "template_id": AIToolRegistry.stringSchema("ID from list_templates"),
            "exercise_id": AIToolRegistry.stringSchema("Source library exercise ID from get_active_plan"),
            "replacement_exercise_id": AIToolRegistry.stringSchema("Library ID from list_exercises; swap also requires weight_kg and reps"),
            "sets": AIToolRegistry.integerSchema("1–20 sets"), "reps": AIToolRegistry.integerSchema("1–100 reps"),
            "weight_kg": AIToolRegistry.numberSchema("Normal working weight in kg in the session target’s weightRecording convention (replacement uses the library convention), 0–999.99; never a 1RM or pre-scaled deload weight"),
            "rest_seconds": AIToolRegistry.integerSchema("Normal rest 15–900 seconds"),
            "skipped": AIToolRegistry.boolSchema("For skipSession; false restores the scheduled session")
        ], required: ["operation"])
    }
    private struct Arguments: Decodable {
        var operation: PlanEditRequest.Operation; var scope: PlanEditRequest.Scope?
        var week: Int?; var destination_week: Int?; var weeks: Int?; var session_id: UUID?; var new_date: String?
        var template_id: UUID?; var exercise_id: UUID?; var replacement_exercise_id: UUID?
        var sets: Int?; var reps: Int?; var weight_kg: Double?; var rest_seconds: Int?; var skipped: Bool?
    }
    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let a = try decodeArguments(Arguments.self, from: argumentsJSON)
        let date = a.new_date.flatMap(AIJSON.parseDate)
        if a.new_date != nil && date == nil { throw AIToolError("new_date must be yyyy-MM-dd") }
        let preview = try await viewModel.previewPlanEdit(.init(operation: a.operation, week: a.week, destinationWeek: a.destination_week,
            sessionID: a.session_id, newDate: date, weeks: a.weeks ?? 1, scope: a.scope ?? (a.session_id == nil ? .week : .session),
            templateID: a.template_id, exerciseID: a.exercise_id, replacementExerciseID: a.replacement_exercise_id,
            sets: a.sets, reps: a.reps, weightKg: a.weight_kg, restSeconds: a.rest_seconds, skipped: a.skipped))
        return AIToolResult(outputForModel: AIJSON.string(.object(["status": .string("confirmation_presented"),
            "preview_id": .string(preview.id.uuidString), "summary": .array(preview.summaryLines.map(JSONValue.string))])),
            draft: .action(.init(kind: .editPlan(preview), title: "Update \(preview.planName)?", summaryLines: preview.summaryLines, confirmLabel: "Apply changes")),
            activityLabel: "Previewed plan changes")
    }
}

@MainActor
public final class GetTrainingPreferencesTool: AITool {
    private let preferences: UserPreferencesService
    public init(preferences: UserPreferencesService) { self.preferences = preferences }
    public let name = "get_training_preferences"
    public let description = "Current units, effort metric, rest and deload settings. Deload percentage applies to normal scheduled weight, not 1RM. No API keys or private credentials."
    public var parametersSchema: JSONValue { AIToolRegistry.objectSchema(properties: [:]) }
    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let p = preferences
        return .init(outputForModel: AIJSON.string(.object([
            "weight_unit": .string(p.weightUnit.rawValue), "intensity_metric": .string(p.intensityMetric.rawValue),
            "body_weight_kg": AIToolData.optional(p.bodyWeightKg), "default_rest_seconds": .number(Double(p.defaultRestSeconds)),
            "auto_start_rest": .bool(p.autoStartRestTimer), "deload_weight_percent": .number(Double(p.deloadWeightPercentage)),
            "deload_rest_percent": .number(Double(p.deloadRestPercentage)), "sets_and_reps": .string("preserved by plan deloads"),
            "duration_weeks": .string("New plans: 4–52; insertions extend rather than truncate")
        ])), activityLabel: "Read training preferences")
    }
}
