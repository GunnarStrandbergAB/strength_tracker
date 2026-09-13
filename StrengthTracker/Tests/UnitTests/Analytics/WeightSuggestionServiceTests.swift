import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("WeightSuggestionService")
@MainActor
struct WeightSuggestionServiceTests {

    private let service = WeightSuggestionService()
    private let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
    private let bodyWeight = 80.0

    /// Three sessions at 100 kg × 5 (e1RM 112.5) on days -3, -6, -9.
    private func history(rpe: [Double?] = [nil, nil, nil], kg: [Double] = [100, 100, 100], deloadLast: Bool = false) -> [Workout] {
        (0..<3).map { i in
            let day = Date().addingTimeInterval(-Double(i + 1) * 3 * 86_400)
            let sets = (1...3).map { AnalyticsTestHelpers.makeCompletedSet(order: $0, weight: kg[i], reps: 5, rpe: rpe[i]) }
            var w = AnalyticsTestHelpers.makeWorkout(
                exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: bench, sets: sets)],
                startedAt: day, completedAt: day.addingTimeInterval(3600)
            )
            if deloadLast && i == 0 { w.isDeload = true }
            return w
        }
    }

    private func trend() -> OverloadTrend {
        OverloadTrend(exerciseId: bench.id, exerciseName: bench.name, weeklyE1RMs: [], slopePerWeek: 5, trendStatus: .progressing, overloadIndex: 1)
    }

    private func verdict(_ kind: TrainingVerdict.Kind) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: 0, reasons: [], signals: [], action: "a", since: Date(), computedAt: Date(), isActiveDeload: false)
    }

    private func load(acwr: Double) -> TrainingLoad {
        TrainingLoad(acuteLoad: acwr * 100, chronicLoad: 100, acwr: acwr, loadZone: LoadZone.from(acwr: acwr))
    }

    private func suggest(trend: OverloadTrend? = nil, recovery: RecoveryStatus? = nil, load: TrainingLoad? = nil,
                         verdict: TrainingVerdict? = nil, workouts: [Workout]? = nil) -> WeightSuggestion? {
        service.suggest(exerciseId: bench.id, exerciseName: bench.name, targetReps: 5,
                        recentWorkouts: workouts ?? history(), overloadTrend: trend, recoveryStatus: recovery,
                        trainingLoad: load, isDeload: false, bodyWeightKg: bodyWeight, verdict: verdict)
    }

    @Test("Progress verdict extrapolates a progressing trend")
    func progressExtrapolates() {
        let s = suggest(trend: trend(), verdict: verdict(.progress))
        #expect(s?.modifiers.contains { $0.hasPrefix("Trend:") } == true)
    }

    @Test("Hold verdict skips trend extrapolation")
    func holdSkipsExtrapolation() {
        let s = suggest(trend: trend(), verdict: verdict(.hold))
        #expect(s != nil)
        #expect(s?.modifiers.contains { $0.hasPrefix("Trend:") } == false)
        #expect(s?.weight == suggest()?.weight)
    }

    @Test("Deload verdict skips extrapolation and takes 10% off")
    func deloadReduces() {
        let base = suggest()!
        let s = suggest(trend: trend(), verdict: verdict(.deload))!
        #expect(s.modifiers.contains("Coach: deload -10%"))
        #expect(s.modifiers.contains { $0.hasPrefix("Trend:") } == false)
        #expect(s.weight < base.weight)
        #expect(s.evidence.count == 3)
    }

    @Test("Stacked reductions are capped at 20%")
    func reductionsCapped() {
        let base = suggest()!
        let s = suggest(recovery: .fatigued, load: load(acwr: 1.7), verdict: verdict(.deload))!
        // Uncapped this would be 0.9 × 0.9 × 0.85 = 31% off; capped at 20%.
        #expect(s.modifiers.contains("Capped at -20%"))
        #expect(s.weight >= (base.weight * 0.8 / 2.5).rounded(.down) * 2.5)
        #expect(s.weight < base.weight)
    }

    @Test("Deload sessions are not evidence for the e1RM or effort creep")
    func deloadSessionsExcluded() {
        // Heavy history plus a light deload as the latest session: e1RM must come from the heavy sessions.
        let workouts = history(kg: [60, 100, 100], deloadLast: true)
        let s = suggest(workouts: workouts)
        #expect(s == nil) // Only two comparable sessions remain.

        // RPE climbing only because a deload session sits in the window → no creep.
        let creepy = history(rpe: [9, 8, 7], kg: [100, 100, 100], deloadLast: false)
        let creep = service.checkEffortCreep(exerciseId: bench.id, exerciseName: bench.name, recentWorkouts: creepy, bodyWeightKg: bodyWeight)
        #expect(creep != nil)
        #expect(creep?.message.contains("while e1RM stayed flat") == true)

        var withDeload = creepy
        withDeload[0].isDeload = true
        let none = service.checkEffortCreep(exerciseId: bench.id, exerciseName: bench.name, recentWorkouts: withDeload, bodyWeightKg: bodyWeight)
        #expect(none == nil)
    }
}

