import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("DeloadDetectionService")
struct DeloadDetectionServiceTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
    private let squat = AnalyticsTestHelpers.makeExercise(name: "Squat", primaryMuscleGroup: .quadriceps, secondaryMuscleGroups: [])
    private let bodyWeight = 80.0

    /// bestE1RM chosen so a 5-rep set at `kg` has effort ratio kg × 1.125 / 120.
    private var bestE1RM: [UUID: Double] { [bench.id: 120, squat.id: 160] }

    private func session(on day: Date, benchKg: Double, squatKg: Double = 120, rpe: Double? = nil, isDeload: Bool = false) -> Workout {
        let benchSets = (1...3).map { AnalyticsTestHelpers.makeCompletedSet(order: $0, weight: benchKg, reps: 5, rpe: rpe) }
        let squatSets = (1...3).map { AnalyticsTestHelpers.makeCompletedSet(order: $0, weight: squatKg, reps: 5, rpe: rpe) }
        var w = AnalyticsTestHelpers.makeWorkout(
            exercises: [
                AnalyticsTestHelpers.makeWorkoutExercise(exercise: bench, order: 1, sets: benchSets),
                AnalyticsTestHelpers.makeWorkoutExercise(exercise: squat, order: 2, sets: squatSets),
            ],
            startedAt: day,
            completedAt: day.addingTimeInterval(3600)
        )
        w.isDeload = isDeload
        return w
    }

    /// `weeks` calendar weeks of two identical sessions per week, ending the week before `now`.
    private func consistentWeeks(_ weeks: Int, now: Date, benchKg: Double = 85) -> [Workout] {
        let currentWeekStart = calendar.weekStart(for: now)
        return (1...weeks).flatMap { back -> [Workout] in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -back, to: currentWeekStart)!
            return [
                session(on: calendar.date(byAdding: .day, value: 1, to: weekStart)!, benchKg: benchKg),
                session(on: calendar.date(byAdding: .day, value: 4, to: weekStart)!, benchKg: benchKg),
            ]
        }
    }

    private func load(acwr: Double) -> TrainingLoad {
        TrainingLoad(acuteLoad: acwr * 100, chronicLoad: 100, acwr: acwr, loadZone: LoadZone.from(acwr: acwr))
    }

    private func trend(_ exercise: Exercise, _ status: TrendStatus) -> OverloadTrend {
        OverloadTrend(exerciseId: exercise.id, exerciseName: exercise.name, weeklyE1RMs: [],
                      slopePerWeek: status == .regressing ? -2 : 1, trendStatus: status, overloadIndex: 0)
    }

    @Test("Twelve consistent weeks with steady load do not recommend a deload")
    func overdueAloneDoesNotFire() {
        let now = date(2026, 9, 3)
        let workouts = consistentWeeks(12, now: now)
        let rec = DeloadDetectionService.detectDeload(
            bodyWeightKg: bodyWeight, workouts: workouts, overloadTrends: [trend(bench, .plateau), trend(squat, .plateau)],
            trainingLoad: load(acwr: 1.0), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(rec == nil)
    }

    @Test("Overdue stands alone only after ten weeks with load trending above baseline")
    func overdueStandaloneNeedsRisingLoad() {
        let now = date(2026, 9, 3)
        let workouts = consistentWeeks(12, now: now)
        let analysis = DeloadDetectionService.analyze(
            bodyWeightKg: bodyWeight, workouts: workouts, overloadTrends: [],
            trainingLoad: load(acwr: 1.1), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(analysis?.triggers == [.overdue])
        #expect(analysis?.weeksSinceDeload == 12)
        // Standalone overdue lands in the hold band (≥0.35), below the deload band (<0.5).
        let urgency = analysis?.urgency ?? 0
        #expect(urgency >= 0.35 && urgency < 0.5)
    }

    @Test("A tagged deload week resets the weeks-since-deload counter")
    func taggedDeloadResets() {
        let now = date(2026, 9, 3)
        var workouts = consistentWeeks(12, now: now)
        // Tag both sessions three weeks back as deload.
        let threeBack = calendar.date(byAdding: .weekOfYear, value: -3, to: calendar.weekStart(for: now))!
        workouts = workouts.map { w in
            var w = w
            if calendar.weekStart(for: w.trainingDate) == threeBack { w.isDeload = true }
            return w
        }
        let weeks = DeloadDetectionService.weeksSinceDeload(
            workouts: workouts, bestE1RM: bestE1RM, bodyWeightKg: bodyWeight, now: now, calendar: calendar
        )
        #expect(weeks == 2)
    }

    @Test("An untrained week also counts as a reset")
    func untrainedWeekResets() {
        let now = date(2026, 9, 3)
        let fiveBack = calendar.date(byAdding: .weekOfYear, value: -5, to: calendar.weekStart(for: now))!
        let workouts = consistentWeeks(12, now: now).filter { calendar.weekStart(for: $0.trainingDate) != fiveBack }
        let weeks = DeloadDetectionService.weeksSinceDeload(
            workouts: workouts, bestE1RM: bestE1RM, bodyWeightKg: bodyWeight, now: now, calendar: calendar
        )
        #expect(weeks == 4)
    }

    @Test("Deload → normal → normal is not effort creep")
    func deloadThenNormalIsNotCreep() {
        let now = date(2026, 9, 10)
        var workouts = consistentWeeks(4, now: now)
        // Last three sessions: a light deload, then two ordinary sessions.
        workouts.append(session(on: date(2026, 8, 31), benchKg: 60, isDeload: true))
        workouts.append(session(on: date(2026, 9, 3), benchKg: 85))
        workouts.append(session(on: date(2026, 9, 7), benchKg: 85))
        let analysis = DeloadDetectionService.analyze(
            bodyWeightKg: bodyWeight, workouts: workouts, overloadTrends: [],
            trainingLoad: load(acwr: 1.0), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(analysis?.triggers.contains(DeloadSignal.effortCreep) == false)
    }

    @Test("Two small upticks over three sessions in one week are not creep")
    func twoUpticksAreNotCreep() {
        let window = [
            session(on: date(2026, 9, 1), benchKg: 85),
            session(on: date(2026, 9, 3), benchKg: 86),
            session(on: date(2026, 9, 5), benchKg: 87),
        ]
        let magnitude = DeloadDetectionService.detectEffortCreep(window: window, bestE1RM: bestE1RM, bodyWeightKg: bodyWeight)
        #expect(magnitude == nil)
    }

    @Test("Genuine four-session creep over ten days is detected")
    func genuineCreepIsDetected() {
        let window = [
            session(on: date(2026, 8, 25), benchKg: 80, squatKg: 110),
            session(on: date(2026, 8, 28), benchKg: 85, squatKg: 115),
            session(on: date(2026, 8, 31), benchKg: 90, squatKg: 120),
            session(on: date(2026, 9, 4), benchKg: 95, squatKg: 125),
        ]
        let magnitude = DeloadDetectionService.detectEffortCreep(window: window, bestE1RM: bestE1RM, bodyWeightKg: bodyWeight)
        #expect(magnitude != nil)
        #expect((magnitude ?? 0) > 0.5)
    }

    @Test("Rising RPE with flat loads is creep")
    func rpeCreepWithFlatLoad() {
        let window = [
            session(on: date(2026, 8, 25), benchKg: 85, rpe: 7),
            session(on: date(2026, 8, 28), benchKg: 85, rpe: 7.5),
            session(on: date(2026, 8, 31), benchKg: 85, rpe: 8),
            session(on: date(2026, 9, 4), benchKg: 85, rpe: 8.5),
        ]
        let magnitude = DeloadDetectionService.detectEffortCreep(window: window, bestE1RM: bestE1RM, bodyWeightKg: bodyWeight)
        #expect(magnitude != nil)
    }

    @Test("Today's session is excluded from the creep window")
    func todayExcluded() {
        let now = date(2026, 9, 5, 18)
        var workouts = consistentWeeks(4, now: now)
        workouts.append(session(on: date(2026, 9, 1), benchKg: 85))
        workouts.append(session(on: date(2026, 9, 3), benchKg: 85))
        workouts.append(session(on: date(2026, 9, 5, 10), benchKg: 100)) // one big day, today
        let analysis = DeloadDetectionService.analyze(
            bodyWeightKg: bodyWeight, workouts: workouts, overloadTrends: [],
            trainingLoad: load(acwr: 1.0), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(analysis?.triggers.contains(DeloadSignal.effortCreep) == false)
    }

    @Test("One regressing lift is not performance decline")
    func singleRegressingLiftIgnored() {
        let now = date(2026, 9, 3)
        let workouts = consistentWeeks(6, now: now)
        let analysis = DeloadDetectionService.analyze(
            bodyWeightKg: bodyWeight, workouts: workouts,
            overloadTrends: [trend(bench, .regressing), trend(squat, .progressing)],
            trainingLoad: load(acwr: 1.0), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(analysis?.triggers.contains(DeloadSignal.performanceDecline) == false)
    }

    @Test("Two regressing lifts plus effort creep recommend a deload")
    func twoRegressingLiftsWithCreepFire() {
        let now = date(2026, 9, 6)
        var workouts = consistentWeeks(4, now: now, benchKg: 80)
        workouts.append(session(on: date(2026, 8, 25), benchKg: 80, squatKg: 110))
        workouts.append(session(on: date(2026, 8, 28), benchKg: 85, squatKg: 115))
        workouts.append(session(on: date(2026, 8, 31), benchKg: 90, squatKg: 120))
        workouts.append(session(on: date(2026, 9, 4), benchKg: 95, squatKg: 125))
        let rec = DeloadDetectionService.detectDeload(
            bodyWeightKg: bodyWeight, workouts: workouts,
            overloadTrends: [trend(bench, .regressing), trend(squat, .regressing)],
            trainingLoad: load(acwr: 1.1), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(rec != nil)
        #expect(rec?.primaryTriggers.count == 2)
    }

    @Test("ACWR at 1.6 alone clears the fire threshold")
    func highACWRFires() {
        let now = date(2026, 9, 3)
        let workouts = consistentWeeks(6, now: now)
        let rec = DeloadDetectionService.detectDeload(
            bodyWeightKg: bodyWeight, workouts: workouts, overloadTrends: [],
            trainingLoad: load(acwr: 1.7), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(rec?.triggers.contains(DeloadSignal.highACWR) == true)
    }

    @Test("Fewer than six sessions yields nothing")
    func tooFewSessions() {
        let now = date(2026, 9, 3)
        let workouts = Array(consistentWeeks(2, now: now).prefix(3))
        let rec = DeloadDetectionService.detectDeload(
            bodyWeightKg: bodyWeight, workouts: workouts, overloadTrends: [],
            trainingLoad: load(acwr: 2.0), bestE1RM: bestE1RM, now: now, calendar: calendar
        )
        #expect(rec == nil)
    }
}
