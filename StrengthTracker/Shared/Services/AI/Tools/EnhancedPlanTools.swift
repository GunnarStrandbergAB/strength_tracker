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
    public let description = "Preview one atomic edit to the active plan. Read get_active_plan first and pass plan_id/version. Use setWeekSchedule for an exact replacement schedule (including [] for rest); removeSessions removes planned work, whereas skipSession records missed work. Use batch for related changes in ONE Apply card. Reusable templates and completed/active workouts are protected."
    private func operationSchema() -> JSONValue {
        let placement = AIToolRegistry.objectSchema(properties: [
            "session_id": AIToolRegistry.stringSchema("Retain this existing session ID from the same week; omit to add a template-based session"),
            "template_id": AIToolRegistry.stringSchema("Template for a new session or explicit replacement"),
            "date": AIToolRegistry.stringSchema("Local date yyyy-MM-dd within the selected week"),
            "label": AIToolRegistry.stringSchema("Optional workout name, without weekday or deload prefix")
        ], required: ["date"])
        let day = AIToolRegistry.objectSchema(properties: [
            "source_weekday": AIToolRegistry.integerSchema("Existing weekday 1=Sunday...7=Saturday to retain; must match exactly one session per week"),
            "weekday": AIToolRegistry.integerSchema("New weekday 1=Sunday...7=Saturday"),
            "template_id": AIToolRegistry.stringSchema("Required for a new weekday without a source; optional replacement otherwise")
        ], required: ["weekday"])
        let contents = AIToolRegistry.objectSchema(properties: [
            "occurrence_id": AIToolRegistry.stringSchema("Existing planned exercise occurrence ID from editable_contents; omit to add"),
            "exercise_id": AIToolRegistry.stringSchema("Library ID, including when retaining an occurrence"),
            "sets": AIToolRegistry.integerSchema("1–20"), "reps": AIToolRegistry.integerSchema("1–100"),
            "weight_kg": AIToolRegistry.numberSchema("Normal weight in this exercise's logging convention; never double side weights"),
            "rest_seconds": AIToolRegistry.integerSchema("15–900 normal seconds"),
            "target_rpe": AIToolRegistry.numberSchema("Target effort 1–10, not a performed effort"),
            "duration_seconds": AIToolRegistry.integerSchema("Time target for timed exercises"),
            "distance_meters": AIToolRegistry.numberSchema("Distance target for distance/cardio exercises"),
            "notes": AIToolRegistry.stringSchema("Exercise instructions")
        ], required: ["exercise_id"])
        return AIToolRegistry.objectSchema(properties: [
            "operation": AIToolRegistry.enumSchema(PlanEditRequest.Operation.self),
            "scope": AIToolRegistry.enumSchema(PlanEditRequest.Scope.self, description: "session, week, or remaining from week"),
            "week": AIToolRegistry.integerSchema("Displayed calendar week from get_active_plan"),
            "end_week": AIToolRegistry.integerSchema("Inclusive final week for a range or recurring schedule change"),
            "destination_week": AIToolRegistry.integerSchema("Destination for moveDeload"),
            "weeks": AIToolRegistry.integerSchema("1–12 inserted/repeated/rest weeks"),
            "session_id": AIToolRegistry.stringSchema("Stable planned session UUID"),
            "session_ids": AIToolRegistry.arraySchema(of: AIToolRegistry.stringSchema("Session UUID"), description: "Exact sessions to remove or edit together"),
            "new_date": AIToolRegistry.stringSchema("Local yyyy-MM-dd: move/add date, shift start date or new finish for shortenPlan"),
            "days": AIToolRegistry.integerSchema("Signed shiftSchedule offset, nonzero, at most 364 days"),
            "template_id": AIToolRegistry.stringSchema("ID from list_templates"),
            "exercise_id": AIToolRegistry.stringSchema("Source library exercise ID"),
            "replacement_exercise_id": AIToolRegistry.stringSchema("Replacement library ID; explicit weight_kg and reps required"),
            "sets": AIToolRegistry.integerSchema("1–20"), "reps": AIToolRegistry.integerSchema("1–100"),
            "weight_kg": AIToolRegistry.numberSchema("Normal working kg in the target's logging convention, never pre-scaled deload load"),
            "rest_seconds": AIToolRegistry.integerSchema("15–900 normal seconds"),
            "target_rpe": AIToolRegistry.numberSchema("Target effort 1–10"),
            "skipped": AIToolRegistry.boolSchema("skipSession: false restores a skipped session; do not use to reduce programmed frequency"),
            "label": AIToolRegistry.stringSchema("New session name for updateSession/addSession/duplicateSession"),
            "notes": AIToolRegistry.stringSchema("Session notes; empty string clears"),
            "schedule": AIToolRegistry.arraySchema(of: placement, description: "setWeekSchedule: COMPLETE desired upcoming schedule. Unlisted editable sessions are removed. [] is a rest week."),
            "weekly_schedule": AIToolRegistry.arraySchema(of: day, description: "changeSchedule: complete repeated weekly pattern; unlisted days are removed"),
            "contents": AIToolRegistry.arraySchema(of: contents, description: "setSessionExercises: complete ordered normal workout. Unlisted occurrences are removed. Preserve IDs to retain prescriptions."),
            "is_deload": AIToolRegistry.boolSchema("Optional deload state for replacement schedule/add/duplicate; omit to preserve retained sessions"),
            "deload_weight_percent": AIToolRegistry.integerSchema("Override Settings for this edit only, 10–100% of normal weight"),
            "deload_rest_percent": AIToolRegistry.integerSchema("Override Settings for this edit only, 25–100% of normal rest"),
            "remaining_only": AIToolRegistry.boolSchema("Preserve past/completed/active sessions in a partially completed week; schedule lists only upcoming sessions"),
            "edit_id": AIToolRegistry.stringSchema("Journal ID for undoEdit or restoreSession; restoring also needs session_id"),
            "correction_reason": AIToolRegistry.stringSchema("Required to explicitly remove an overdue unperformed session; preview shows adherence impact")
        ], required: ["operation"])
    }
    public var parametersSchema: JSONValue {
        guard case .object(var schema) = operationSchema(), case .object(var properties) = schema["properties"] else { return operationSchema() }
        properties["plan_id"] = AIToolRegistry.stringSchema("Active plan UUID from get_active_plan")
        properties["expected_version"] = AIToolRegistry.stringSchema("Version from the fresh get_active_plan response")
        properties["operations"] = AIToolRegistry.arraySchema(of: operationSchema(), description: "batch: 1–50 operations applied in order, in one transaction and one confirmation. No nested batches.")
        schema["properties"] = .object(properties)
        return .object(schema)
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        // Decode the public snake_case tool format into the domain's persisted format.
        // Dates use local calendar days, not UTC midnight, and unknown fields fail visibly.
        let object = try JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))
        guard var input = object as? [String: Any] else { throw AIToolError("Expected a plan edit object.") }
        var planID: UUID?
        if let supplied = input.removeValue(forKey: "plan_id") {
            guard let text = supplied as? String, let id = UUID(uuidString: text) else {
                throw AIToolError("plan_id must be a valid UUID from get_active_plan.")
            }
            planID = id
        }
        var version: String?
        if let supplied = input.removeValue(forKey: "expected_version") {
            guard let text = supplied as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIToolError("expected_version must be the non-empty version from get_active_plan.")
            }
            version = text
        }
        let request = try Self.decodeRequest(input)
        // Old single-operation tool calls remain compatible. New structural operations
        // must bind to the exact plan/version that the assistant inspected.
        let legacy: Set<PlanEditRequest.Operation> = [.convertDeload, .insertDeload, .moveDeload, .removeDeload, .repeatWeek, .extendPlan, .rescheduleSession, .skipSession, .changeTemplate, .changeExercise, .changeTargets]
        if !legacy.contains(request.operation), planID == nil || version == nil { throw AIToolError("Read get_active_plan, then pass its plan_id and expected_version.") }
        let preview = try await viewModel.previewPlanEdit(request, planID: planID, expectedVersion: version)
        return AIToolResult(outputForModel: AIJSON.string(.object([
            "status": .string("confirmation_presented"), "preview_id": .string(preview.id.uuidString),
            "summary": .array(preview.summaryLines.map(JSONValue.string)),
            "session_changes": try AIToolData.json(preview.sessionChanges),
            "resulting_schedule": try AIToolData.json(preview.changeRecord.map { record in
                var result = ProgressionPlan(name: preview.planName, trainingStatus: .intermediate, programType: .linear, primaryGoal: .strength, weeklyFrequency: record.after.weeklyFrequency)
                record.after.install(on: &result)
                return PlanEditingService.weekSummaries(result)
            })
        ])), draft: .action(.init(kind: .editPlan(preview), title: "Update \(preview.planName)?", summaryLines: preview.summaryLines, confirmLabel: "Apply changes")),
            activityLabel: "Previewed plan changes")
    }

    private static func decodeRequest(_ input: [String: Any]) throws -> PlanEditRequest {
        let names = ["session_id": "sessionID", "session_ids": "sessionIDs", "template_id": "templateID", "exercise_id": "exerciseID",
            "replacement_exercise_id": "replacementExerciseID", "new_date": "newDate", "destination_week": "destinationWeek", "end_week": "endWeek",
            "weight_kg": "weightKg", "rest_seconds": "restSeconds", "target_rpe": "targetRPE", "is_deload": "isDeload", "remaining_only": "remainingOnly",
            "deload_weight_percent": "deloadWeightPercentage", "deload_rest_percent": "deloadRestPercentage", "edit_id": "editID",
            "weekly_schedule": "weeklySchedule", "source_weekday": "sourceWeekday", "occurrence_id": "occurrenceID",
            "duration_seconds": "durationSeconds", "distance_meters": "distanceMeters", "correction_reason": "correctionReason"]
        let allowed = Set(names.keys).union(["operation", "scope", "week", "weeks", "sets", "reps", "skipped", "operations", "schedule", "contents", "date", "label", "notes", "days", "weekday"])
        func transform(_ object: [String: Any]) throws -> [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in object {
                guard allowed.contains(key) else { throw AIToolError("Unknown plan edit field: \(key)") }
                let target = names[key] ?? key
                if key == "new_date" || key == "date" {
                    guard let text = value as? String, let date = AIJSON.parseDate(text), AIJSON.dateString(date) == text else { throw AIToolError("Dates must be valid yyyy-MM-dd calendar days.") }
                    result[target] = date.timeIntervalSinceReferenceDate
                } else if let values = value as? [[String: Any]] {
                    result[target] = try values.map(transform)
                } else { result[target] = value }
            }
            if object["operation"] != nil {
                result["weeks"] = result["weeks"] ?? 1
                result["scope"] = result["scope"] ?? (result["sessionID"] == nil ? "week" : "session")
            }
            return result
        }
        let data = try JSONSerialization.data(withJSONObject: transform(input))
        return try JSONDecoder().decode(PlanEditRequest.self, from: data)
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

public struct PlanWeekSummary: Codable, Sendable {
    public var week: Int
    public var start: Date?
    public var scheduledCount: Int
    public var completedCount: Int
    public var skippedCount: Int
    public var restWeek: Bool
    public var sessions: [PlanSessionSummary]
    public init(week: Int, start: Date?, sessions: [PlannedSession]) {
        self.week = week; self.start = start
        scheduledCount = sessions.filter { !$0.isOmitted }.count
        completedCount = sessions.filter(\.isCompleted).count; skippedCount = sessions.filter(\.isSkipped).count
        restWeek = scheduledCount == 0
        self.sessions = sessions.filter { !$0.isOmitted }.map { .init(id: $0.id, date: $0.scheduledDate, name: $0.displayLabel, deload: $0.isDeload) }
    }
}
public struct PlanSessionSummary: Codable, Sendable {
    public var id: UUID
    public var date: Date?
    public var name: String
    public var deload: Bool
}
