import Foundation

public enum AIToolData {
    /// ISO timestamps and native numeric precision across all detailed read tools.
    public static func json<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }
    public static func optional(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }

    /// A planned session without its own copy of the workout. That copy repeats every
    /// exercise in full; plannedExercises already lists each one with its target, and
    /// the time or distance of the exercises not counted in reps is added here.
    public static func session(_ session: PlannedSession?) throws -> JSONValue {
        guard let session else { return .null }
        var compact = session
        compact.exerciseSnapshot = nil
        guard case .object(var fields) = try json(compact) else { return .null }
        fields["owns_exercises"] = .bool(session.exerciseSnapshot != nil)
        let timed = (session.exerciseSnapshot?.exercises ?? []).filter { $0.targetDurationSeconds != nil || $0.targetDistanceMeters != nil }
        if !timed.isEmpty {
            fields["timed_targets"] = .array(timed.map { row in
                .object(["occurrence_id": .string(row.id.uuidString), "n": .string(row.exercise.name),
                    "duration_seconds": row.targetDurationSeconds.map { .number(Double($0)) } ?? .null,
                    "distance_meters": optional(row.targetDistanceMeters)])
            })
        }
        return .object(fields)
    }
}

@MainActor
public final class ProposePlanEditTool: AITool {
    private let viewModel: ProgressionPlanViewModel
    public init(viewModel: ProgressionPlanViewModel) { self.viewModel = viewModel }
    public let name = "propose_plan_edit"
    public let description = "Preview one atomic edit to the active plan. Read get_active_plan first and pass plan_id/version. A plan owns its exercises: every session carries its own exercise list, and a template (template_id, changeTemplate) is only copied in, never linked, so the plan never follows later template changes. setSessionExercises edits that list exercise by exercise: with scope session it changes one session; with scope remaining and session_id it also reaches the later sessions of the same workout (those with the same exercises in the same order), which take the added, removed, reordered and swapped exercises and keep their own targets on the exercises that stay. Use setWeekSchedule for an exact replacement schedule (including [] for rest); removeSessions removes planned work, whereas skipSession records missed work. Use batch for related changes in ONE Apply card. Reusable templates and completed/active workouts are protected. setProgression gives one exercise (exercise_id) a complete progression rule and re-lays its remaining sessions; its start fields only matter before the rule has trained sessions. To set the next target instead, change that session's targets: the ladder continues from a manual target. renamePlan sets the plan's name from label. Everything the app's plan screens can change is an operation here."
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
            "scope": AIToolRegistry.enumSchema(PlanEditRequest.Scope.self, description: "session, week, or remaining from week. setSessionExercises with session_id and remaining: this session and the later sessions of the same workout"),
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
            "label": AIToolRegistry.stringSchema("New session name for updateSession/addSession/duplicateSession; the plan's new name for renamePlan"),
            "notes": AIToolRegistry.stringSchema("Session notes, or plan notes for renamePlan; empty string clears"),
            "schedule": AIToolRegistry.arraySchema(of: placement, description: "setWeekSchedule: COMPLETE desired upcoming schedule. Unlisted editable sessions are removed. [] is a rest week."),
            "weekly_schedule": AIToolRegistry.arraySchema(of: day, description: "changeSchedule: complete repeated weekly pattern; unlisted days are removed"),
            "contents": AIToolRegistry.arraySchema(of: contents, description: "setSessionExercises: complete ordered normal workout of session_id. Unlisted occurrences are removed. Preserve IDs to retain prescriptions. An exercise the plan already progresses should be added at its next_target. A band exercise takes weight_kg 0."),
            "is_deload": AIToolRegistry.boolSchema("Optional deload state for replacement schedule/add/duplicate; omit to preserve retained sessions"),
            "deload_weight_percent": AIToolRegistry.integerSchema("Override Settings for this edit only, 10–100% of normal weight"),
            "deload_rest_percent": AIToolRegistry.integerSchema("Override Settings for this edit only, 25–100% of normal rest"),
            "remaining_only": AIToolRegistry.boolSchema("Preserve past/completed/active sessions in a partially completed week; schedule lists only upcoming sessions"),
            "edit_id": AIToolRegistry.stringSchema("Journal ID for undoEdit or restoreSession; restoring also needs session_id"),
            "progression": ToolSchemas.progressionRule,
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
            "session_changes": .array(try (preview.sessionChanges ?? []).map { change in
                .object(["id": .string(change.id.uuidString), "kind": .string(change.kind),
                    "before": try AIToolData.session(change.before), "after": try AIToolData.session(change.after)])
            }),
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
        let allowed = Set(names.keys).union(["operation", "scope", "week", "weeks", "sets", "reps", "skipped", "operations", "schedule", "contents", "date", "label", "notes", "days", "weekday", "progression"])
        func transform(_ object: [String: Any]) throws -> [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in object {
                guard allowed.contains(key) else { throw AIToolError("Unknown plan edit field: \(key)") }
                let target = names[key] ?? key
                if key == "progression" {
                    // The rule arrives in the tool's snake_case and is validated before it reaches the engine.
                    guard let fields = value as? [String: Any] else { throw AIToolError("progression must be a rule object.") }
                    let argument = try JSONDecoder().decode(ProgressionRuleArgument.self, from: JSONSerialization.data(withJSONObject: fields))
                    result[target] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(argument.rule()))
                } else if key == "new_date" || key == "date" {
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

// MARK: - preview_progression

/// Lets the assistant see what a progression rule asks for before proposing it.
@MainActor
public final class PreviewProgressionTool: AITool {
    private let progressionPlanRepository: any ProgressionPlanRepository

    public init(progressionPlanRepository: any ProgressionPlanRepository) {
        self.progressionPlanRepository = progressionPlanRepository
    }

    public let name = "preview_progression"
    public let description = "Simulate a progression rule without changing anything: the sentence the user will see, and the targets of the next sessions if every one is hit. With exercise_id of a rule-driven exercise in the active plan, the simulation continues from where that exercise stands now instead of the rule's start. Use it before propose_training_plan or a setProgression edit to check a rule does what the user asked for."

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "rule": ToolSchemas.progressionRule,
            "sessions": AIToolRegistry.integerSchema("How many sessions to simulate, 1–60; default 12"),
            "exercise_id": AIToolRegistry.stringSchema("Optional library exercise ID from get_active_plan: continue from that exercise's current target")
        ], required: ["rule"])
    }