@Suite("Weight suggestion recording scenarios")
@MainActor
struct WeightSuggestionRecordingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func exercise(_ recording: WeightRecording? = .init(), id: UUID = UUID()) -> Exercise {
        Exercise(id: id, name: "Bulgarian Split Squat", primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes], category: .dumbbell, exerciseType: .weightedReps,
            instructions: nil, isCustom: false, isArchived: false, weightRecording: recording)
    }
    private func history(_ e: Exercise, weight: Double = 24, reps: Int = 8, days: [Int] = [1, 4, 7]) -> [Workout] {
        days.map { day in
            let date = now.addingTimeInterval(-Double(day) * 86400)
            return AnalyticsTestHelpers.makeWorkout(exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: e,
                sets: [AnalyticsTestHelpers.makeCompletedSet(weight: weight, reps: reps)])], startedAt: date, completedAt: date.addingTimeInterval(3600))
        }
    }
    private func suggest(_ e: Exercise, _ workouts: [Workout], reps: Int = 8, deload: Bool = false, trend: OverloadTrend? = nil) -> WeightSuggestion? {
        WeightSuggestionService().suggest(exerciseId: e.id, exerciseName: e.name, targetReps: reps,
            recentWorkouts: workouts, overloadTrend: trend, recoveryStatus: nil, trainingLoad: nil,
            isDeload: deload, bodyWeightKg: 80, recordingReference: e, now: now)
    }

    @Test("All eight recording scenarios preserve input weights and count volume separately")
    func scenarioMatrix() throws {
        let cases: [(WeightRecording, Double, Int, Double, Int)] = [
            (.init(), 24, 8, 384, 8),
            (.init(weightEntry: .combined), 48, 8, 384, 8),
            (.init(repetitions: .perSide), 24, 8, 768, 8),
            (.init(weightEntry: .combined, repetitions: .perSide), 48, 8, 768, 8),
            (.init(equipment: .single, repetitions: .perSide), 24, 8, 384, 8),
            (.init(weightEntry: .combined, repetitions: .oneSide), 48, 8, 384, 8),
            (.init(equipment: .single, repetitions: .totalAlternating), 24, 16, 384, 8),
            (.init(weightEntry: .combined, repetitions: .totalAlternating), 48, 16, 768, 8)
        ]
        for (recording, weight, reps, volume, strengthReps) in cases {
            let e = exercise(recording), rows = history(e, weight: weight, reps: reps)
            let hint = try #require(suggest(e, rows, reps: reps))
            #expect(hint.weight == weight)
            #expect(rows[0].totalVolume(bodyWeightKg: 80) == volume)
            #expect(abs(hint.evidence[0].estimatedStrength - AnalyticsCalculations.calculateOneRM(weight: weight, reps: strengthReps)) < 0.000001)
        }
    }

    @Test("Formula round trips never invent an increase, including the screenshot's 110 x 8")
    func formulaRoundTrips() throws {
        for weight in [24.0, 48, 110, 0.25, 999.99] {
            for reps in 1...15 {
                let estimate = AnalyticsCalculations.calculateOneRM(weight: weight, reps: reps)
                let result = try #require(AnalyticsCalculations.weightAtReps(e1rm: estimate, reps: reps))
                #expect(abs(result - weight) < 0.000001)
            }
        }
        let e = exercise(.init(weightEntry: .combined, repetitions: .perSide))
        #expect(suggest(e, history(e, weight: 110))?.weight == 110)
        #expect(suggest(e, history(e, weight: 48))?.weight == 48)
        #expect(AnalyticsCalculations.weightAtReps(e1rm: .infinity, reps: 8) == nil)
    }

    @Test("Each and combined histories convert once, retain precision and show their source")
    func conversionsAndEvidence() throws {
        let each = exercise(.init(repetitions: .perSide))
        var total = each; total.weightRecording?.weightEntry = .combined
        let eachRows = history(each, weight: 24.25)
        let totalRows = history(total, weight: 48.5)
        let a = try #require(suggest(total, eachRows))
        let b = try #require(suggest(each, totalRows))
        #expect(a.weight == 48.5 && b.weight == 24.25)
        #expect(a.evidence.first?.originalWeight == 24.25)
        #expect(a.evidence.first?.convertedWeight == 48.5)
        #expect(a.evidence.first?.description(unit: .kg, reference: total) == "24.25 Kg each × 8/side → 48.5 Kg total × 8/side")
        #expect(a.displayText(unit: .kg) == "Suggested: ≈48.5 Kg total × 8/side")
        #expect(a.displayText(unit: .lbs).contains("106.92 lbs total"))
        #expect(eachRows[0].exercises[0].sets[0].weight == 24.25)
        #expect(totalRows[0].exercises[0].sets[0].weight == 48.5)
    }

    @Test("Only the latest three comparable sessions contribute; one high observation cannot dominate")
    func medianEvidence() throws {
        let e = exercise()
        var rows = history(e)
        rows[0].exercises[0].sets[0].weight = 240
        rows += history(e, weight: 999, days: [15])
        let result = try #require(suggest(e, rows))
        #expect(result.weight == 24)
        #expect(result.evidence.map(\.workoutId) == Array(rows.prefix(3)).map(\.id))
        #expect(suggest(e, Array(rows.prefix(2))) == nil)
        #expect(suggest(e, [rows[1], rows[1], rows[1]]) == nil)
        #expect(suggest(e, history(e, days: [91, 94, 97])) == nil)
        #expect(suggest(e, history(e, days: [-3, -2, -1])) == nil)
        #expect(suggest(e, rows, deload: true) == nil)
    }

    @Test("Unknown, incompatible and changed bodyweight conventions never become evidence")
    func incompatibleEvidence() {
        let e = exercise()
        #expect(suggest(exercise(nil, id: e.id), history(e)) == nil)
        #expect(suggest(e, history(exercise(nil, id: e.id))) == nil)
        #expect(suggest(e, history(exercise(.init(equipment: .single), id: e.id))) == nil)
        #expect(suggest(e, history(exercise(.init(repetitions: .totalAlternating), id: e.id), reps: 16)) == nil)
        var bw = e; bw.category = .bodyweight; bw.exerciseType = .bodyweightReps; bw.bodyweightFactor = 0.8
        var old = bw; old.bodyweightFactor = 0.64
        #expect(suggest(bw, history(old)) == nil)
        #expect(suggest(bw, history(bw, weight: 24))?.weight == 24)
        #expect(suggest(bw, history(bw, weight: 0)) == nil)
    }

    @Test("Unsupported and ambiguous rep counts are suppressed instead of extrapolated")
    func unsupportedReps() {
        let e = exercise(), alternating = exercise(.init(repetitions: .totalAlternating))
        for reps in [0, -1, 16, 37, 99] { #expect(suggest(e, history(e), reps: reps) == nil) }
        for reps in [1, 15, 17, 32] { #expect(suggest(alternating, history(alternating, reps: 16), reps: reps) == nil) }
        #expect(suggest(e, history(e, reps: 16)) == nil)
        #expect(suggest(alternating, history(alternating, reps: 17), reps: 16) == nil)
    }

    @Test("Warmups, incomplete sets, drop sets and deloads cannot provide working-weight evidence")
    func exclusions() {
        let e = exercise()
        for mode in 0...3 {
            var rows = history(e)
            for i in rows.indices {
                switch mode {
                case 0: rows[i].exercises[0].sets[0].setType = .warmup
                case 1: rows[i].exercises[0].sets[0].isCompleted = false
                case 2: rows[i].exercises[0].sets[0].applyDropSets([.init(weight: 24, reps: 8), .init(weight: 20, reps: 8)])
                default: rows[i].isDeload = true
                }
            }
            #expect(suggest(e, rows) == nil)
        }
    }

    @Test("Separate side rows use the lower estimate")
    func separateSides() {
        let e = exercise(.init(weightEntry: .combined, repetitions: .oneSide))
        var rows = history(e, weight: 48)
        for i in rows.indices {
            rows[i].exercises[0].sets.append(AnalyticsTestHelpers.makeCompletedSet(order: 2, weight: 60, reps: 8))
        }
        #expect(suggest(e, rows)?.weight == 48)
    }

    @Test("Converted histories never reuse an unconverted progression slope")
    func trendBasis() throws {
        let each = exercise(); var total = each; total.weightRecording?.weightEntry = .combined
        let trend = OverloadTrend(exerciseId: each.id, exerciseName: each.name, weeklyE1RMs: [], slopePerWeek: 20, trendStatus: .progressing, overloadIndex: 1)
        let hint = try #require(suggest(total, history(each), trend: trend))
        #expect(hint.weight == 48)
        #expect(hint.modifiers.isEmpty)
    }

    @Test("Alternating strength agrees across analytics, charts and records, while recorded reps and volume stay intact")
    func sharedStrength() throws {
        let e = exercise(.init(equipment: .single, repetitions: .totalAlternating))
        let rows = history(e, reps: 16)
        let expected = AnalyticsCalculations.calculateOneRM(weight: 24, reps: 8)
        #expect(AnalyticsCalculations.buildBestE1RMMap(from: rows, bodyWeightKg: 80, asOf: now)[e.id] == expected)
        let chart = try #require(ExerciseHistoryCalculator.sessions(exerciseId: e.id, workouts: rows, bodyWeightKg: 80, now: now).first)
        #expect(chart.value(for: .strength) == expected)
        #expect(chart.recordedReps == 16)
        #expect(chart.recordedVolume == 384)
        let records = PersonalRecordService.candidateRecords(exerciseId: e.id, exercise: e, set: rows[0].exercises[0].sets[0], bodyWeightKg: 80)
        #expect(records.first { $0.recordType == .estimatedOneRepMax }?.value == expected)
        #expect(records.first { $0.recordType == .maxVolume }?.value == 384)
        let weeks = history(e, reps: 16, days: [1, 8, 15, 22, 29])
        let trend = try #require(OverloadTrackingService.computeOverloadTrends(workouts: weeks, bodyWeightKg: 80, now: now).first)
        #expect(trend.weeklyE1RMs.allSatisfy { $0.e1rm == expected })
    }
}

@Suite("Alternating baseline compatibility")
@MainActor
struct AlternatingBaselineTests {
    @Test("Old alternating plans do not treat corrected strength estimates as regression")
    func oldPlans() throws {
        var e = AnalyticsTestHelpers.makeExercise()
        e.category = .dumbbell; e.weightRecording = .init(repetitions: .totalAlternating)
        let plan = PlanExercise(exerciseId: e.id, exerciseName: e.name, primaryMuscleGroup: e.primaryMuscleGroup,
            category: e.category, estimated1RM: 36, oneRMSource: .estimated, current1RM: 36,
            isCompound: false, order: 0, weightRecording: e.weightRecording)
        #expect(plan.acceptsBodyweightBasis(of: e))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        object.removeValue(forKey: "strengthModelVersion")
        let legacy = try JSONDecoder().decode(PlanExercise.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!legacy.acceptsBodyweightBasis(of: e))
        e.weightRecording?.repetitions = .perSide
        #expect(legacy.acceptsBodyweightBasis(of: e))
    }
}
