import Foundation

/// Describes what the *entered* numbers mean. Nil on a snapshot means legacy,
/// unconfirmed logging: retain the original weight × reps calculation.
public struct WeightRecording: Codable, Hashable, Sendable {
    public enum Equipment: String, Codable, CaseIterable, Sendable {
        case single, pair
        public var title: String { self == .single ? "One dumbbell per repetition" : "Two dumbbells per repetition" }
        public var count: Double { self == .single ? 1 : 2 }
    }
    public enum WeightEntry: String, Codable, CaseIterable, Sendable {
        case perDumbbell, combined
        public var title: String { self == .perDumbbell ? "Weight of one dumbbell" : "Combined weight" }
    }
    public enum Repetitions: String, Codable, CaseIterable, Sendable {
        case standard, perSide, totalAlternating, oneSide
        public var title: String {
            switch self {
            case .standard: return "Reps as entered"
            case .perSide: return "Reps per side; row covers both sides"
            case .totalAlternating: return "Total alternating reps"
            case .oneSide: return "One side only; separate row for other side"
            }
        }
    }
    public var equipment: Equipment
    public var weightEntry: WeightEntry
    public var repetitions: Repetitions
    public init(equipment: Equipment = .pair, weightEntry: WeightEntry = .perDumbbell, repetitions: Repetitions = .standard) {
        self.equipment = equipment
        self.weightEntry = weightEntry
        self.repetitions = repetitions
    }
    /// Tonnage only. Never apply this to e1RM, target weights, RPE or hard-set counts.
    public var volumeMultiplier: Double {
        (weightEntry == .perDumbbell ? equipment.count : 1) * (repetitions == .perSide ? 2 : 1)
    }
    /// Strength is estimated per side, never from the sum of both sides' reps.
    /// Odd alternating totals do not tell us how many reps each side performed.
    public func strengthReps(_ entered: Int) -> Int? {
        guard entered > 0 else { return nil }
        guard repetitions == .totalAlternating else { return entered }
        return entered.isMultiple(of: 2) ? entered / 2 : nil
    }
    /// Strength remains in the recorded convention. Incompatible conventions form
    /// separate histories, rather than manufacturing a PR when a setting changes.
    public var performanceKey: String { "\(equipment.rawValue)/\(weightEntry.rawValue)/\(repetitions == .totalAlternating ? "alternating" : "perMovement")" }
    public func weightLabel(_ unit: WeightUnit) -> String { "\(unit.symbol) \(weightEntry == .perDumbbell ? "each" : "total")" }
    public var repsLabel: String { repetitions == .perSide ? "Reps/side" : "Reps" }
    public var explanation: String {
        "\(weightEntry.title). \(equipment.title). \(repetitions.title). Volume = entered weight × reps × \(Int(volumeMultiplier))."
    }
    public var encoded: String? { try? String(decoding: JSONEncoder().encode(self), as: UTF8.self) }
    public static func decode(_ value: String?) -> Self? {
        guard let value else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(value.utf8))
    }
}

