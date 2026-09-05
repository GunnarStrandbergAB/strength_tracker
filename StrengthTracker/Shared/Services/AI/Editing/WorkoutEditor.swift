import Foundation

// MARK: - Value types

public struct IntensityValue: Sendable, Equatable {
    public var value: Double
    public var metric: IntensityMetric
    public init(value: Double, metric: IntensityMetric) {
        self.value = value
        self.metric = metric
    }
}

public struct DropSegment: Sendable, Equatable {
    public var weightKg: Double?
    public var reps: Int?
    public var intensity: IntensityValue?
    public var isFailure: Bool
    public init(weightKg: Double? = nil, reps: Int? = nil, intensity: IntensityValue? = nil, isFailure: Bool = false) {
        self.weightKg = weightKg
        self.reps = reps
        self.intensity = intensity
        self.isFailure = isFailure
    }

    func makeEntry() -> DropSetEntry {
        var entry = DropSetEntry(weight: weightKg, reps: reps)
        if let intensity { entry.applyIntensity(intensity.value, metric: intensity.metric) }
        if isFailure { entry.setFailureFlag(true) }
        return entry
    }
}

/// Fields to change on a set; nil = leave untouched.
public struct SetChanges: Sendable, Equatable {
    public var weightKg: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var intensity: IntensityValue?
    public var setType: SetType?
    public var isFailure: Bool?
    public var isCompleted: Bool?
    /// Replaces the whole segment group; `[]` collapses a drop set to a plain set.
    public var dropSegments: [DropSegment]?

    public init(
        weightKg: Double? = nil, reps: Int? = nil,
        durationSeconds: Int? = nil, distanceMeters: Double? = nil,
        intensity: IntensityValue? = nil, setType: SetType? = nil,
        isFailure: Bool? = nil, isCompleted: Bool? = nil,
        dropSegments: [DropSegment]? = nil
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.intensity = intensity
        self.setType = setType
        self.isFailure = isFailure
        self.isCompleted = isCompleted
        self.dropSegments = dropSegments
    }

    /// True when any parent-row field is set (these are rejected on a drop set).
    var touchesParentFields: Bool {
        weightKg != nil || reps != nil || setType != nil
    }
}

/// A planned set to create alongside a new exercise or via add_sets.
public struct SetPrefill: Sendable, Equatable {
    public var weightKg: Double?
    public var reps: Int?
    public var setType: SetType
    public init(weightKg: Double? = nil, reps: Int? = nil, setType: SetType = .normal) {
        self.weightKg = weightKg
        self.reps = reps
        self.setType = setType
    }

    public func makeSet(order: Int) -> ExerciseSet {
        ExerciseSet(
            id: UUID(), order: order, setType: setType,
            weight: weightKg, reps: reps, durationSeconds: nil, distanceMeters: nil,
            rpe: nil, isCompleted: false, isPersonalRecord: false, completedAt: nil
        )
    }
}

// MARK: - Errors

public enum WorkoutEditError: Error, LocalizedError, Equatable {
    case noActiveWorkout
    case workoutNotFound(String)
    case ambiguousWorkout(candidates: [String])
    case exerciseNotFound(name: String, available: [String])
    case ambiguousExercise(name: String, matches: [String])
    case occurrenceOutOfRange(name: String, count: Int)
    case setNotFound(number: Int, count: Int)
    case invalidArgument(String)
    case saveFailed(String)
    case watchWorkoutInProgress

    public var errorDescription: String? {
        switch self {
        case .noActiveWorkout:
            return "No active workout. Pass workout_date to edit a completed workout, or use start_workout."
        case .workoutNotFound(let detail):
            return detail
        case .ambiguousWorkout(let candidates):
            return "Several workouts match: \(candidates.joined(separator: "; ")). Pass workout_name to pick one."
        case .exerciseNotFound(let name, let available):
            if available.isEmpty {
                return "'\(name)' is not in this workout, which has no exercises yet. Use add_exercise to add it."
            }
            return "'\(name)' is not in this workout. Exercises: \(available.joined(separator: ", ")). Use add_exercise to add it."
        case .ambiguousExercise(let name, let matches):
            return "'\(name)' matches several exercises in this workout: \(matches.joined(separator: ", ")). Use the exact name."
        case .occurrenceOutOfRange(let name, let count):
            return "occurrence out of range: \(name) appears \(count) time(s) in this workout."
        case .setNotFound(let number, let count):
            return "set_number \(number) out of range: the exercise has \(count) set(s) (use \(count + 1) to append)."
        case .invalidArgument(let message):
            return message
        case .saveFailed(let message):
            return "Save failed: \(message)"
        case .watchWorkoutInProgress:
            return "A workout is in progress on Apple Watch; it can only be edited there."
        }
    }
}

// MARK: - Guards

/// Decides whether a removal is destructive enough to need a Confirm card.
public enum WorkoutEditGuards {
    public static func exerciseHasCompletedSets(_ exercise: WorkoutExercise) -> Bool {
        exercise.sets.contains(where: \.isCompleted)
    }

    public static func setHasData(_ set: ExerciseSet) -> Bool {
        set.isCompleted || set.weight != nil || set.reps != nil
            || set.durationSeconds != nil || set.distanceMeters != nil
            || set.rpe != nil || set.rir != nil || !set.dropSets.isEmpty
    }
}

// MARK: - Resolver