    private struct Arguments: Decodable {
        var rule: ProgressionRuleArgument
        var sessions: Int?
        var exercise_id: UUID?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let rule = try args.rule.rule()
        let count = args.sessions ?? 12
        guard (1...60).contains(count) else { throw AIToolError("sessions must be 1–60") }
        var state = ProgressionRuleEngine.initialState(rule)
        var from = "the rule's start"
        if let id = args.exercise_id {
            guard let plan = try await progressionPlanRepository.fetchActive(),
                  let exercise = plan.exercises.first(where: { $0.exerciseId == id }) else {
                throw AIToolError("That exercise is not in the active plan.")
            }
            if let current = ProgressionRuleEngine.currentState(of: exercise, in: plan)?.state.target {
                state = .init(target: .init(weightKg: current.weightKg, reps: min(max(current.reps, rule.minReps), rule.maxReps)))
                from = "\(exercise.exerciseName)'s current target"
            }
        }
        let targets = ProgressionRuleEngine.projection(from: state, rule: rule, count: count)
        return AIToolResult(outputForModel: AIJSON.string(.object([
            "summary": .string(rule.summary(unit: .kg)),
            "starts_from": .string(from),
            "targets_if_every_session_is_hit": .array(targets.enumerated().map { index, target in
                .object(["session": .number(Double(index + 1)), "weight_kg": .number(target.weightKg), "reps": .number(Double(target.reps)), "sets": .number(Double(rule.sets))])
            }),
            "note": .string("A missed session repeats its target, so real progress is at most this fast. Nothing was changed.")
        ])), activityLabel: "Simulated a progression rule")
    }
}
