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
        #expect(s.explanation.contains("adjusted from"))
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
        #expect(s?.weight == suggest()?.weight)

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