/// Finds an exercise inside a workout by (fuzzy) name and occurrence.
public enum WorkoutExerciseResolver {
    public static func resolve(name: String, occurrence: Int, in workout: Workout) throws -> WorkoutExercise {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw WorkoutEditError.invalidArgument("exercise_name must not be empty.")
        }
        let exercises = workout.exercises.sorted { $0.order < $1.order }
        let available = exercises.map(\.exercise.name)

        // 1. Exact (case-insensitive) name.
        var matchedName: String?
        if let exact = exercises.first(where: { $0.exercise.name.caseInsensitiveCompare(query) == .orderedSame }) {
            matchedName = exact.exercise.name
        } else {
            // 2. Unique contains match in either direction, over distinct names.
            let lowered = query.lowercased()
            let distinct = Array(NSOrderedSet(array: available)) as? [String] ?? available
            let contains = distinct.filter {
                let n = $0.lowercased()
                return n.contains(lowered) || lowered.contains(n)
            }
            if contains.count == 1 {
                matchedName = contains[0]
            } else if contains.count > 1 {
                throw WorkoutEditError.ambiguousExercise(name: name, matches: contains)
            } else {
                throw WorkoutEditError.exerciseNotFound(name: name, available: available)
            }
        }

        let sameNamed = exercises.filter { $0.exercise.name == matchedName }
        guard occurrence >= 1, occurrence <= sameNamed.count else {
            throw WorkoutEditError.occurrenceOutOfRange(name: matchedName ?? name, count: sameNamed.count)
        }
        return sameNamed[occurrence - 1]
    }

    /// 1-based position among same-named exercises; 1 when the name is unique.
    public static func occurrence(of exercise: WorkoutExercise, in workout: Workout) -> Int {
        let sameNamed = workout.exercises
            .sorted { $0.order < $1.order }
            .filter { $0.exercise.name == exercise.exercise.name }
        return (sameNamed.firstIndex { $0.id == exercise.id } ?? 0) + 1
    }
}

// MARK: - Editor protocol

/// Uniform mutation surface over the active workout (WorkoutViewModel + the
/// session coordinator) and completed workouts (HistoryViewModel). Every write
/// tool resolves an editor, mutates, then calls `commit()` once.
@MainActor
public protocol WorkoutEditor: AnyObject {
    var scope: AIReceipt.Scope { get }
    /// Fresh state after every operation.
    func snapshot() throws -> Workout

    @discardableResult
    func addExercise(_ exercise: Exercise, sets: [SetPrefill], restSeconds: Int?, notes: String?) async throws -> WorkoutExercise
    func removeExercise(id: UUID) async throws
    func replaceExercise(id: UUID, with exercise: Exercise) async throws
    @discardableResult
    func addSets(exerciseId: UUID, prefills: [SetPrefill]) async throws -> [ExerciseSet]
    func removeSet(exerciseId: UUID, setId: UUID) async throws
    @discardableResult
    func updateSet(exerciseId: UUID, setId: UUID, changes: SetChanges) async throws -> ExerciseSet
    func setWorkoutNotes(_ notes: String?) async throws
    func setExerciseNotes(exerciseId: UUID, notes: String?) async throws
    func setDeload(_ isDeload: Bool) async throws
    /// History: endEditing() (re-vectorize + PR recalculation). Active: widget refresh.
    func commit() async
}

public extension WorkoutEditor {
    func findExercise(named name: String, occurrence: Int = 1) throws -> WorkoutExercise {
        try WorkoutExerciseResolver.resolve(name: name, occurrence: occurrence, in: try snapshot())
    }

    /// Current copy of an exercise by WorkoutExercise.id.
    func exercise(id: UUID) throws -> WorkoutExercise {
        guard let exercise = try snapshot().exercises.first(where: { $0.id == id }) else {
            throw WorkoutEditError.invalidArgument("The exercise is no longer in this workout.")
        }
        return exercise
    }

    /// 1-based set lookup.
    func set(in exerciseId: UUID, number: Int) throws -> ExerciseSet {
        let sets = try exercise(id: exerciseId).sets
        guard number >= 1, number <= sets.count else {
            throw WorkoutEditError.setNotFound(number: number, count: sets.count)
        }
        return sets[number - 1]
    }

    /// Validates parent-field edits against the drop-set invariant (parent
    /// weight/reps are mirrors of segment 1 and must be edited via segments).
    func validateDropSetEdit(_ set: ExerciseSet, exerciseName: String, changes: SetChanges) throws {
        let willBeDropSet = changes.dropSegments.map { !$0.isEmpty } ?? !set.dropSets.isEmpty
        if willBeDropSet, changes.touchesParentFields {
            throw WorkoutEditError.invalidArgument(
                "Set \(set.order) of \(exerciseName) is a drop set; pass drop_segments with every segment (or [] to make it a plain set) instead of weight/reps/set_type."
            )
        }
        if changes.setType == .dropset, changes.dropSegments == nil, set.dropSets.isEmpty {
            throw WorkoutEditError.invalidArgument(
                "set_type dropset requires drop_segments (at least 2 segments including the top set)."
            )
        }
        if let segments = changes.dropSegments, segments.count == 1 {
            throw WorkoutEditError.invalidArgument(
                "drop_segments needs at least 2 segments (the top set plus the drops), or [] to clear."
            )
        }
    }
}
