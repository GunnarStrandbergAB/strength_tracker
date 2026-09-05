import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("CoachingInsightService")
@MainActor
struct CoachingInsightServiceTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private let service = CoachingInsightService(searchService: VectorSearchService())

    private func workout(on day: Date, kg: Double = 80, pr: Bool = false, isDeload: Bool = false) -> Workout {
        let sets = (1...3).map { AnalyticsTestHelpers.makeCompletedSet(order: $0, weight: kg, reps: 8, isPersonalRecord: pr && $0 == 1) }
        var w = AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise(sets: sets)],
            startedAt: day, completedAt: day.addingTimeInterval(3600)
        )
        w.isDeload = isDeload
        return w
    }

    private func verdict(_ kind: TrainingVerdict.Kind, active: Bool = false) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: 0.6, reasons: ["r"], signals: [], action: "Verdict action",
                        since: Date(), computedAt: Date(), isActiveDeload: active)
    }

    private func load(acwr: Double) -> TrainingLoad {
        TrainingLoad(acuteLoad: acwr * 100, chronicLoad: 100, acwr: acwr, loadZone: LoadZone.from(acwr: acwr))
    }

    /// 20 completed workouts so the 19-workout load bullets are unlocked.
    private func longHistory() -> [Workout] {
        (1...20).map { workout(on: Date().addingTimeInterval(-Double($0) * 2 * 86_400)) }
    }

    private func debrief(verdict: TrainingVerdict?, load: TrainingLoad?) async -> PostWorkoutDebrief {
        let all = longHistory()
        return await service.generatePostWorkoutDebrief(
            workout: all[0], allWorkouts: all, overloadTrends: [], qualityScore: nil, recoveryPatterns: [],
            trainingLoad: load, optimalVolumes: [], currentVector: nil, allVectors: [], bodyWeightKg: 80, verdict: verdict
        )
    }

    @Test("With a verdict the debrief carries it and emits no load bullet of its own")
    func debriefCarriesVerdict() async {
        let d = await debrief(verdict: verdict(.deload), load: load(acwr: 0.5))
        #expect(d.verdict?.kind == .deload)
        #expect(!d.bullets.contains { $0.source == .acwr })
        #expect(!d.bullets.map(\.title).contains("Room to Push"))
        #expect(!d.bullets.map(\.title).contains("Low Training Load"))

        let p = await debrief(verdict: verdict(.progress), load: load(acwr: 1.7))
        #expect(p.verdict?.kind == .progress)
        #expect(!p.bullets.contains { $0.source == .acwr })
    }

    @Test("Without a verdict the load bullet is descriptive, never imperative")
    func debriefDescriptiveWithoutVerdict() async {
        let d = await debrief(verdict: nil, load: load(acwr: 1.7))
        let bullet = d.bullets.first { $0.source == .acwr }
        #expect(bullet?.title == "Training Load Very high")
        #expect(bullet?.detail.lowercased().contains("reduce") == false)
        #expect(d.verdict == nil)
    }

    @Test("Digest compares the last complete Monday-start week with the prior one")
    func digestUsesCompleteWeeks() {
        // now = Wed 2026-09-09. Last week: Aug 31–Sep 6. Prior: Aug 24–30.
        let now = date(2026, 9, 9)
        let workouts = [
            workout(on: date(2026, 9, 8), kg: 200),                 // this week (ignored for delta)
            workout(on: date(2026, 9, 1), kg: 100, pr: true),        // last week
            workout(on: date(2026, 9, 3), kg: 100),                  // last week
            workout(on: date(2026, 9, 6, 23), kg: 100),              // Sunday late: still last week
            workout(on: date(2026, 8, 25), kg: 80),                  // prior week
            workout(on: date(2026, 8, 27), kg: 80),                  // prior week
        ]
        let digest = service.generateWeeklyDigest(workouts: workouts, overloadTrends: [], bodyWeightKg: 80, now: now, calendar: calendar)
        #expect(digest?.workoutsLastWeek == 3)
        #expect(digest?.workoutsThisWeek == 1)
        #expect(digest?.prsLastWeek == 1)
        #expect(digest?.prsThisWeek == 0)
        #expect(digest?.weekStart == date(2026, 8, 31, 0))
        // Last week volume 3×(3×100×8)=7200 vs prior 2×(3×80×8)=3840 → +87.5%
        #expect(abs((digest?.volumeDeltaPercent ?? 0) - 87.5) < 0.1)
        #expect(digest?.topInsight.detail.contains("vs prior week") == true)
    }

    @Test("Digest top insight follows a deload verdict over a progressing trend")
    func digestFollowsVerdict() {
        let now = date(2026, 9, 9)
        let workouts = (0..<6).map { workout(on: date(2026, 9, 1).addingTimeInterval(-Double($0) * 2 * 86_400)) }
        let trend = OverloadTrend(exerciseId: UUID(), exerciseName: "Bench Press", weeklyE1RMs: [], slopePerWeek: 2.5, trendStatus: .progressing, overloadIndex: 1)
        let digest = service.generateWeeklyDigest(workouts: workouts, overloadTrends: [trend], bodyWeightKg: 80, verdict: verdict(.deload), now: now, calendar: calendar)
        #expect(digest?.topInsight.title == "Deload Recommended")

        let clear = service.generateWeeklyDigest(workouts: workouts, overloadTrends: [trend], bodyWeightKg: 80, verdict: verdict(.progress), now: now, calendar: calendar)
        #expect(clear?.topInsight.title == "Bench Press Gaining")
        #expect(clear?.topInsight.detail == "+2.5 kg/wk over recent weeks")
    }
}
