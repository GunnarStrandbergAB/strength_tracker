import Foundation

/// Computes per-muscle volume-response analyses from a workout history.
///
/// Observation-only model:
/// 1. Per-week effective hard sets per muscle (1.0 primary, 0.5 split across secondaries — matches `VolumeLandmarkService`).
/// 2. Dose = 3-week trailing average of effective hard sets.
/// 3. Per-exercise normalised response over non-overlapping [W-3..W-1] vs [W+1..W+3] windows of weekly best e1RM.
/// 4. Aggregate to muscle via contribution-weighted median.
/// 5. Mature weeks only (W+3 must have elapsed).
/// 6. Static literature-aligned bins: 0-4, 5-8, 9-12, 13-16, 17-20, 21+.
/// 7. Robust per-bin centre (median / 20%-trimmed mean) + IQR.
/// 8. Triangular smoothing across populated neighbours only.
/// 9. Status-aware landmarks (BestRangeStatus / LowerBoundStatus / UpperBoundStatus).
/// 10. Per-muscle confidence from data shape (bins, N, range coverage, continuity, IQR overlap).
public enum VolumeResponseService {

    // MARK: - Public

    /// Compute one analysis per trained muscle group.
    /// Pass the upstream `overloadTrends` to reuse the weekly best-e1RM series.
    public static func computeAnalyses(
        workouts: [Workout],
        overloadTrends: [OverloadTrend],
        now: Date = Date()
    ) -> [VolumeResponseAnalysis] {
        let completed = workouts.filter { $0.completedAt != nil }
        guard !completed.isEmpty else { return [] }

        let calendar = Calendar.mondayStart
        // Map exercises that appear in history to their primary muscle group, for continuity calc.
        var exercisesPerMuscleWeek: [String: [Date: Set<UUID>]] = [:]

        // Step 1 — effectiveHardSets(M, week) for every (muscle, week) in history.
        let effectiveSets = computeEffectiveHardSetsPerWeek(
            completed: completed,
            calendar: calendar,
            exercisesPerMuscleWeek: &exercisesPerMuscleWeek
        )

        // Index per-exercise weekly e1RM by exerciseId for fast lookup.
        let e1rmByExercise: [UUID: [Date: Double]] = overloadTrends.reduce(into: [:]) { acc, trend in
            acc[trend.exerciseId] = trend.weeklyE1RMs.reduce(into: [:]) { dict, entry in
                dict[entry.weekStart] = entry.e1rm
            }
        }
        // Map exercise → primary muscle, taken from history (first occurrence).
        let primaryMuscleByExercise: [UUID: String] = primaryMuscleMap(completed: completed)
        // Map exercise → all (primary+secondary) muscles with contribution weights.
        let contributionsByExercise: [UUID: [String: Double]] = contributionsMap(completed: completed)

        // Maturity cutoff: only weeks W where W+3 has elapsed are mature.
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let maturityCutoff = calendar.date(byAdding: .weekOfYear, value: -3, to: thisWeekStart)!

        // Per-muscle data shaping.
        var analyses: [VolumeResponseAnalysis] = []
        let muscleGroups = Set(effectiveSets.keys)
        for muscle in muscleGroups.sorted() {
            let analysis = computeForMuscle(
                muscle: muscle,
                effectiveSetsForMuscle: effectiveSets[muscle] ?? [:],
                e1rmByExercise: e1rmByExercise,
                primaryMuscleByExercise: primaryMuscleByExercise,
                contributionsByExercise: contributionsByExercise,
                exercisesPerWeekForMuscle: exercisesPerMuscleWeek[muscle] ?? [:],
                maturityCutoff: maturityCutoff,
                calendar: calendar
            )
            analyses.append(analysis)
        }
        return analyses
    }

    // MARK: - Step 1 — effective hard sets per (muscle, week)

