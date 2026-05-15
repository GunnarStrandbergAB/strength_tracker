import Testing
import Foundation
@testable import StrengthTrackerShared

@MainActor
@Suite("VolumeResponseService")
struct VolumeResponseServiceTests {

    // MARK: - Helpers

    /// Fixed reference date for deterministic week arithmetic. Picked far from week boundaries.
    private static let referenceNow: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 7
        components.day = 16 // Wednesday
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private static let mondayCalendar = Calendar.mondayStart

    private static func weekStart(weeksAgo: Int, now: Date = referenceNow) -> Date {
        let thisWeekStart = mondayCalendar.dateInterval(of: .weekOfYear, for: now)!.start
        return mondayCalendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart)!
    }

    /// Build a completed workout placed in a specific past week.
    private func makeWorkout(
        weeksAgo: Int,
        exerciseId: UUID,
        exerciseName: String,
        primary: MuscleGroup,
        secondary: [MuscleGroup] = [],
        hardSets: Int,
        weight: Double = 80,
        reps: Int = 8,
        isDeload: Bool = false,
        now: Date = referenceNow
    ) -> Workout {
        let date = Self.weekStart(weeksAgo: weeksAgo, now: now).addingTimeInterval(60 * 60 * 24) // Tuesday-ish
        let exercise = AnalyticsTestHelpers.makeExercise(
            id: exerciseId,
            name: exerciseName,
            primaryMuscleGroup: primary,
            secondaryMuscleGroups: secondary
        )
        let sets = (1...hardSets).map { order in
            AnalyticsTestHelpers.makeCompletedSet(order: order, weight: weight, reps: reps)
        }
        let we = AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, order: 1, sets: sets)
        return Workout(
            id: UUID(),
            name: "Fixture",
            startedAt: date,
            completedAt: date.addingTimeInterval(3600),
            notes: nil,
            templateId: nil,
            healthKitWorkoutId: nil,
            isDeload: isDeload,
            plannedSessionId: nil,
            plannedPlanId: nil,
            exercises: [we]
        )
    }

    /// Build an OverloadTrend whose weeklyE1RMs are explicitly seeded.
    private func makeOverloadTrend(
        exerciseId: UUID,
        exerciseName: String,
        e1rms: [(weeksAgo: Int, e1rm: Double)],
        slope: Double = 1.0
    ) -> OverloadTrend {
        let weekly = e1rms.map { entry in
            WeeklyE1RM(weekStart: Self.weekStart(weeksAgo: entry.weeksAgo), e1rm: entry.e1rm)
        }
        return OverloadTrend(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            weeklyE1RMs: weekly,
            slopePerWeek: slope,
            trendStatus: .progressing,
            overloadIndex: 1.0
        )
    }

    // MARK: - Tests

    @Test("Effective-hard-sets: primary 1.0, secondaries split 0.5 across them")
    func effectiveHardSetsWeighting() {
        let exId = UUID()
        // One workout (1 week ago, NOT mature: only one week of data) — we only test the dose attribution
        // via a longer multi-week history that crosses the maturity gate.
        var workouts: [Workout] = []
        // 10 weeks of bench at 4 sets each: chest gets 4, triceps gets 0.5 * 4 / 2 = 1, shoulders gets 1.
        for w in 4...13 {
            workouts.append(makeWorkout(
                weeksAgo: w,
                exerciseId: exId,
                exerciseName: "Bench",
                primary: .chest,
                secondary: [.triceps, .shoulders],
                hardSets: 4
            ))
        }
        // Need an OverloadTrend with enough e1RM observations spanning the relevant windows so the service
        // emits something for chest. Add e1RM in every one of those 10 weeks at a stable value (response ~ 0).
        let trend = makeOverloadTrend(
            exerciseId: exId,
            exerciseName: "Bench",
            e1rms: (4...13).map { ($0, 100.0) }
        )

        let analyses = VolumeResponseService.computeAnalyses(
            workouts: workouts,
            overloadTrends: [trend],
            now: Self.referenceNow
        )

        // Chest tested range hits dose ≈ 4 (consistent volume). Triceps and shoulders each got 1 effective set per week → bin "0-4".
        let chest = analyses.first { $0.muscleGroup == "chest" }
        let triceps = analyses.first { $0.muscleGroup == "triceps" }

        #expect(chest != nil, "Chest analysis must exist")
        #expect(triceps != nil, "Triceps analysis must exist via secondary contribution")

        // Chest is binned in "0-4" (dose = 4 in steady state); triceps in "0-4" too. Confirm via testedRange.
        if let chest {
            #expect(chest.testedRange?.contains(4) == true)
        }
        if let triceps {
            #expect(triceps.testedRange?.contains(1) == true || triceps.testedRange?.contains(0) == true,
                    "Triceps secondary contribution ≈ 1 effective set/wk")
        }
    }

    @Test("Maturity gate: weeks within last 3 weeks of `now` don't enter the analysis")
    func maturityGateExcludesImmatureWeeks() {
        let exId = UUID()
        var workouts: [Workout] = []
        // 10 weeks of training, but spanning weeksAgo 0..9 — so the last 3 weeks (0, 1, 2) are immature.
        for w in 0...9 {
            workouts.append(makeWorkout(
                weeksAgo: w,
                exerciseId: exId,
                exerciseName: "Bench",
                primary: .chest,
                hardSets: 10
            ))
        }
        let trend = makeOverloadTrend(
            exerciseId: exId,
            exerciseName: "Bench",
            e1rms: (0...9).map { ($0, 100.0) }
        )

        let analyses = VolumeResponseService.computeAnalyses(
            workouts: workouts,
            overloadTrends: [trend],
            now: Self.referenceNow
        )

        // The most recent mature week is 3 weeks ago. Weeks 0/1/2 cannot have a future window (no W+3 data).
        // So total observations should be capped at the count of mature weeks (≤ 7), not 10.
        guard let chest = analyses.first(where: { $0.muscleGroup == "chest" }) else {
            Issue.record("Expected chest analysis")
            return
        }
        let totalObs = chest.bins.reduce(0) { $0 + $1.observationCount }
        #expect(totalObs <= 7, "Immature weeks must not contribute (got \(totalObs))")
    }

    @Test("Within-exercise normalization: adding a new lower-absolute-weight exercise does not drop the muscle response")
    func withinExerciseNormalizationPreventsFalseDrop() {
        let bench = UUID()
        let fly = UUID()
        // 14 weeks of bench at steady e1RM = 100 (response = 0).
        var workouts: [Workout] = []
        for w in 1...14 {
            workouts.append(makeWorkout(
                weeksAgo: w, exerciseId: bench, exerciseName: "Bench", primary: .chest, hardSets: 8
            ))
        }
        // Starting at week 7, add fly (much lower absolute weight) at steady e1RM = 25 (also response = 0).
        for w in 1...7 {
            workouts.append(makeWorkout(
                weeksAgo: w, exerciseId: fly, exerciseName: "Fly", primary: .chest, hardSets: 4,
                weight: 25
            ))
        }
        let benchTrend = makeOverloadTrend(
            exerciseId: bench, exerciseName: "Bench",
            e1rms: (1...14).map { ($0, 100.0) }
        )
        let flyTrend = makeOverloadTrend(
            exerciseId: fly, exerciseName: "Fly",
            e1rms: (1...7).map { ($0, 25.0) }
        )

        let analyses = VolumeResponseService.computeAnalyses(
            workouts: workouts,
            overloadTrends: [benchTrend, flyTrend],
            now: Self.referenceNow
        )
        guard let chest = analyses.first(where: { $0.muscleGroup == "chest" }) else {
            Issue.record("Expected chest analysis")
            return
        }

        // Per-exercise response is (future - baseline) / baseline ≈ 0 for both exercises.
        // The muscle-level aggregation must therefore also be ≈ 0, even though absolute e1RM differs by 4×.
        let nonZeroBins = chest.bins.compactMap(\.smoothed).filter { abs($0) > 0.05 }
        #expect(nonZeroBins.isEmpty, "Adding a low-absolute exercise must not produce phantom responses (got \(nonZeroBins))")
    }

    @Test("Binning boundaries: dose 4 → 0-4, dose 5 → 5-8, dose 21 → 21+")
    func binningBoundaries() {
        #expect(VolumeBin.bin(for: 0) == .zeroToFour)
        #expect(VolumeBin.bin(for: 4.0) == .zeroToFour)
        #expect(VolumeBin.bin(for: 4.99) == .zeroToFour)
        #expect(VolumeBin.bin(for: 5.0) == .fiveToEight)
        #expect(VolumeBin.bin(for: 8.99) == .fiveToEight)
        #expect(VolumeBin.bin(for: 9.0) == .nineToTwelve)
        #expect(VolumeBin.bin(for: 13.0) == .thirteenToSixteen)
        #expect(VolumeBin.bin(for: 17.0) == .seventeenToTwenty)
        #expect(VolumeBin.bin(for: 21.0) == .twentyOnePlus)
        #expect(VolumeBin.bin(for: 99) == .twentyOnePlus)
    }

    @Test("Best-range status: peak in middle when responses are highest at a middle bin")
    func bestRangeStatusObservedPeak() {
        // Single exercise spans 29 weeks. Set count varies to produce three distinct dose bins.
        // e1RM is flat during low/high volume periods and *rises* during the middle period —
        // so the middle bin's response is the peak.
        // Note: lower weeksAgo = more recent week. e1RM increases as we move toward more recent weeks.
        let exId = UUID()
        var workouts: [Workout] = []
        var e1rms: [(weeksAgo: Int, e1rm: Double)] = []

        // Oldest: 4 sets/wk, flat e1RM=100. (weeksAgo 23..29 = 7 weeks)
        for w in 23...29 {
            workouts.append(makeWorkout(weeksAgo: w, exerciseId: exId, exerciseName: "Bench",
                                        primary: .chest, hardSets: 4, weight: 80, reps: 6))
            e1rms.append((w, 100.0))
        }
        // Middle: 10 sets/wk, e1RM rising from 100 (at weeksAgo=22) to 109 (at weeksAgo=13). 10 weeks.
        for (idx, w) in (13...22).reversed().enumerated() {
            // idx=0 → w=22 (oldest of period) → 100; idx=9 → w=13 (newest of period) → 109
            workouts.append(makeWorkout(weeksAgo: w, exerciseId: exId, exerciseName: "Bench",
                                        primary: .chest, hardSets: 10, weight: 80, reps: 6))
            e1rms.append((w, 100.0 + Double(idx)))
        }
        // Newest: 18 sets/wk, flat e1RM=110. (weeksAgo 1..12 = 12 weeks; includes immature 1..3 for future windows)
        for w in 1...12 {
            workouts.append(makeWorkout(weeksAgo: w, exerciseId: exId, exerciseName: "Bench",
                                        primary: .chest, hardSets: 18, weight: 80, reps: 6))
            e1rms.append((w, 110.0))
        }

        let trend = makeOverloadTrend(exerciseId: exId, exerciseName: "Bench", e1rms: e1rms)
        let analyses = VolumeResponseService.computeAnalyses(
            workouts: workouts,
            overloadTrends: [trend],
            now: Self.referenceNow
        )
        guard let chest = analyses.first(where: { $0.muscleGroup == "chest" }) else {
            Issue.record("Expected chest analysis")
            return
        }

        // Diagnostic: which bins have data and what are their smoothed values?
        let report = chest.bins.compactMap { b -> String? in
            guard b.isPopulated, let m = b.median else { return nil }
            return "\(b.bin.label): n=\(b.observationCount) median=\(String(format: "%.3f", m))"
        }.joined(separator: ", ")

        switch chest.best {
        case .observedPeak(let bin):
            #expect(bin == .nineToTwelve,
                    "Expected peak at 9-12 (the rising-e1RM period), got \(bin). Bins: \(report)")
        case .bestObservedSoFar(let bin):
            // Edge effects may pick a different bin if smoothing prefers an edge; require it's at least 9-12.
            #expect(bin == .nineToTwelve,
                    "Got bestObservedSoFar(\(bin)) — expected 9-12. Bins: \(report)")
        case .unclear(let bins):
            #expect(bins.contains(.nineToTwelve),
                    "Got unclear(\(bins)) — at least 9-12 should be among contenders. Bins: \(report)")
        case .insufficient:
            Issue.record("Insufficient — fixture should produce enough bins. Bins: \(report)")
        }
    }

    @Test("Deload weeks are excluded from dose accumulation")
    func deloadExclusion() {
        let exId = UUID()
        var workouts: [Workout] = []
        // 10 normal weeks at 10 sets, plus a deload at week 6 with 4 sets.
        for w in 1...10 {
            let isDeload = (w == 6)
            workouts.append(makeWorkout(
                weeksAgo: w,
                exerciseId: exId,
                exerciseName: "Bench",
                primary: .chest,
                hardSets: isDeload ? 4 : 10,
                isDeload: isDeload
            ))
        }
        let trend = makeOverloadTrend(
            exerciseId: exId,
            exerciseName: "Bench",
            e1rms: (1...10).map { ($0, 100.0) }
        )
        let analyses = VolumeResponseService.computeAnalyses(
            workouts: workouts,
            overloadTrends: [trend],
            now: Self.referenceNow
        )
        guard let chest = analyses.first(where: { $0.muscleGroup == "chest" }) else {
            Issue.record("Expected chest analysis")
            return
        }

        // If the deload had been counted, the dose for adjacent weeks would average to (10+4+10)/3 ≈ 8 → bin "5-8".
        // Excluded, the 3-week trailing dose stays at 10 → bin "9-12". Confirm at least one obs lands in "9-12".
        let nineToTwelve = chest.bins.first { $0.bin == .nineToTwelve }
        #expect((nineToTwelve?.observationCount ?? 0) > 0, "Expected dose=10 observations to land in 9-12 bin")
    }

    @Test("Single populated bin → confidence .insufficient, status .insufficient")
    func insufficientWhenOnlyOneBin() {
        let exId = UUID()
        var workouts: [Workout] = []
        for w in 1...14 {
            workouts.append(makeWorkout(
                weeksAgo: w, exerciseId: exId, exerciseName: "Bench", primary: .chest, hardSets: 10
            ))
        }
        let trend = makeOverloadTrend(
            exerciseId: exId, exerciseName: "Bench",
            e1rms: (1...14).map { ($0, 100.0 + Double($0)) }
        )
        let analyses = VolumeResponseService.computeAnalyses(
            workouts: workouts,
            overloadTrends: [trend],
            now: Self.referenceNow
        )
        guard let chest = analyses.first(where: { $0.muscleGroup == "chest" }) else {
            Issue.record("Expected chest analysis")
            return
        }
        #expect(chest.confidence == .insufficient)
        if case .insufficient = chest.best {} else {
            Issue.record("Expected BestRangeStatus.insufficient")
        }
    }

    @Test("Triangular smoothing skips bins with an unpopulated neighbour")
    func smoothingSkipsUnpopulatedNeighbours() {
        // Use BinResponse directly via the public API to verify smoothing is conservative.
        // We can't call the smoothing helper directly (private), so we exercise it via end-to-end with
        // a fixture that produces an unpopulated bin between two populated ones.
        let exA = UUID(), exC = UUID()
        var workouts: [Workout] = []
        // exA at hardSets=4 (bin 0-4) for weeks 4..10
        for w in 4...10 {
            workouts.append(makeWorkout(weeksAgo: w, exerciseId: exA, exerciseName: "A", primary: .chest, hardSets: 4))
        }
        // exC at hardSets=18 (bin 17-20) for weeks 11..17 — skips bins 5-16
        for w in 11...17 {
            workouts.append(makeWorkout(weeksAgo: w, exerciseId: exC, exerciseName: "C", primary: .chest, hardSets: 18))
        }
        let trends = [
            makeOverloadTrend(exerciseId: exA, exerciseName: "A", e1rms: (4...10).map { ($0, 100.0) }),
            makeOverloadTrend(exerciseId: exC, exerciseName: "C", e1rms: (11...17).map { ($0, 100.0) })
        ]
        let analyses = VolumeResponseService.computeAnalyses(
            workouts: workouts,
            overloadTrends: trends,
            now: Self.referenceNow
        )
        guard let chest = analyses.first(where: { $0.muscleGroup == "chest" }) else {
            Issue.record("Expected chest analysis")
            return
        }
        // Bin 0-4 has neighbour 5-8 unpopulated → smoothed must equal raw median (no blending with unknown).
        let lowBin = chest.bins.first { $0.bin == .zeroToFour }
        if let raw = lowBin?.median, let smoothed = lowBin?.smoothed {
            #expect(abs(raw - smoothed) < 1e-9, "Edge bin with unpopulated neighbour must not be smoothed (got raw=\(raw), smoothed=\(smoothed))")
        }
    }
}
