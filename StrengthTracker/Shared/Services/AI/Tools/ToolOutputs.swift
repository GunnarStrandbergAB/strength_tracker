import Foundation

// Shared output/argument helpers for the workout write tools.

// MARK: - Model-facing receipts

func proposalReceipt(kind: String, name: String) -> String {
    AIJSON.string(.object([
        "status": .string("proposal_presented"),
        "kind": .string(kind),
        "name": .string(name),
        "note": .string("The user sees a card with Save/Discard. Do not claim it was saved.")
    ]))
}

func confirmationReceipt(action: String, title: String, summary: [String]) -> String {
    AIJSON.string(.object([
        "status": .string("confirmation_presented"),
        "action": .string(action),
        "title": .string(title),
        "summary": .array(summary.map { .string($0) }),
        "note": .string("The user sees a Confirm/Cancel card. Stop and wait; do not claim it was done. The next user turn will say whether it was confirmed.")
    ]))
}

// MARK: - Seams the tools depend on (stubbed in tests)

@MainActor
public protocol WorkoutTargetResolving: AnyObject {
    func resolve(date: String?, workoutName: String?) async throws -> any WorkoutEditor
}

extension WorkoutEditorResolver: WorkoutTargetResolving {}

/// Session-level operations for start_workout / finish_workout / cancel_workout.
@MainActor
public protocol WorkoutSessionControlling: AnyObject {
    var activeWorkout: Workout? { get }
    var watchWorkoutInProgress: Bool { get }
    func start(_ request: WorkoutSessionCoordinator.StartRequest) async throws -> Workout
    /// Returns the completed workout.
    func finish(notes: String?) async throws -> Workout
    func allTemplates() async throws -> [WorkoutTemplate]
    func activePlan() async -> ProgressionPlan?
    func sessionTemplate(for session: PlannedSession) async -> WorkoutTemplate?
}

/// Production implementation over the coordinator and plan/template sources.
@MainActor
public final class AppWorkoutSessionController: WorkoutSessionControlling {
    private let coordinator: WorkoutSessionCoordinator
    private let templateRepository: any TemplateRepository
    private let progressionPlanViewModel: ProgressionPlanViewModel

    public init(
        coordinator: WorkoutSessionCoordinator,
        templateRepository: any TemplateRepository,
        progressionPlanViewModel: ProgressionPlanViewModel
    ) {
        self.coordinator = coordinator
        self.templateRepository = templateRepository
        self.progressionPlanViewModel = progressionPlanViewModel
    }

    public var activeWorkout: Workout? {
        coordinator.workoutViewModel.isActive ? coordinator.workoutViewModel.currentWorkout : nil
    }

    public var watchWorkoutInProgress: Bool {
        coordinator.workoutViewModel.watchActiveWorkout != nil
    }

    public func start(_ request: WorkoutSessionCoordinator.StartRequest) async throws -> Workout {
        try await coordinator.start(request)
        guard let workout = coordinator.workoutViewModel.currentWorkout else {
            throw AIToolError("The workout did not start.")
        }
        return workout
    }

    public func finish(notes: String?) async throws -> Workout {
        let vm = coordinator.workoutViewModel
        guard vm.isActive, let current = vm.currentWorkout else {
            throw WorkoutEditError.noActiveWorkout
        }
        if let notes, !notes.isEmpty {
            let merged = [current.notes, notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            await vm.updateNotes(merged)
        }
        try await coordinator.finish()
        guard let completed = vm.currentWorkout else {
            throw AIToolError("The workout did not finish.")
        }
        return completed
    }

    public func allTemplates() async throws -> [WorkoutTemplate] {
        try await templateRepository.fetchAll()
    }

    public func activePlan() async -> ProgressionPlan? {
        if progressionPlanViewModel.activePlan == nil {
            await progressionPlanViewModel.loadActivePlan()
        }
        return progressionPlanViewModel.activePlan
    }

    public func sessionTemplate(for session: PlannedSession) async -> WorkoutTemplate? {
        await progressionPlanViewModel.prepareSessionTemplate(for: session)
    }
}

// MARK: - Argument shapes

/// `set_type` values the model may pass (`failure` is expressed via `to_failure`).
enum AISetType: String, CaseIterable {
    case normal, warmup, dropset, restPause

    var setType: SetType {
        switch self {
        case .normal: return .normal
        case .warmup: return .warmup
        case .dropset: return .dropset
        case .restPause: return .restPause
        }
    }
}

struct DropSegmentArgument: Decodable {
    var weight: WeightArgument?
    var reps: Int?
    var rpe: Double?
    var rir: Double?
    var to_failure: Bool?