    private static func computeEffectiveHardSetsPerWeek(
        completed: [Workout],
        calendar: Calendar,
        exercisesPerMuscleWeek: inout [String: [Date: Set<UUID>]]
    ) -> [String: [Date: Double]] {
        var out: [String: [Date: Double]] = [:]
        for workout in completed {
            // Exclude deload weeks.
            guard !workout.isDeload else { continue }
            let workoutDate = workout.completedAt ?? workout.startedAt
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: workoutDate)?.start else { continue }

            for we in workout.exercises {
                let hardSets = we.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                guard hardSets > 0 else { continue }

                let primary = we.exercise.primaryMuscleGroup.rawValue
                out[primary, default: [:]][weekStart, default: 0] += Double(hardSets)
                exercisesPerMuscleWeek[primary, default: [:]][weekStart, default: []].insert(we.exercise.id)

                let secondaries = we.exercise.secondaryMuscleGroups
                if !secondaries.isEmpty {
                    let perSecondary = Double(hardSets) * 0.5 / Double(secondaries.count)
                    for sec in secondaries {
                        let key = sec.rawValue
                        out[key, default: [:]][weekStart, default: 0] += perSecondary
                        exercisesPerMuscleWeek[key, default: [:]][weekStart, default: []].insert(we.exercise.id)
                    }
                }
            }
        }
        return out
    }

    // MARK: - Helpers: exercise → muscle maps

    private static func primaryMuscleMap(completed: [Workout]) -> [UUID: String] {
        var map: [UUID: String] = [:]
        for w in completed {
            for we in w.exercises where map[we.exercise.id] == nil {
                map[we.exercise.id] = we.exercise.primaryMuscleGroup.rawValue
            }
        }
        return map
    }

    private static func contributionsMap(completed: [Workout]) -> [UUID: [String: Double]] {
        var map: [UUID: [String: Double]] = [:]
        for w in completed {
            for we in w.exercises where map[we.exercise.id] == nil {
                var contribs: [String: Double] = [we.exercise.primaryMuscleGroup.rawValue: 1.0]
                let secondaries = we.exercise.secondaryMuscleGroups
                if !secondaries.isEmpty {
                    let perSecondary = 0.5 / Double(secondaries.count)
                    for sec in secondaries {
                        contribs[sec.rawValue] = perSecondary
                    }
                }
                map[we.exercise.id] = contribs
            }
        }
        return map
    }

    // MARK: - Step 2-10 — per-muscle pipeline

    private struct MuscleObservation {
        let weekStart: Date
        let dose: Double
        let response: Double
    }

    private static func computeForMuscle(
        muscle: String,
        effectiveSetsForMuscle: [Date: Double],
        e1rmByExercise: [UUID: [Date: Double]],
        primaryMuscleByExercise: [UUID: String],
        contributionsByExercise: [UUID: [String: Double]],
        exercisesPerWeekForMuscle: [Date: Set<UUID>],
        maturityCutoff: Date,
        calendar: Calendar
    ) -> VolumeResponseAnalysis {
        let allWeeks = effectiveSetsForMuscle.keys.sorted()
        guard !allWeeks.isEmpty else {
            return insufficient(muscle: muscle, reason: .noTraining)
        }

        // Build the list of mature observations.
        var observations: [MuscleObservation] = []
        for week in allWeeks where week <= maturityCutoff {
            // Step 2 — dose = mean over [W-2, W-1, W] of effective sets. Skip if < 2 of 3 weeks have data.
            let dosePresent = (-2...0).compactMap { offset -> Double? in
                guard let date = calendar.date(byAdding: .weekOfYear, value: offset, to: week),
                      let v = effectiveSetsForMuscle[date], v > 0 else { return nil }
                return v
            }
            guard dosePresent.count >= 2 else { continue }
            let dose = dosePresent.reduce(0, +) / Double(dosePresent.count)

            // Step 3-4 — response: per-exercise normalised, then contribution-weighted median.
            guard let response = muscleResponse(
                muscle: muscle,
                week: week,
                e1rmByExercise: e1rmByExercise,
                contributionsByExercise: contributionsByExercise,
                calendar: calendar
            ) else { continue }

            observations.append(MuscleObservation(weekStart: week, dose: dose, response: response))
        }

        guard !observations.isEmpty else {
            return insufficient(muscle: muscle, reason: .notMatureEnough)
        }

        // Step 6 — bin
        var byBin: [VolumeBin: [Double]] = [:]
        for obs in observations {
            let bin = VolumeBin.bin(for: obs.dose)
            byBin[bin, default: []].append(obs.response)
        }

        // Step 7 — robust per-bin aggregation
        let bins: [BinResponse] = VolumeBin.allCases.map { bin in
            let values = byBin[bin] ?? []
            let n = values.count
            guard n >= 3 else {
                return BinResponse(bin: bin, observationCount: n, median: nil, q1: nil, q3: nil, smoothed: nil)
            }
            let centre = n >= 10 ? trimmedMean(values, trimFraction: 0.2) : median(values)
            let q1v = quantile(values, p: 0.25)
            let q3v = quantile(values, p: 0.75)
            return BinResponse(bin: bin, observationCount: n, median: centre, q1: q1v, q3: q3v, smoothed: nil)
        }

        // Step 8 — triangular smoothing (only across populated neighbours)
        let smoothed = applyTriangularSmoothing(bins: bins)

        // Step 9 — landmarks
        let best = computeBestRange(bins: smoothed)
        let lower = computeLowerBound(bins: smoothed)
        let upper = computeUpperBound(bins: smoothed, observations: observations, best: best)

        // Step 10 — confidence
        let testedRange = computeTestedRange(observations: observations)
        let continuity = computeContinuity(exercisesPerWeek: exercisesPerWeekForMuscle, calendar: calendar)
        let confidence = computeConfidence(bins: smoothed, best: best, continuity: continuity)

        let sentence = buildSentence(
            muscle: muscle,
            observations: observations.count,
            best: best,
            lower: lower,
            upper: upper,
            confidence: confidence,
            bins: smoothed
        )

        return VolumeResponseAnalysis(
            muscleGroup: muscle,
            bins: smoothed,
            best: best,
            lower: lower,
            upper: upper,
            confidence: confidence,
            testedRange: testedRange,
            sentence: sentence
        )
    }

    // MARK: - Step 3-4: per-exercise response → muscle aggregation

    private static func muscleResponse(
        muscle: String,
        week: Date,
        e1rmByExercise: [UUID: [Date: Double]],
        contributionsByExercise: [UUID: [String: Double]],
        calendar: Calendar
    ) -> Double? {
        var weightedValues: [(value: Double, weight: Double)] = []

        for (exerciseId, contribs) in contributionsByExercise {
            guard let weight = contribs[muscle], weight > 0 else { continue }
            guard let series = e1rmByExercise[exerciseId] else { continue }

            let baselineWeeks = (-3...(-1)).compactMap { offset -> Double? in
                guard let date = calendar.date(byAdding: .weekOfYear, value: offset, to: week),
                      let v = series[date] else { return nil }
                return v
            }
            let futureWeeks = (1...3).compactMap { offset -> Double? in
                guard let date = calendar.date(byAdding: .weekOfYear, value: offset, to: week),
                      let v = series[date] else { return nil }
                return v
            }
            guard baselineWeeks.count >= 2, futureWeeks.count >= 2 else { continue }

            let baseline = baselineWeeks.reduce(0, +) / Double(baselineWeeks.count)
            let future = futureWeeks.reduce(0, +) / Double(futureWeeks.count)
            guard baseline > 0 else { continue }

            let response = (future - baseline) / baseline
            weightedValues.append((response, weight))
        }

        guard !weightedValues.isEmpty else { return nil }
        return weightedMedian(weightedValues)
    }

    // MARK: - Step 8: triangular smoothing

    private static func applyTriangularSmoothing(bins: [BinResponse]) -> [BinResponse] {
        let n = bins.count
        var out: [BinResponse] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let me = bins[i]
            // Only smooth if me is populated AND both neighbours are populated.
            let leftIdx = i - 1
            let rightIdx = i + 1
            guard me.isPopulated,
                  leftIdx >= 0, rightIdx < n,
                  bins[leftIdx].isPopulated, bins[rightIdx].isPopulated,
                  let l = bins[leftIdx].median, let m = me.median, let r = bins[rightIdx].median else {
                out.append(BinResponse(
                    bin: me.bin,
                    observationCount: me.observationCount,
                    median: me.median,
                    q1: me.q1,
                    q3: me.q3,
                    smoothed: me.median
                ))
                continue
            }
            let smoothed = 0.25 * l + 0.5 * m + 0.25 * r
            out.append(BinResponse(
                bin: me.bin,
                observationCount: me.observationCount,
                median: me.median,
                q1: me.q1,
                q3: me.q3,
                smoothed: smoothed
            ))
        }
        return out
    }

    // MARK: - Step 9: landmark derivation

    private static func computeBestRange(bins: [BinResponse]) -> BestRangeStatus {
        let populated = bins.enumerated().filter { $0.element.isPopulated && $0.element.smoothed != nil }
        // Need at least two populated bins to call something "best" — comparison is the whole point.
        guard populated.count >= 2 else { return .insufficient }

        // Find the bin with the highest smoothed value.
        guard let topIdx = populated.max(by: { ($0.element.smoothed ?? -.infinity) < ($1.element.smoothed ?? -.infinity) })?.offset else {
            return .insufficient
        }
        let topBin = bins[topIdx]

        // Check for unclear: any other populated bin whose IQR overlaps the top bin's IQR by > 50%.
        if let topQ1 = topBin.q1, let topQ3 = topBin.q3, topQ3 > topQ1 {
            let topSpan = topQ3 - topQ1
            let overlapping = populated.filter { $0.offset != topIdx }.compactMap { entry -> VolumeBin? in
                guard let q1 = entry.element.q1, let q3 = entry.element.q3 else { return nil }
                let overlap = min(q3, topQ3) - max(q1, topQ1)
                guard overlap > 0 else { return nil }
                let fraction = overlap / topSpan
                return fraction > 0.5 ? entry.element.bin : nil
            }
            if !overlapping.isEmpty {
                return .unclear([topBin.bin] + overlapping)
            }
        }

        // Has at least one populated bin above the top?
        let hasAbove = populated.contains { $0.offset > topIdx }
        let hasBelow = populated.contains { $0.offset < topIdx }
        if hasAbove && hasBelow {
            return .observedPeak(topBin.bin)
        } else {
            return .bestObservedSoFar(topBin.bin)
        }
    }

    private static func computeLowerBound(bins: [BinResponse]) -> LowerBoundStatus {
        for b in bins where b.isPopulated {
            if let q1 = b.q1, q1 > 0 {
                return .likelyProductiveFrom(b.bin)
            }
        }
        return .noMeaningfulFloorYet
    }

    private static func computeUpperBound(
        bins: [BinResponse],
        observations: [MuscleObservation],
        best: BestRangeStatus
    ) -> UpperBoundStatus {
        let maxDose = observations.map(\.dose).max() ?? 0

        guard case let bestBin = bestBinFromStatus(best),
              let bestIdx = bins.firstIndex(where: { $0.bin == bestBin }),
              let bestSmoothed = bins[bestIdx].smoothed else {
            return .notYetTestedAbove(maxObservedDose: maxDose)
        }

        for higher in bins.suffix(from: bestIdx + 1) where higher.isPopulated {
            if let v = higher.smoothed,
               bestSmoothed > 0,
               (bestSmoothed - v) / bestSmoothed >= 0.3 {
                return .diminishingReturnsObserved(higher.bin)
            }
        }

        let anyHigherPopulated = bins.suffix(from: bestIdx + 1).contains(where: \.isPopulated)
        if !anyHigherPopulated {
            return .notYetTestedAbove(maxObservedDose: maxDose)
        }
        return .notYetTestedAbove(maxObservedDose: maxDose)
    }

    private static func bestBinFromStatus(_ status: BestRangeStatus) -> VolumeBin? {
        switch status {
        case .observedPeak(let bin), .bestObservedSoFar(let bin):
            return bin
        case .unclear(let bins):
            return bins.first
        case .insufficient:
            return nil
        }
    }

    // MARK: - Step 10: confidence

    private static func computeConfidence(
        bins: [BinResponse],
        best: BestRangeStatus,
        continuity: Double
    ) -> Confidence {
        let populated = bins.enumerated().filter { $0.element.isPopulated }
        guard populated.count >= 2 else { return .insufficient }

        guard let bestBin = bestBinFromStatus(best),
              let bestIdx = bins.firstIndex(where: { $0.bin == bestBin }) else {
            return .insufficient
        }
        let bestN = bins[bestIdx].observationCount
        let neighbourNs = [bestIdx - 1, bestIdx + 1]
            .filter { $0 >= 0 && $0 < bins.count }
            .map { bins[$0].observationCount }
        let bestNeighbourN = neighbourNs.max() ?? 0
        let hasBelow = populated.contains { $0.offset < bestIdx }
        let hasAbove = populated.contains { $0.offset > bestIdx }

        let overlapNeighbour = maxIQROverlapWithNeighbours(bins: bins, idx: bestIdx)

        // High
        if populated.count >= 4,
           bestN >= 5, bestNeighbourN >= 5,
           hasBelow, hasAbove,
           continuity >= 0.6,
           overlapNeighbour < 0.5 {
            return .high
        }
        // Medium
        if populated.count >= 3,
           bestN >= 3, bestNeighbourN >= 3,
           hasBelow, hasAbove,
           continuity >= 0.4,
           overlapNeighbour < 0.7 {
            return .medium
        }
        // Low
        if populated.count >= 2, bestN >= 3 {
            return .low
        }
        return .insufficient
    }

    private static func maxIQROverlapWithNeighbours(bins: [BinResponse], idx: Int) -> Double {
        guard let me = bins[safe: idx],
              let myQ1 = me.q1, let myQ3 = me.q3, myQ3 > myQ1 else { return 0 }
        let mySpan = myQ3 - myQ1
        var maxFraction = 0.0
        for nIdx in [idx - 1, idx + 1] {
            guard let n = bins[safe: nIdx], n.isPopulated,
                  let nQ1 = n.q1, let nQ3 = n.q3 else { continue }
            let overlap = min(myQ3, nQ3) - max(myQ1, nQ1)
            guard overlap > 0 else { continue }
            maxFraction = max(maxFraction, overlap / mySpan)
        }
        return maxFraction
    }

    private static func computeContinuity(exercisesPerWeek: [Date: Set<UUID>], calendar: Calendar) -> Double {
        let weeks = exercisesPerWeek.keys.sorted()
        guard weeks.count >= 2 else { return 1.0 }
        var ratios: [Double] = []
        for i in 1..<weeks.count {
            let current = exercisesPerWeek[weeks[i]] ?? []
            let previous = exercisesPerWeek[weeks[i - 1]] ?? []
            guard !current.isEmpty else { continue }
            let intersection = current.intersection(previous).count
            ratios.append(Double(intersection) / Double(current.count))
        }
        guard !ratios.isEmpty else { return 1.0 }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private static func computeTestedRange(observations: [MuscleObservation]) -> ClosedRange<Int>? {
        guard !observations.isEmpty else { return nil }
        let doses = observations.map { Int($0.dose.rounded()) }
        guard let lo = doses.min(), let hi = doses.max() else { return nil }
        return lo...hi
    }

    // MARK: - Sentence (user-facing copy)

    private static func buildSentence(
        muscle: String,
        observations: Int,
        best: BestRangeStatus,
        lower: LowerBoundStatus,
        upper: UpperBoundStatus,
        confidence: Confidence,
        bins: [BinResponse]
    ) -> String {
        let muscleCap = muscle.capitalized

        switch confidence {
        case .insufficient:
            return "Insufficient varied data for \(muscleCap). Train at distinctly different weekly volumes across several weeks to start building this curve."
        default:
            break
        }

        var parts: [String] = []
        switch best {
        case .observedPeak(let bin):
            parts.append("Based on \(observations) training weeks, \(muscleCap.lowercased()) progress was strongest when recent volume averaged \(bin.label) hard sets/week.")
        case .bestObservedSoFar(let bin):
            parts.append("Best observed range so far for \(muscleCap.lowercased()): \(bin.label) hard sets/week. This is your highest tested range, so an upper limit isn't established.")
        case .unclear(let bs):
            let labels = bs.map(\.label).joined(separator: " and ")
            parts.append("Top volume ranges for \(muscleCap.lowercased()) (\(labels)) gave similar progress and overlap in uncertainty.")
        case .insufficient:
            break
        }

        switch lower {
        case .likelyProductiveFrom(let bin):
            parts.append("Likely productive from \(bin.label) sets/week.")
        case .noMeaningfulFloorYet:
            break
        }

        switch upper {
        case .diminishingReturnsObserved(let bin):
            parts.append("Diminishing returns observed at \(bin.label) sets/week.")
        case .recoveryLimitObserved(let bin):
            parts.append("Recovery limit observed at \(bin.label) sets/week.")
        case .notYetTestedAbove(let maxDose):
            parts.append("You haven't tested above ~\(Int(maxDose.rounded())) sets often enough to know if more helps.")
        }

        parts.append("Confidence: \(confidence.rawValue).")
        return parts.joined(separator: " ")
    }

    // MARK: - Insufficient stub

    private enum InsufficientReason {
        case noTraining
        case notMatureEnough
    }

    private static func insufficient(muscle: String, reason: InsufficientReason) -> VolumeResponseAnalysis {
        let emptyBins = VolumeBin.allCases.map {
            BinResponse(bin: $0, observationCount: 0, median: nil, q1: nil, q3: nil, smoothed: nil)
        }
        let muscleCap = muscle.capitalized
        let sentence: String
        switch reason {
        case .noTraining:
            sentence = "No completed \(muscleCap.lowercased()) training in your history yet."
        case .notMatureEnough:
            sentence = "Insufficient varied data for \(muscleCap). Train at distinctly different weekly volumes across several weeks to start building this curve."
        }
        return VolumeResponseAnalysis(
            muscleGroup: muscle,
            bins: emptyBins,
            best: .insufficient,
            lower: .noMeaningfulFloorYet,
            upper: .notYetTestedAbove(maxObservedDose: 0),
            confidence: .insufficient,
            testedRange: nil,
            sentence: sentence
        )
    }

    // MARK: - Statistics helpers

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        if n == 0 { return 0 }
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    private static func quantile(_ values: [Double], p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let pos = p * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = Int(pos.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = pos - Double(lo)
        return sorted[lo] + frac * (sorted[hi] - sorted[lo])
    }

    private static func trimmedMean(_ values: [Double], trimFraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let trim = Int(Double(sorted.count) * trimFraction / 2.0)
        let core = Array(sorted.dropFirst(trim).dropLast(trim))
        guard !core.isEmpty else { return median(values) }
        return core.reduce(0, +) / Double(core.count)
    }

    private static func weightedMedian(_ pairs: [(value: Double, weight: Double)]) -> Double {
        guard !pairs.isEmpty else { return 0 }
        let sorted = pairs.sorted { $0.value < $1.value }
        let totalWeight = sorted.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return sorted[sorted.count / 2].value }
        let half = totalWeight / 2.0
        var cumulative = 0.0
        for p in sorted {
            cumulative += p.weight
            if cumulative >= half { return p.value }
        }
        return sorted.last!.value
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
