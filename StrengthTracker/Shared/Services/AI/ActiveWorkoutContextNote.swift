import Foundation

/// Builds the per-turn "[App state …]" note describing the active workout. The
/// system prompt is frozen for a conversation (xAI rejects instructions on
/// continuation turns), so live state travels as a bracketed user-role note.
@MainActor
public final class ActiveWorkoutContextNoteProvider {
    private let workoutViewModel: WorkoutViewModel
    private let userPreferencesService: UserPreferencesService
    private let now: () -> Date

    public init(
        workoutViewModel: WorkoutViewModel,
        userPreferencesService: UserPreferencesService,
        now: @escaping () -> Date = Date.init
    ) {
        self.workoutViewModel = workoutViewModel
        self.userPreferencesService = userPreferencesService
        self.now = now
    }

    public func note() -> String {
        guard workoutViewModel.isActive, let workout = workoutViewModel.currentWorkout else {
            if workoutViewModel.watchActiveWorkout != nil {
                return "[App state, auto-generated: a workout is in progress on Apple Watch; it cannot be edited from here.]"
            }
            return "[App state, auto-generated: no active workout.]"
        }
        return Self.format(
            workout: workout,
            weightUnit: userPreferencesService.weightUnit,
            intensityMetric: userPreferencesService.intensityMetric,
            now: now()
        )
    }

    /// Pure formatter, testable without a ViewModel.
    public static func format(
        workout: Workout,
        weightUnit: WeightUnit,
        intensityMetric: IntensityMetric,
        now: Date
    ) -> String {
        let started = workout.startedAt.formatted(date: .omitted, time: .shortened)
        let minutes = max(0, Int(now.timeIntervalSince(workout.startedAt) / 60))
        var header = "[App state, auto-generated: active workout \"\(workout.name)\" · started \(started) (\(minutes) min ago)"
        if workout.isDeload { header += " · deload" }
        if workout.plannedPlanId != nil { header += " · plan session" }

        var lines = [header]
        let exercises = workout.exercises.sorted { $0.order < $1.order }
        let nameCounts = Dictionary(exercises.map { ($0.exercise.name, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]
        for (index, exercise) in exercises.prefix(15).enumerated() {
            let name = exercise.exercise.name
            seen[name, default: 0] += 1
            var label = name
            if (nameCounts[name] ?? 1) > 1 { label += " (\(seen[name]!))" }
            let done = exercise.sets.filter(\.isCompleted).count
            var parts = ["\(index + 1). \(label): \(done)/\(exercise.sets.count) done"]
            if let last = exercise.sets.last(where: \.isCompleted) {
                parts.append("last " + describe(last, unit: weightUnit, metric: intensityMetric))
            }
            if let nextIndex = exercise.sets.firstIndex(where: { !$0.isCompleted }) {
                let next = exercise.sets[nextIndex]
                var planned = "next set \(nextIndex + 1)"
                let target = describe(next, unit: weightUnit, metric: intensityMetric)
                if !target.isEmpty { planned += " planned \(target)" }
                parts.append(planned)
            }
            if let notes = exercise.notes, !notes.isEmpty {
                parts.append("notes: \"\(notes.prefix(40))\"")
            }
            lines.append(parts.joined(separator: " · "))
        }
        if exercises.count > 15 {
            lines.append("… \(exercises.count - 15) more exercises")
        }
        if let notes = workout.notes, !notes.isEmpty {
            lines.append("Workout notes: \"\(notes.prefix(60))\"")
        }
        lines.append("Weights in \(weightUnit.symbol). Refer to exercises by name and sets by 1-based number.]")
        return lines.joined(separator: "\n")
    }

    /// "85kg×8 RPE9 F" style; drop sets as "85×8→70×6".
    static func describe(_ set: ExerciseSet, unit: WeightUnit, metric: IntensityMetric) -> String {
        func load(_ weight: Double?, _ reps: Int?, withUnit: Bool) -> String? {
            switch (weight, reps) {
            case (let w?, let r?):
                return "\(AIJSON.compact(unit.fromKg(w), maxFractionDigits: 2))\(withUnit ? unit.symbol : "")×\(r)"
            case (let w?, nil):
                return "\(AIJSON.compact(unit.fromKg(w), maxFractionDigits: 2))\(withUnit ? unit.symbol : "")"
            case (nil, let r?):
                return "\(r) reps"
            default:
                return nil
            }
        }
        var parts: [String] = []
        if !set.dropSets.isEmpty {
            let segments = set.dropSets.compactMap { load($0.weight, $0.reps, withUnit: false) }
            if !segments.isEmpty { parts.append(segments.joined(separator: "→")) }
        } else if let text = load(set.weight, set.reps, withUnit: true) {
            parts.append(text)
        } else if let seconds = set.durationSeconds {
            parts.append("\(seconds)s")
        }
        if let value = set.intensityValue(for: metric) {
            parts.append("\(metric.displayName)\(AIJSON.compact(value))")
        }
        if set.isFailure { parts.append("F") }
        if set.setType == .warmup { parts.append("warmup") }
        return parts.joined(separator: " ")
    }
}