    func segment() throws -> DropSegment {
        DropSegment(
            weightKg: try weight?.kilograms(),
            reps: reps,
            intensity: try ToolArguments.intensity(rpe: rpe, rir: rir),
            isFailure: to_failure ?? false
        )
    }
}

enum ToolArguments {
    static func intensity(rpe: Double?, rir: Double?) throws -> IntensityValue? {
        switch (rpe, rir) {
        case (nil, nil):
            return nil
        case (let rpe?, nil):
            guard (1...10).contains(rpe) else { throw AIToolError("rpe must be between 1 and 10.") }
            return IntensityValue(value: rpe, metric: .rpe)
        case (nil, let rir?):
            guard (0...9).contains(rir) else { throw AIToolError("rir must be between 0 and 9.") }
            return IntensityValue(value: rir, metric: .rir)
        default:
            throw AIToolError("Pass either rpe or rir, not both.")
        }
    }

    static func setType(_ raw: String?, allowDropset: Bool) throws -> SetType? {
        guard let raw else { return nil }
        if raw.lowercased() == "failure" {
            throw AIToolError("set_type 'failure' is not supported; pass to_failure: true instead.")
        }
        let parsed = try parseEnum(AISetType.self, raw, field: "set_type")
        if parsed == .dropset, !allowDropset {
            throw AIToolError("set_type dropset is only valid on log_set with drop_segments.")
        }
        return parsed.setType
    }
}

// MARK: - Schema fragments

@MainActor
enum ToolSchemas {
    static var target: [String: JSONValue] {
        [
            "workout_date": AIToolRegistry.stringSchema(
                "Date (yyyy-MM-dd) the completed workout was started. Omit to target the active workout."
            ),
            "workout_name": AIToolRegistry.stringSchema(
                "Only with workout_date: picks among several workouts started that day."
            )
        ]
    }

    static var exerciseInWorkout: [String: JSONValue] {
        [
            "exercise_name": AIToolRegistry.stringSchema(
                "Exercise already in the workout (exact name from the app-state note or get_workout)."
            ),
            "occurrence": AIToolRegistry.integerSchema(
                "1-based, only when the same exercise appears more than once in the workout (default 1)."
            )
        ]
    }

    static var weight: JSONValue {
        AIToolRegistry.objectSchema(
            properties: [
                "value": AIToolRegistry.numberSchema("Weight value"),
                "unit": AIToolRegistry.stringSchema("kg or lbs")
            ],
            required: ["value", "unit"]
        )
    }

    static var dropSegment: JSONValue {
        AIToolRegistry.objectSchema(
            properties: [
                "weight": weight,
                "reps": AIToolRegistry.integerSchema("Reps in this segment"),
                "rpe": AIToolRegistry.numberSchema("RPE 1-10 (not with rir)"),
                "rir": AIToolRegistry.numberSchema("RIR 0-9 (not with rpe)"),
                "to_failure": AIToolRegistry.boolSchema("Segment taken to failure")
            ]
        )
    }
}

// MARK: - JSON output shapes

enum WorkoutJSON {
    static func workout(_ workout: Workout, scope: AIReceipt.Scope) -> JSONValue {
        var object: [String: JSONValue] = [
            "source": .string(scope == .activeWorkout ? "active" : "history"),
            "name": .string(workout.name),
            "date": .string(AIJSON.dateString(workout.startedAt)),
            "started": .string(workout.startedAt.formatted(date: .omitted, time: .shortened)),
            "exercises": .array(exercisesJSON(workout)),
            "units": .string("kg")
        ]
        if let completed = workout.completedAt {
            object["completed"] = .string(completed.formatted(date: .omitted, time: .shortened))
        }
        if workout.isDeload { object["is_deload"] = .bool(true) }
        if let notes = workout.notes, !notes.isEmpty { object["notes"] = .string(notes) }
        if workout.plannedPlanId != nil { object["plan_session"] = .bool(true) }
        return .object(object)
    }

    static func exercisesJSON(_ workout: Workout) -> [JSONValue] {
        let ordered = workout.exercises.sorted { $0.order < $1.order }
        let counts = Dictionary(ordered.map { ($0.exercise.name, 1) }, uniquingKeysWith: +)
        return ordered.map { exercise in
            let occurrence = (counts[exercise.exercise.name] ?? 1) > 1
                ? WorkoutExerciseResolver.occurrence(of: exercise, in: workout) : nil
            return self.exercise(exercise, occurrence: occurrence)
        }
    }

    static func exercise(_ exercise: WorkoutExercise, occurrence: Int? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(exercise.exercise.name),
            "sets": .array(exercise.sets.enumerated().map { set($1, number: $0 + 1) }),
            "done": .string("\(exercise.sets.filter(\.isCompleted).count)/\(exercise.sets.count)")
        ]
        if let occurrence { object["occurrence"] = .number(Double(occurrence)) }
        if let notes = exercise.notes, !notes.isEmpty { object["notes"] = .string(notes) }
        if let rest = exercise.restTimerSeconds { object["rest_s"] = .number(Double(rest)) }
        if let group = exercise.supersetGroup { object["superset"] = .number(Double(group)) }
        return .object(object)
    }

