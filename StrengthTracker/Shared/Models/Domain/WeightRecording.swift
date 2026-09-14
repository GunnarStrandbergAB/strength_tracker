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
        case perDumbbell, combined, perSide, displayed
        public var title: String {
            switch self {
            case .perDumbbell: return "Weight of one dumbbell"
            case .combined: return "Combined weight"
            case .perSide: return "Weight per side"
            case .displayed: return "Displayed load"
            }
        }
        public var isIndividual: Bool { self == .perDumbbell || self == .perSide }
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
    /// Optional on purpose: older records do not establish how the sides moved.
    public enum Execution: String, Codable, CaseIterable, Sendable {
        case together, sequential, alternating
        public var title: String {
            switch self {
            case .together: return "Both sides together"
            case .sequential: return "One side at a time"
            case .alternating: return "Alternating sides"
            }
        }
    }
    public enum Resistance: String, Codable, CaseIterable, Sendable {
        case shared, independent, carriedPair
        public var title: String {
            switch self {
            case .shared: return "One shared load / stack"
            case .independent: return "Separately loaded sides"
            case .carriedPair: return "Two weights carried for each side"
            }
        }
    }
    public var execution: Execution?
    public var resistance: Resistance?
    public var equipment: Equipment
    public var weightEntry: WeightEntry
    public var repetitions: Repetitions
    public init(equipment: Equipment = .pair, weightEntry: WeightEntry = .perDumbbell, repetitions: Repetitions = .standard, execution: Execution? = nil, resistance: Resistance? = nil) {
        self.execution = execution
        self.resistance = resistance
        self.equipment = equipment
        self.weightEntry = weightEntry
        self.repetitions = repetitions
    }
    public static func sides(execution: Execution = .sequential, resistance: Resistance = .independent,
                             weightEntry: WeightEntry = .perSide) -> Self {
        .init(equipment: resistance == .shared ? .single : .pair, weightEntry: weightEntry,
              repetitions: execution == .together ? .standard : .perSide,
              execution: execution, resistance: resistance)
    }
    public var hasSideConfiguration: Bool { execution != nil && resistance != nil }
    public var supportsSeparateSides: Bool {
        hasSideConfiguration && !(execution == .together && resistance != .independent)
    }
    /// Number of physical loads represented by a combined entry, independent of timing.
    public var combinedCount: Double { resistance == .shared ? 1 : equipment.count }
    public var externalLoadMultiplier: Double {
        guard hasSideConfiguration else { return weightEntry.isIndividual ? equipment.count : 1 }
        switch resistance! {
        case .shared: return 1
        case .carriedPair: return weightEntry.isIndividual ? 2 : 1
        case .independent:
            let simultaneous = execution == .together
            return weightEntry.isIndividual ? (simultaneous ? 2 : 1) : (simultaneous ? 1 : 0.5)
        }
    }
    public var repetitionMultiplier: Double { repetitions == .perSide ? 2 : 1 }
    /// External-load tonnage only; the bodyweight base is never multiplied by equipment count.
    public var volumeMultiplier: Double { externalLoadMultiplier * repetitionMultiplier }
    /// Expanded sides always show the weight for ONE side (or the pair carried for that side).
    public var sideWeightScale: Double { resistance == .independent && !weightEntry.isIndividual ? 0.5 : 1 }
    public var sideBaseMultiplier: Double { execution == .together ? 0.5 : 1 }
    public var sideExternalMultiplier: Double { resistance == .carriedPair && weightEntry.isIndividual ? 2 : 1 }
    public var summary: String {
        guard let execution else { return "\(weightEntry.title) · \(repetitions.title)" }
        let coverage = execution == .together ? (resistance == .independent ? "Independent sides" : "Shared load")
            : repetitions == .oneSide ? "One side per set" : "Both sides per set"
        return "\(execution.title) · \(coverage)"
    }
    public func strengthReps(_ entered: Int) -> Int? {
        guard entered > 0 else { return nil }
        guard repetitions == .totalAlternating else { return entered }
        return entered.isMultiple(of: 2) ? entered / 2 : nil
    }
    public var movementKey: String {
        let legacy = repetitions == .totalAlternating ? "alternating" : "perMovement"
        guard let execution, let resistance else { return legacy }
        return "\(execution.rawValue):\(resistance.rawValue)"
    }
    public var performanceKey: String { "\(equipment.rawValue)/\(weightEntry.rawValue)/\(movementKey)" }
    public func weightLabel(_ unit: WeightUnit) -> String {
        let symbol = unit == .kg ? "Kg" : unit.symbol
        switch weightEntry {
        case .perDumbbell: return "\(symbol) each"
        case .perSide: return "\(symbol)/side"
        case .combined: return "\(symbol) total"
        case .displayed: return symbol
        }
    }
    public func sideWeightLabel(_ unit: WeightUnit) -> String {
        resistance == .independent ? "\(unit == .kg ? "Kg" : unit.symbol)/side" : weightLabel(unit)
    }
    public var repsLabel: String { repetitions == .perSide ? "Reps/side" : repetitions == .totalAlternating ? "Reps total" : "Reps" }
    public var explanation: String {
        guard hasSideConfiguration else {
            return "\(weightEntry.title). \(equipment.title). \(repetitions.title). Volume = entered weight × reps × \(Int(volumeMultiplier))."
        }
        return "\(summary). \(resistance!.title). \(weightEntry.title). \(repetitions.title). Complete one set after both sides, or log left and right separately within the same set. Recorded-load volume = entered weight × reps × \(volumeMultiplier.formatted()). Bodyweight contribution, when used, is added once per performed rep. Use the displayed machine load consistently; pulley ratios are not inferred."
    }
    public func validate() throws {
        guard (execution == nil) == (resistance == nil) else { throw WorkoutEditError.invalidArgument("Choose both movement and resistance for side logging.") }
        guard let execution, let resistance else {
            guard weightEntry == .perDumbbell || weightEntry == .combined else { throw WorkoutEditError.invalidArgument("Per-side or displayed load requires a side configuration.") }
            return
        }
        guard equipment == (resistance == .shared ? .single : .pair),
              execution == .together ? repetitions == .standard : repetitions != .standard,
              execution == .alternating || repetitions != .totalAlternating else {
            throw WorkoutEditError.invalidArgument("Use standard reps together, per-side reps one side at a time, or per-side / total reps alternating. Shared load uses one load; independent sides or carried weights use a pair.")
        }
        if resistance == .shared, weightEntry != .displayed { throw WorkoutEditError.invalidArgument("A shared load uses the displayed weight.") }
        if resistance != .shared, weightEntry == .displayed { throw WorkoutEditError.invalidArgument("Choose per-side / individual or combined weight for separate loads.") }
    }

    public var encoded: String? { try? String(decoding: JSONEncoder().encode(self), as: UTF8.self) }
    public static func decode(_ value: String?) -> Self? {
        guard let value else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(value.utf8))
    }
}