extension Exercise {
    public var isDumbbell: Bool { category == .dumbbell }
    public var strengthRecording: WeightRecording? { isDumbbell && exerciseType == .weightedReps ? weightRecording : nil }
    public func strengthReps(_ entered: Int) -> Int? {
        if let recording = strengthRecording { return recording.strengthReps(entered) }
        return entered > 0 ? entered : nil
    }
    public func recordedPerformance(weight: Double, reps: Int, unit: WeightUnit) -> String {
        let symbol = unit == .kg ? "Kg" : unit.symbol
        let weightSuffix = strengthRecording.map { $0.weightEntry == .perDumbbell ? " each" : " total" } ?? ""
        let repSuffix = strengthRecording.map { $0.repetitions == .perSide ? "/side" : $0.repetitions == .totalAlternating ? " total alternating" : $0.repetitions == .oneSide ? " on one side" : "" } ?? ""
        let added = exerciseType == .bodyweightReps ? " added" : ""
        return "\(unit.formatValue(weight)) \(symbol)\(weightSuffix)\(added) × \(reps)\(repSuffix)"
    }
    public var volumeMultiplier: Double { isDumbbell && exerciseType == .weightedReps ? weightRecording?.volumeMultiplier ?? 1 : 1 }
    public var performanceConvention: String {
        if exerciseType == .bodyweightReps { return "bodyweight/\(Int((resolvedBodyweightFactor * 1_000_000).rounded()))" }
        return isDumbbell ? weightRecording?.performanceKey ?? "unconfirmed" : "standard"
    }
    public var personalRecordConvention: String? {
        exerciseType == .bodyweightReps ? performanceConvention : isDumbbell ? weightRecording?.performanceKey : nil
    }
    public func weightEntryLabel(_ unit: WeightUnit) -> String {
        if exerciseType == .bodyweightReps { return "+\(unit.symbol)" }
        return isDumbbell ? weightRecording?.weightLabel(unit) ?? "\(unit.symbol) ?" : unit.symbol
    }
    public var weightRecordingExplanation: String? {
        guard isDumbbell else { return nil }
        return weightRecording?.explanation ?? "Weight convention unconfirmed. Volume uses entered weight × reps. Review Weight logging in Settings."
    }
    public var repetitionsLabel: String { isDumbbell ? weightRecording?.repsLabel ?? "Reps" : "Reps" }
    public func volume(of set: ExerciseSet, bodyWeightKg: Double) -> Double {
        set.setVolume(baseLoadPerRep: baseLoadPerRep(bodyWeightKg: bodyWeightKg), multiplier: volumeMultiplier)
    }
}

/// Explicit seed classification; never infer a historical convention from a name.
public enum DumbbellDefaults {
    public static func recording(for name: String) -> WeightRecording? {
        if pairs.contains(name) { return .init() }
        if singles.contains(name) { return .init(equipment: .single) }
        if singlePerSide.contains(name) { return .init(equipment: .single, repetitions: .perSide) }
        if pairPerSide.contains(name) { return .init(equipment: .pair, repetitions: .perSide) }
        return nil
    }
    private static let pairs: Set<String> = [
        "Dumbbell Bench Press", "Incline Dumbbell Press", "Dumbbell Chest Fly", "Dumbbell Shoulder Press",
        "Lateral Raise", "Front Raise", "Dumbbell Curl", "Hammer Curl", "Dumbbell Shrug", "Man Maker",
        "Decline Dumbbell Bench Press", "Dumbbell Floor Press", "Incline Dumbbell Fly", "Dumbbell Squeeze Press",
        "Chest-Supported Dumbbell Row", "Arnold Press", "Dumbbell Front Raise", "Dumbbell Rear Delt Fly",
        "Dumbbell Upright Row", "Incline Prone Dumbbell Shrug", "Prone Y-Raise", "Incline Dumbbell Curl",
        "Spider Curl", "Zottman Curl", "Incline Hammer Curl", "Tate Press", "Dumbbell Wrist Curl",
        "Dumbbell Reverse Wrist Curl", "Dumbbell Stiff-Leg Deadlift", "Dumbbell Thruster", "Devil Press", "Farmer's Walk"
    ]
    private static let singles: Set<String> = ["Overhead Tricep Extension", "Goblet Squat", "Dumbbell Pullover", "Dumbbell Overhead Tricep Extension", "Suitcase Carry", "Weighted Decline Sit-Up"]
    private static let singlePerSide: Set<String> = [
        "One-Arm Dumbbell Row", "Single-Arm Dumbbell Bench Press", "Kroc Row", "Helms Row", "Concentration Curl",
        "Cross-Body Hammer Curl", "Single-Arm Dumbbell Overhead Extension", "Dumbbell Kickback",
        "Single-Leg Dumbbell Romanian Deadlift", "Dumbbell Single-Leg Calf Raise", "Weighted Standing Knee Raise", "Dumbbell Side Bend"
    ]
    private static let pairPerSide: Set<String> = ["Walking Lunge", "Bulgarian Split Squat", "Dumbbell Step-Up", "Dumbbell Lateral Lunge"]
}

