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
    /// The base load every rep moves BEFORE added weight: `bodyWeight × (factor ?? 1.0)`
    /// for `.bodyweightReps` exercises, nil for every other type.
    public func baseLoadPerRep(bodyWeightKg: Double) -> Double? {
        exerciseType == .bodyweightReps ? bodyWeightKg * (bodyweightFactor ?? 1.0) : nil
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