extension Exercise {
    public var isDumbbell: Bool { category == .dumbbell }
    public var supportsWeightRecording: Bool { exerciseType == .weightedReps || exerciseType == .bodyweightReps }
    public var strengthRecording: WeightRecording? {
        guard supportsWeightRecording else { return nil }
        // Older bodyweight snapshots sometimes carried unused dumbbell metadata.
        if exerciseType == .bodyweightReps && weightRecording?.hasSideConfiguration != true { return nil }
        return weightRecording
    }
    public var suggestedSideRecording: WeightRecording? {
        guard !isCustom, supportsWeightRecording, weightRecording == nil else { return nil }
        return SideLoggingDefaults.recording(for: name)
    }
    public var recordingNeedsConfirmation: Bool { supportsWeightRecording && weightRecording == nil && (isDumbbell || suggestedSideRecording != nil) }
    public var defaultWeightRecording: WeightRecording {
        weightRecording ?? suggestedSideRecording ?? (isDumbbell ? DumbbellDefaults.recording(for: name) ?? WeightRecording() : .sides(execution: .together, resistance: .shared, weightEntry: .displayed))
    }
    public func strengthReps(_ entered: Int) -> Int? {
        if let recording = strengthRecording { return recording.strengthReps(entered) }
        return entered > 0 ? entered : nil
    }
    public func recordedPerformance(weight: Double, reps: Int, unit: WeightUnit) -> String {
        let symbol = unit == .kg ? "Kg" : unit.symbol
        let weightSuffix = strengthRecording.map {
            switch $0.weightEntry { case .perDumbbell: return " each"; case .perSide: return "/side"; case .combined: return " total"; case .displayed: return "" }
        } ?? ""
        let repSuffix = strengthRecording.map { $0.repetitions == .perSide ? "/side" : $0.repetitions == .totalAlternating ? " total alternating" : $0.repetitions == .oneSide ? " on one side" : "" } ?? ""
        let added = exerciseType == .bodyweightReps ? " added" : ""
        return "\(unit.formatValue(weight)) \(symbol)\(weightSuffix)\(added) × \(reps)\(repSuffix)"
    }
    public var volumeMultiplier: Double { strengthRecording?.volumeMultiplier ?? 1 }
    public var performanceConvention: String {
        if exerciseType == .bodyweightReps { return "bodyweight/\(Int((resolvedBodyweightFactor * 1_000_000).rounded()))" + (strengthRecording.map { "/" + $0.performanceKey } ?? "") }
        return strengthRecording?.performanceKey ?? (isDumbbell ? "unconfirmed" : "standard")
    }
    public var personalRecordConvention: String? {
        exerciseType == .bodyweightReps ? performanceConvention : strengthRecording?.performanceKey
    }
    public func weightEntryLabel(_ unit: WeightUnit) -> String {
        let symbol = unit == .kg ? "Kg" : unit.symbol
        if exerciseType == .bodyweightReps { return "+" + (strengthRecording?.weightLabel(unit) ?? symbol) }
        return strengthRecording?.weightLabel(unit) ?? (isDumbbell ? "\(symbol) ?" : symbol)
    }
    public var weightRecordingExplanation: String? {
        guard strengthRecording != nil || recordingNeedsConfirmation else { return nil }
        return weightRecording?.explanation ?? "Weight convention unconfirmed. Volume uses entered weight × reps. Review Weight logging in Settings."
    }
    public var repetitionsLabel: String { strengthRecording?.repsLabel ?? "Reps" }
    public func volume(of set: ExerciseSet, bodyWeightKg: Double) -> Double {
        set.setVolume(baseLoadPerRep: baseLoadPerRep(bodyWeightKg: bodyWeightKg), recording: strengthRecording)
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
        guard exercise.supportsWeightRecording, let target = exercise.weightRecording else {
            throw WorkoutEditError.invalidArgument("Confirm this exercise's weight convention in Weight logging before converting individual and combined weights.")
        }
        guard entry != target.weightEntry else { return kg }
        return entry == .combined ? kg / target.combinedCount : target.weightEntry == .combined ? kg * target.combinedCount : kg
    }
    public static func convertWeight(_ kg: Double, from source: WeightRecording?, to target: WeightRecording?) -> Double? {
        if source == target { return kg }
        guard let source, let target, source.equipment == target.equipment,
              source.movementKey == target.movementKey else { return nil }
        guard source.weightEntry != target.weightEntry else { return kg }
        return source.weightEntry == .combined ? kg / source.combinedCount : target.weightEntry == .combined ? kg * source.combinedCount : kg
    }
    public static func convertible(_ source: Exercise, to reference: Exercise) -> Bool {
        guard source.exerciseType != .bodyweightReps, reference.exerciseType != .bodyweightReps,
              source.id == reference.id, let a = source.weightRecording, let b = reference.weightRecording else { return false }
        return a.equipment == b.equipment && a.movementKey == b.movementKey
    }
    /// Transient performance view only. Persistence always retains the source numbers.
    public static func converted(_ entry: WorkoutExercise, to reference: Exercise?) -> WorkoutExercise {
        guard let reference, convertible(entry.exercise, to: reference),
              let source = entry.exercise.weightRecording, let target = reference.weightRecording else { return entry }
        var copy = entry
        let scale = convertWeight(1, from: source, to: target) ?? 1
        func convertedReps(_ reps: Int?) -> Int? {
            guard source.repetitions != target.repetitions else { return reps }
            guard let reps, let perSide = source.strengthReps(reps) else { return nil }
            return target.repetitions == .totalAlternating ? perSide * 2 : perSide
        }
        copy.sets = copy.sets.map { set in
            var adjusted = set
            if let sides = set.sideSets {
                let sideScale = source.sideExternalMultiplier / target.sideExternalMultiplier
                adjusted.applySideSets(sides.map { side in
                    var result = side
                    result.effort.weight = side.effort.weight.map { $0 * sideScale }
                    if !side.effort.dropSets.isEmpty { result.effort.applyDropSets(side.effort.dropSets.map { part in
                        var p = part; p.weight = part.weight.map { $0 * sideScale }; return p
                    }) }
                    return result
                })
            } else if set.dropSets.isEmpty {
                adjusted.weight = set.weight.map { $0 * scale }
                adjusted.reps = convertedReps(set.reps)
            } else { adjusted.applyDropSets(set.dropSets.map { part in
                var part = part; part.weight = part.weight.map { $0 * scale }; part.reps = convertedReps(part.reps); return part
            }) }
            return adjusted
        }
        copy.exercise.weightRecording = target
        if source.execution == nil { copy.exercise.weightRecording?.repetitions = source.repetitions }
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

/// Reviewed library suggestions only. Applying one requires user confirmation and
/// never rewrites historical snapshots based on an exercise name.
public enum SideLoggingDefaults {
    public static func recording(for name: String) -> WeightRecording? {
        let names: Set<String> = ["Single-Arm Cable Row", "Single-Arm Lat Pulldown", "Single-Arm Cable Tricep Extension"]
        return names.contains(name) ? .sides() : nil
    }
}