public enum WeightRecordingHistory {
    /// A known conversion is used at an input boundary; unconfirmed values are
    /// never guessed. Repetition conventions must be specified independently.
    public static func inputWeight(_ kg: Double, entry: WeightRecording.WeightEntry?, for exercise: Exercise) throws -> Double {
        guard let entry else { return kg }
        guard exercise.isDumbbell, let target = exercise.weightRecording else {
            throw WorkoutEditError.invalidArgument("Confirm this exercise's weight convention in Weight logging before converting per-dumbbell and combined weights.")
        }
        guard entry != target.weightEntry else { return kg }
        return entry == .combined ? kg / target.equipment.count : kg * target.equipment.count
    }
    public static func convertWeight(_ kg: Double, from source: WeightRecording?, to target: WeightRecording?) -> Double? {
        if source == target { return kg }
        guard let source, let target, source.equipment == target.equipment,
              (source.repetitions == .totalAlternating) == (target.repetitions == .totalAlternating) else { return nil }
        guard source.weightEntry != target.weightEntry else { return kg }
        return source.weightEntry == .combined ? kg / source.equipment.count : kg * source.equipment.count
    }
    public static func convertible(_ source: Exercise, to reference: Exercise) -> Bool {
        guard source.exerciseType != .bodyweightReps, reference.exerciseType != .bodyweightReps,
              source.id == reference.id, let a = source.weightRecording, let b = reference.weightRecording else { return false }
        return a.equipment == b.equipment && (a.repetitions == .totalAlternating) == (b.repetitions == .totalAlternating)
    }
    /// Transient performance view only. Persistence always retains the source numbers.
    public static func converted(_ entry: WorkoutExercise, to reference: Exercise?) -> WorkoutExercise {
        guard let reference, convertible(entry.exercise, to: reference),
              let source = entry.exercise.weightRecording, let target = reference.weightRecording,
              source.weightEntry != target.weightEntry else { return entry }
        var copy = entry
        let scale = source.weightEntry == .combined ? 1 / source.equipment.count : source.equipment.count
        copy.sets = copy.sets.map { set in
            var adjusted = set
            if set.dropSets.isEmpty { adjusted.weight = set.weight.map { $0 * scale } }
            else { adjusted.applyDropSets(set.dropSets.map { part in var part = part; part.weight = part.weight.map { $0 * scale }; return part }) }
            return adjusted
        }
        copy.exercise.weightRecording?.weightEntry = target.weightEntry
        return copy
    }
    public static func relativeKey(_ exercise: Exercise) -> String { exercise.id.uuidString + "/" + exercise.performanceConvention }
    /// Baselines for mixed histories, expressed in each observation's own units.
    /// Known conversions share evidence; unresolved/incompatible histories don't.
    public static func relativeBaselines(_ workouts: [Workout], bodyWeightKg: Double) -> [String: Double] {
        let grouped = Dictionary(grouping: workouts.flatMap(\.exercises), by: { $0.exercise.id })
        var result: [String: Double] = [:]
        for (_, rows) in grouped where Set(rows.map { $0.exercise.performanceConvention }).count > 1 {
            let references = Dictionary(rows.map { ($0.exercise.performanceConvention, $0.exercise) }, uniquingKeysWith: { a, _ in a })
            for reference in references.values {
                let compatible = rows.filter { $0.exercise.performanceConvention == reference.performanceConvention || convertible($0.exercise, to: reference) }
                result[relativeKey(reference)] = compatible.compactMap { source in
                    let entry = converted(source, to: reference)
                    return AnalyticsCalculations.bestE1RM(in: entry.sets, baseLoadPerRep: entry.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg), recording: entry.exercise.strengthRecording)
                }.max() ?? 0
            }
        }
        return result
    }
    public static func latestExercises(_ workouts: [Workout]) -> [UUID: Exercise] {
        var result: [UUID: Exercise] = [:]
        for w in workouts.sorted(by: { $0.trainingDate < $1.trainingDate }) {
            for e in w.exercises where e.sets.contains(where: { $0.isCompleted && $0.setType != .warmup }) { result[e.exercise.id] = e.exercise }
        }
        return result
    }
    public static func matching(_ workouts: [Workout], references: [UUID: Exercise]? = nil) -> [Workout] {
        let refs = references ?? latestExercises(workouts)
        return workouts.map { workout in
            var copy = workout
            copy.exercises = copy.exercises.filter { entry in
                guard let reference = refs[entry.exercise.id] else { return true }
                return reference.performanceConvention == entry.exercise.performanceConvention
                    || convertible(entry.exercise, to: reference)
            }.map { converted($0, to: refs[$0.exercise.id]) }
            return copy
        }
    }
}
