import Foundation

// MARK: - Effective Load
//
// The single choke point for the effective-load model: for `.bodyweightReps`
// exercises, the load moved per rep is bodyWeight × factor PLUS any added weight
// (the set's `weight` field means EXTRA kg — belt, vest, chains). For all other
// exercise types the set's weight IS the load, unchanged.
//
// Never hand-roll `bw × factor + weight` at call sites — go through these helpers
// so the fallback (factor nil → 1.0) and the extra-kg semantics stay uniform.

extension Exercise {
    public var resolvedBodyweightFactor: Double {
        let factor = bodyweightFactorOverride ?? bodyweightFactor ?? 1
        return factor.isFinite && (0.1...1.5).contains(factor) ? factor : 1
    }

    public var bodyweightPercentLabel: String {
        (resolvedBodyweightFactor * 100).formatted(.number.precision(.fractionLength(0...2))) + "%"
    }

    public var bodyweightExplanation: String? {
        guard exerciseType == .bodyweightReps else { return nil }
        return "Estimated bodyweight contribution: \(bodyweightPercentLabel). Enter only additional weight. Effective load = bodyweight × percentage + added weight."
    }

    /// Only refresh the bodyweight setting, never the template's other metadata
    /// or prescribed added weights. Used at new-session boundaries.
    public func resolvingBodyweight(from library: [Exercise]) -> Exercise {
        guard exerciseType == .bodyweightReps,
              let current = library.first(where: { $0.id == id && $0.exerciseType == .bodyweightReps }) else { return self }
        var copy = self
        copy.bodyweightFactor = current.resolvedBodyweightFactor
        copy.bodyweightFactorOverride = nil
        return copy
    }
    /// The base load every rep moves BEFORE added weight: `bodyWeight × (factor ?? 1.0)`
    /// for `.bodyweightReps` exercises, nil for every other type.
    public func baseLoadPerRep(bodyWeightKg: Double) -> Double? {
        exerciseType == .bodyweightReps ? bodyWeightKg * resolvedBodyweightFactor : nil
    }
}

extension WorkoutTemplate {
    public func resolvingBodyweight(from library: [Exercise]) -> WorkoutTemplate {
        var copy = self
        for i in copy.exercises.indices {
            copy.exercises[i].exercise = copy.exercises[i].exercise.resolvingBodyweight(from: library)
        }
        return copy
    }
}

/// Shared validation for the exercise form, detail editor and AI creation tool.
public enum BodyweightPercentage {
    public enum Invalid: Error, LocalizedError {
        case percentage
        public var errorDescription: String? { "Enter a percentage between 10 and 150." }
    }
    public static func factor(percent: Double) throws -> Double {
        guard percent.isFinite, (10...150).contains(percent) else { throw Invalid.percentage }
        return percent / 100
    }
    public static func parse(_ text: String) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let percent = Double(value.replacingOccurrences(of: ",", with: ".")) else { throw Invalid.percentage }
        _ = try factor(percent: percent)
        return percent
    }
}

extension DropSetEntry {
    /// Effective load of one performed part. With a bodyweight base: base + extra kg
    /// (nil weight = no extra). Without: the weight as-is (nil stays nil).
    public func effectiveLoad(baseLoadPerRep: Double?) -> Double? {
        if let base = baseLoadPerRep { return base + (weight ?? 0) }
        return weight
    }
}

extension ExerciseSet {
    /// Strength-only interpretation; volume and recorded rep history stay intact.
    public func strengthParts(baseLoadPerRep: Double?, recording: WeightRecording? = nil) -> [(load: Double, reps: Int)] {
        effectiveLoadParts(baseLoadPerRep: baseLoadPerRep).compactMap { part in
            guard part.load.isFinite else { return nil }
            let reps: Int? = recording == nil ? part.reps : recording?.strengthReps(part.reps)
            guard let reps, reps > 0 else { return nil }
            return (part.load, reps)
        }
    }
    /// (load, reps) for every performed part with a positive effective load and reps —
    /// the canonical input for e1RM, max-weight PRs, and IWV candidates.
    public func effectiveLoadParts(baseLoadPerRep: Double?) -> [(load: Double, reps: Int)] {
        effectiveParts.compactMap { part in
            guard let load = part.effectiveLoad(baseLoadPerRep: baseLoadPerRep), load > 0,
                  let reps = part.reps, reps > 0 else { return nil }
            return (load, reps)
        }
    }
}
