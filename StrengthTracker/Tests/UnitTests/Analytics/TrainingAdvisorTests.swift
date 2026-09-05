import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("TrainingAdvisor")
@MainActor
struct TrainingAdvisorTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func workout(on day: Date, isDeload: Bool = false) -> Workout {
        var w = AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
            startedAt: day, completedAt: day.addingTimeInterval(3600)
        )
        w.isDeload = isDeload
        return w
    }

    private func load(acwr: Double) -> TrainingLoad {
        TrainingLoad(acuteLoad: acwr * 100, chronicLoad: 100, acwr: acwr, loadZone: LoadZone.from(acwr: acwr))
    }

    private func recommendation(urgency: Double, triggers: [DeloadSignal]) -> DeloadRecommendation {
        DeloadRecommendation(urgencyScore: urgency, triggers: triggers, weeksSinceLastDeload: 8, suggestedAction: "Take a lighter week")
    }

    private func trend(_ name: String, _ status: TrendStatus) -> OverloadTrend {
        OverloadTrend(exerciseId: UUID(), exerciseName: name, weeklyE1RMs: [], slopePerWeek: 0, trendStatus: status, overloadIndex: 0)
    }

    private func pattern(_ group: String, status: RecoveryStatus, lastTrained: Date) -> RecoveryPattern {
        RecoveryPattern(muscleGroup: group, averageRecoveryHours: 48, optimalRestDays: 2,
                        lastTrainedDate: lastTrained, readyToTrainDate: nil, recoveryStatus: status)
    }

    private func advisor() -> TrainingAdvisor {
        TrainingAdvisor(store: InMemoryTrainingVerdictStore(), calendar: calendar)
    }

    /// Recent, ordinary history ending yesterday.
    private func recentHistory(now: Date) -> [Workout] {
        (1...6).map { workout(on: calendar.date(byAdding: .day, value: -$0 * 2, to: now)!) }
    }

    // MARK: Precedence

    @Test("No signals → progress")
    func clearIsProgress() {
        let now = date(2026, 9, 5)
        let v = advisor().evaluate(.init(workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.0), now: now))
        #expect(v.kind == .progress)
        #expect(v.headline == "Clear to Progress")
        #expect(!v.discouragesLoadIncrease)
    }

    @Test("A recent deload session → hold, flagged as active deload, even with strong signals")
    func activeDeloadWins() {
        let now = date(2026, 9, 5)
        var history = recentHistory(now: now)
        history.append(workout(on: date(2026, 9, 4), isDeload: true))
        let v = advisor().evaluate(.init(
            workouts: history, trainingLoad: load(acwr: 1.8),
            deloadRecommendation: recommendation(urgency: 0.9, triggers: [.highACWR, .performanceDecline]), now: now
        ))
        #expect(v.kind == .hold)
        #expect(v.isActiveDeload)
        #expect(v.headline == "Deload In Progress")
    }

    @Test("A deload session older than a week is no longer active")
    func staleDeloadNotActive() {
        let now = date(2026, 9, 20)
        let history = [workout(on: date(2026, 9, 1), isDeload: true), workout(on: date(2026, 9, 18))]
        let v = advisor().evaluate(.init(workouts: history, trainingLoad: load(acwr: 1.0), now: now))
        #expect(!v.isActiveDeload)
    }

    @Test("Ten days without training → hold to ease back in")
    func layoffIsHold() {
        let now = date(2026, 9, 15)
        let v = advisor().evaluate(.init(workouts: [workout(on: date(2026, 9, 1))], trainingLoad: load(acwr: 0.3), now: now))
        #expect(v.kind == .hold)
        #expect(v.reasons.first?.contains("days since") == true)
    }

    @Test("ACWR in the danger zone → deload")
    func dangerZoneIsDeload() {
        let now = date(2026, 9, 5)
        let v = advisor().evaluate(.init(workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.6), now: now))
        #expect(v.kind == .deload)
    }

    @Test("Two primary triggers → deload; one moderate trigger → hold")
    func triggerCountsDecide() {
        let now = date(2026, 9, 5)
        let two = advisor().evaluate(.init(
            workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.0),
            deloadRecommendation: recommendation(urgency: 0.4, triggers: [.effortCreep, .performanceDecline]), now: now
        ))
        #expect(two.kind == .deload)

        let one = advisor().evaluate(.init(
            workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.0),
            deloadRecommendation: recommendation(urgency: 0.4, triggers: [.overdue]), now: now
        ))
        #expect(one.kind == .hold)
        #expect(one.signals == [.overdue])
    }

    @Test("ACWR caution → hold")
    func cautionIsHold() {
        let now = date(2026, 9, 5)
        let v = advisor().evaluate(.init(workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.35), now: now))
        #expect(v.kind == .hold)
    }

    @Test("Half of the lifts regressing → hold; one of four → progress")
    func regressionShare() {
        let now = date(2026, 9, 5)
        let half = advisor().evaluate(.init(
            workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.0),
            overloadTrends: [trend("A", .regressing), trend("B", .regressing), trend("C", .progressing), trend("D", .plateau)], now: now
        ))
        #expect(half.kind == .hold)
        let one = advisor().evaluate(.init(
            workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.0),
            overloadTrends: [trend("A", .regressing), trend("B", .progressing), trend("C", .progressing), trend("D", .plateau)], now: now
        ))
        #expect(one.kind == .progress)
    }

    @Test("Systemic fatigue → hold, but just-trained groups do not count")
    func systemicFatigue() {
        let now = date(2026, 9, 5)
        let old = date(2026, 9, 1)
        let systemic = advisor().evaluate(.init(
            workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.0),
            recoveryPatterns: [pattern("chest", status: .fatigued, lastTrained: old),
                               pattern("back", status: .fatigued, lastTrained: old),
                               pattern("quads", status: .fatigued, lastTrained: old)], now: now
        ))
        #expect(systemic.kind == .hold)

        let justTrained = advisor().evaluate(.init(
            workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.0),
            recoveryPatterns: [pattern("chest", status: .fatigued, lastTrained: date(2026, 9, 4, 18)),
                               pattern("back", status: .fatigued, lastTrained: old),
                               pattern("quads", status: .fatigued, lastTrained: old)], now: now
        ))
        #expect(justTrained.kind == .progress)
    }

    // MARK: Hysteresis

    @Test("A deload verdict persists for five days even when the signal clears")
    func deloadPersists() {
        let adv = advisor()
        let day1 = date(2026, 9, 1)
        let first = adv.evaluate(.init(workouts: recentHistory(now: day1), trainingLoad: load(acwr: 1.6), now: day1))
        #expect(first.kind == .deload)

        let day3 = date(2026, 9, 3)
        let second = adv.evaluate(.init(workouts: recentHistory(now: day3), trainingLoad: load(acwr: 1.0), now: day3))
        #expect(second.kind == .deload)
        #expect(second.since == first.since)
        #expect(adv.lastVerdict?.kind == .deload)
    }

    @Test("Release needs two clear computations on distinct days after the persistence window")
    func releaseNeedsTwoClearDays() {
        let adv = advisor()
        let day1 = date(2026, 9, 1)
        adv.evaluate(.init(workouts: recentHistory(now: day1), trainingLoad: load(acwr: 1.6), now: day1))

        // Day 7, two same-day recomputes: still deload (same-day debounced).
        let day7 = date(2026, 9, 7, 9)
        #expect(adv.evaluate(.init(workouts: recentHistory(now: day7), trainingLoad: load(acwr: 1.0), now: day7)).kind == .deload)
        let day7later = date(2026, 9, 7, 20)
        #expect(adv.evaluate(.init(workouts: recentHistory(now: day7later), trainingLoad: load(acwr: 1.0), now: day7later)).kind == .deload)

        // Day 8: second distinct clear day → released to progress.
        let day8 = date(2026, 9, 8)
        let released = adv.evaluate(.init(workouts: recentHistory(now: day8), trainingLoad: load(acwr: 1.0), now: day8))
        #expect(released.kind == .progress)
        #expect(released.since == day8)
    }

    @Test("Logging a deload workout releases the deload verdict immediately")
    func deloadWorkoutReleases() {
        let adv = advisor()
        let day1 = date(2026, 9, 1)
        adv.evaluate(.init(workouts: recentHistory(now: day1), trainingLoad: load(acwr: 1.6), now: day1))

        let day2 = date(2026, 9, 2, 18)
        var history = recentHistory(now: day2)
        history.append(workout(on: date(2026, 9, 2, 10), isDeload: true))
        let v = adv.evaluate(.init(workouts: history, trainingLoad: load(acwr: 1.6), now: day2))
        #expect(v.kind == .hold)
        #expect(v.isActiveDeload)
    }

    @Test("hold → progress releases immediately")
    func holdReleasesImmediately() {
        let adv = advisor()
        let day1 = date(2026, 9, 1)
        #expect(adv.evaluate(.init(workouts: recentHistory(now: day1), trainingLoad: load(acwr: 1.35), now: day1)).kind == .hold)
        let day1later = date(2026, 9, 1, 15)
        #expect(adv.evaluate(.init(workouts: recentHistory(now: day1later), trainingLoad: load(acwr: 1.0), now: day1later)).kind == .progress)
    }

    @Test("persist: false never touches the store")
    func nonPersistingEvaluation() {
        let adv = advisor()
        let now = date(2026, 9, 5)
        let v = adv.evaluate(.init(workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.6), now: now), persist: false)
        #expect(v.kind == .deload)
        #expect(adv.lastVerdict == nil)
    }

    @Test("State survives a JSON round trip through the UserDefaults store")
    func userDefaultsRoundTrip() {
        let suite = "TrainingAdvisorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsTrainingVerdictStore(defaults: defaults)
        let adv = TrainingAdvisor(store: store, calendar: calendar)
        let now = date(2026, 9, 5)
        let v = adv.evaluate(.init(workouts: recentHistory(now: now), trainingLoad: load(acwr: 1.6), now: now))
        #expect(store.load()?.verdict == v)
        #expect(TrainingAdvisor(store: store, calendar: calendar).lastVerdict?.kind == .deload)
    }
}