    static func set(_ set: ExerciseSet, number: Int) -> JSONValue {
        var object: [String: JSONValue] = ["n": .number(Double(number))]
        if set.setType != .normal { object["type"] = .string(set.setType.rawValue) }
        if let weight = set.weight { object["weight_kg"] = .number(AIJSON.round1(weight)) }
        if let reps = set.reps { object["reps"] = .number(Double(reps)) }
        if let seconds = set.durationSeconds { object["duration_s"] = .number(Double(seconds)) }
        if let meters = set.distanceMeters { object["distance_m"] = .number(AIJSON.round1(meters)) }
        if let rpe = set.rpe { object["rpe"] = .number(AIJSON.round1(rpe)) }
        if let rir = set.rir { object["rir"] = .number(AIJSON.round1(rir)) }
        if set.isCompleted { object["done"] = .bool(true) }
        if set.isFailure || set.setType == .failure { object["failure"] = .bool(true) }
        if set.isPersonalRecord { object["pr"] = .bool(true) }
        if !set.dropSets.isEmpty {
            object["drops"] = .array(set.dropSets.map { entry in
                var drop: [String: JSONValue] = [:]
                if let weight = entry.weight { drop["weight_kg"] = .number(AIJSON.round1(weight)) }
                if let reps = entry.reps { drop["reps"] = .number(Double(reps)) }
                if let rpe = entry.rpe { drop["rpe"] = .number(AIJSON.round1(rpe)) }
                if let rir = entry.rir { drop["rir"] = .number(AIJSON.round1(rir)) }
                if entry.isFailure { drop["failure"] = .bool(true) }
                return .object(drop)
            })
        }
        return .object(object)
    }
}

// MARK: - Receipt text (user's display unit and metric)

@MainActor
struct ReceiptText {
    let unit: WeightUnit
    let metric: IntensityMetric

    init(preferences: UserPreferencesService?) {
        unit = preferences?.weightUnit ?? .kg
        metric = preferences?.intensityMetric ?? .rpe
    }

    func headline(for workout: Workout, scope: AIReceipt.Scope) -> String {
        switch scope {
        case .activeWorkout:
            return "Active workout · \(workout.name)"
        case .historyWorkout:
            return "\(workout.name) · \(workout.startedAt.formatted(.dateTime.month(.abbreviated).day()))"
        case .session:
            return workout.name
        }
    }

    func receipt(for workout: Workout, scope: AIReceipt.Scope, symbol: String, title: String, lines: [String]) -> AIReceipt {
        AIReceipt(
            scope: scope,
            workoutID: workout.id,
            headline: headline(for: workout, scope: scope),
            sections: [.init(symbol: symbol, title: title, lines: lines)]
        )
    }

    func load(weightKg: Double?, reps: Int?) -> String? {
        switch (weightKg, reps) {
        case (let w?, let r?): return "\(unit.format(w)) × \(r)"
        case (let w?, nil): return unit.format(w)
        case (nil, let r?): return "\(r) reps"
        default: return nil
        }
    }

    /// e.g. ["85 kg × 8", "RPE 9 · to failure"] or ["85 kg × 8 → 70 kg × 6", …]
    func lines(for set: ExerciseSet) -> [String] {
        var lines: [String] = []
        if !set.dropSets.isEmpty {
            let segments = set.dropSets.compactMap { load(weightKg: $0.weight, reps: $0.reps) }
            if !segments.isEmpty { lines.append(segments.joined(separator: " → ")) }
        } else if let text = load(weightKg: set.weight, reps: set.reps) {
            lines.append(text)
        } else if let seconds = set.durationSeconds {
            lines.append("\(seconds) s")
        } else if let meters = set.distanceMeters {
            lines.append("\(AIJSON.compact(meters, maxFractionDigits: 0)) m")
        }
        var details: [String] = []
        if let value = set.intensityValue(for: metric) {
            details.append("\(metric.displayName) \(AIJSON.compact(value))")
        }
        if set.isFailure || set.setType == .failure { details.append("to failure") }
        if set.setType == .warmup { details.append("warm-up") }
        if set.setType == .restPause { details.append("rest-pause") }
        if !set.isCompleted { details.append("planned") }
        if !details.isEmpty { lines.append(details.joined(separator: " · ")) }
        return lines
    }

    /// Short inline form for summaries: "85 kg × 8, RPE 9".
    func inline(_ set: ExerciseSet) -> String {
        lines(for: set).joined(separator: ", ")
    }
}
