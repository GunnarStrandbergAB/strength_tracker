import Foundation

// Session-level tools: start (empty / template / plan session), finish, cancel.
// start_workout while a workout is active and cancel_workout are destructive and
// go through a Confirm card (`AIDraft.action`) instead of writing directly.

// MARK: - start_workout

@MainActor
public final class StartWorkoutTool: AITool {
    private let session: any WorkoutSessionControlling
    private let preferences: UserPreferencesService?

    public init(session: any WorkoutSessionControlling, userPreferencesService: UserPreferencesService?) {
        self.session = session
        self.preferences = userPreferencesService
    }

    public let name = "start_workout"
    public let description = """
    Start a workout: empty (no arguments), from a template (template_name, custom or library), or \
    from the active training plan (plan_session: "next" or a yyyy-MM-dd scheduled date). If a \
    workout is already active the user sees a Confirm card before it is replaced.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "template_name": AIToolRegistry.stringSchema("Exact template name (see list_templates); not with plan_session"),
            "plan_session": AIToolRegistry.stringSchema("\"next\" for the next open plan session, or its scheduled date yyyy-MM-dd; not with template_name"),
            "name": AIToolRegistry.stringSchema("Workout name override (default: template/session name, or \"Quick Workout\")"),
            "is_deload": AIToolRegistry.boolSchema("Mark as deload (plan sessions inherit their week's deload flag)")
        ])
    }

    private struct Arguments: Decodable {
        var template_name: String?
        var plan_session: String?
        var name: String?
        var is_deload: Bool?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        if args.template_name != nil, args.plan_session != nil {
            throw AIToolError("Pass either template_name or plan_session, not both.")
        }
        if session.watchWorkoutInProgress {
            throw AIToolError("A workout is in progress on Apple Watch; finish it there first.")
        }

        // Resolve the source before touching any state.
        var template: WorkoutTemplate?
        var plannedSessionID: UUID?
        var plannedPlanID: UUID?
        var isDeload = args.is_deload ?? false
        var sourceLine: String?

        if let templateName = args.template_name {
            let all = try await session.allTemplates()
            template = try TemplateNameResolver.resolve(name: templateName, in: all, includeLibrary: true)
            sourceLine = "From template '\(template!.name)'"
        } else if let planSession = args.plan_session {
            guard let plan = await session.activePlan() else {
                throw AIToolError("No active training plan. Use start_workout with a template_name or no arguments instead.")
            }
            let picked = try Self.pickSession(planSession, in: plan)
            guard let built = await session.sessionTemplate(for: picked.session) else {
                throw AIToolError("Could not build the session '\(picked.session.sessionLabel)' from the plan.")
            }
            template = built
            plannedSessionID = picked.session.id
            plannedPlanID = plan.id
            isDeload = args.is_deload ?? (picked.session.isDeload || picked.week.isDeload)
            sourceLine = "Plan \(plan.name) · week \(picked.week.absoluteWeekNumber) · \(picked.session.sessionLabel)"
        }

        let workoutName = args.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? template?.name
            ?? "Quick Workout"

        if let active = session.activeWorkout {
            let done = active.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
            let minutes = max(0, Int(Date().timeIntervalSince(active.startedAt) / 60))
            let title = "Replace the active workout '\(active.name)'?"
            let lines = [
                "'\(active.name)' has \(done) completed set\(done == 1 ? "" : "s") over \(minutes) min and will be deleted",
                "Start '\(workoutName)'" + (sourceLine.map { " · \($0)" } ?? "")
            ]
            let action = AIPendingAction(
                kind: .startWorkout(
                    name: workoutName,
                    templateID: template?.id,
                    plannedSessionID: plannedSessionID,
                    plannedPlanID: plannedPlanID,
                    isDeload: isDeload,
                    replacingWorkoutID: active.id
                ),
                title: title, summaryLines: lines, confirmLabel: "Discard & Start"
            )
            return AIToolResult(
                outputForModel: confirmationReceipt(action: name, title: title, summary: lines),
                draft: .action(action),
                activityLabel: "Asked to confirm replacing the active workout"
            )
        }

        let workout = try await session.start(.init(
            name: workoutName,
            template: template,
            isDeload: isDeload,
            plannedSessionId: plannedSessionID,
            plannedPlanId: plannedPlanID
        ))

        var lines = ["\(workout.exercises.count) exercise\(workout.exercises.count == 1 ? "" : "s")"]
        if let sourceLine { lines[0] += " · \(sourceLine)" }
        if workout.isDeload { lines.append("Deload") }
        let receipt = AIReceipt(
            scope: .session,
            workoutID: workout.id,
            headline: "Started \(workout.name)",
            sections: [.init(symbol: "play.circle.fill", title: workout.name, lines: lines)]
        )
        return AIToolResult(
            outputForModel: AIJSON.string(.object([
                "status": .string("started"),
                "workout": WorkoutJSON.workout(workout, scope: .activeWorkout)
            ])),
            receipt: receipt,
            activityLabel: "Started \(workout.name)"
        )
    }

    static func pickSession(_ selector: String, in plan: ProgressionPlan) throws -> (session: PlannedSession, week: TrainingWeek) {
        let open = plan.blocks.flatMap(\.weeks).flatMap { week in
            week.sessions.filter { !$0.isClosed }.map { (session: $0, week: week) }
        }
        guard !open.isEmpty else {
            throw AIToolError("No open sessions left in plan '\(plan.name)'.")
        }
        if selector.lowercased() == "next" {
            guard let next = open.min(by: { ($0.session.scheduledDate ?? .distantFuture) < ($1.session.scheduledDate ?? .distantFuture) }) else {
                throw AIToolError("No open sessions left in plan '\(plan.name)'.")
            }
            return next
        }
        guard let day = AIJSON.parseDate(selector) else {
            throw AIToolError("plan_session must be \"next\" or a date yyyy-MM-dd.")
        }
        let calendar = Calendar.current
        if let match = open.first(where: { $0.session.scheduledDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }) {
            return match
        }
        let nearby = open
            .compactMap { entry -> String? in
                guard let date = entry.session.scheduledDate else { return nil }
                return "\(AIJSON.dateString(date)) '\(entry.session.sessionLabel)'"
            }
            .prefix(5)
            .joined(separator: ", ")
        throw AIToolError("No open plan session on \(selector). Open sessions: \(nearby).")
    }
}

// MARK: - finish_workout

@MainActor
public final class FinishWorkoutTool: AITool {
    private let session: any WorkoutSessionControlling
    private let preferences: UserPreferencesService?

    public init(session: any WorkoutSessionControlling, userPreferencesService: UserPreferencesService?) {
        self.session = session
        self.preferences = userPreferencesService
    }

    public let name = "finish_workout"
    public let description = """
    Finish the active workout (same as the Finish button): saves it to history, completes a linked \
    plan session, and triggers HealthKit/analytics. Only call when the user clearly asks.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "notes": AIToolRegistry.stringSchema("Optional note appended to the workout before finishing")
        ])
    }

    private struct Arguments: Decodable {
        var notes: String?
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        guard session.activeWorkout != nil else { throw WorkoutEditError.noActiveWorkout }
        let completed = try await session.finish(notes: args.notes)

        let unit = preferences?.weightUnit ?? .kg
        let bodyWeight = preferences?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
        let setsDone = completed.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
        let incomplete = completed.exercises.reduce(0) { $0 + $1.sets.filter { !$0.isCompleted }.count }
        let volumeKg = completed.totalVolume(bodyWeightKg: bodyWeight)
        let minutes = Int((completed.duration ?? 0) / 60)

        var lines = ["\(minutes) min · \(setsDone) set\(setsDone == 1 ? "" : "s") · \(unit.format(volumeKg, decimals: 0))"]
        if incomplete > 0 { lines.append("\(incomplete) planned set\(incomplete == 1 ? "" : "s") left incomplete") }
        if completed.plannedSessionId != nil { lines.append("Plan session completed") }

        var output: [String: JSONValue] = [
            "status": .string("completed"),
            "name": .string(completed.name),
            "duration_min": .number(Double(minutes)),
            "sets_completed": .number(Double(setsDone)),
            "volume_kg": .number(AIJSON.round1(volumeKg)),
            "units": .string("kg")
        ]
        if incomplete > 0 { output["incomplete_sets"] = .number(Double(incomplete)) }
        if completed.plannedSessionId != nil { output["plan_session_completed"] = .bool(true) }

        return AIToolResult(
            outputForModel: AIJSON.string(.object(output)),
            receipt: AIReceipt(
                scope: .session,
                workoutID: completed.id,
                headline: "Finished \(completed.name)",
                sections: [.init(symbol: "flag.checkered", title: completed.name, lines: lines)]
            ),
            activityLabel: "Finished \(completed.name)"
        )
    }
}

// MARK: - cancel_workout

@MainActor
public final class CancelWorkoutTool: AITool {
    private let session: any WorkoutSessionControlling

    public init(session: any WorkoutSessionControlling) {
        self.session = session
    }

    public let name = "cancel_workout"
    public let description = """
    Discard the active workout and everything logged in it. Always shows the user a Confirm card; \
    only call when the user clearly asks to cancel or discard the workout.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [:])
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        guard let active = session.activeWorkout else { throw WorkoutEditError.noActiveWorkout }
        let done = active.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
        let minutes = max(0, Int(Date().timeIntervalSince(active.startedAt) / 60))
        let title = "Cancel '\(active.name)'?"
        let lines = ["\(done) logged set\(done == 1 ? "" : "s") over \(minutes) min will be deleted"]
        let action = AIPendingAction(
            kind: .cancelWorkout(workoutID: active.id),
            title: title, summaryLines: lines, confirmLabel: "Cancel Workout"
        )
        return AIToolResult(
            outputForModel: confirmationReceipt(action: name, title: title, summary: lines),
            draft: .action(action),
            activityLabel: "Asked to confirm cancelling the workout"
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
