import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("Progression rules")
struct ProgressionRuleEngineTests {
    typealias Engine = ProgressionRuleEngine

    private let reps = ProgressionRule(kind: .repsThenWeight, sets: 3, minReps: 6, maxReps: 10, incrementKg: 2.5, startWeightKg: 80)
    private let steps = ProgressionRule(kind: .fixedSteps, sets: 4, minReps: 5, maxReps: 5, incrementKg: 5,
        missesBeforeBackoff: 3, backoffPercent: 10, startWeightKg: 100)

    private func done(_ weight: Double, _ reps: Int, all: Bool = true) -> ProgressionOutcome {
        .init(weightKg: weight, lowestReps: reps, completedAllSets: all)
    }

    private func set(_ weight: Double?, _ reps: Int, type: SetType = .normal, completed: Bool = true) -> ExerciseSet {
        ExerciseSet(id: UUID(), order: 0, setType: type, weight: weight, reps: reps, durationSeconds: nil, distanceMeters: nil,
            rpe: nil, isCompleted: completed, isPersonalRecord: false, completedAt: completed ? Date() : nil)
    }

    private func targets(_ rule: ProgressionRule, _ count: Int) -> [String] {
        Engine.projection(from: Engine.initialState(rule), rule: rule, count: count).map { "\($0.weightKg)x\($0.reps)" }
    }

    // MARK: - The rule

    @Test("Reps then weight climbs the rep range, then adds weight and restarts")
    func repLadder() {
        #expect(targets(reps, 7) == ["80.0x6", "80.0x7", "80.0x8", "80.0x9", "80.0x10", "82.5x6", "82.5x7"])
    }

    @Test("A conservative rule repeats each target before moving on")
    func repeatsEachTarget() {
        var rule = reps
        rule.sessionsPerStep = 2
        #expect(targets(rule, 5) == ["80.0x6", "80.0x6", "80.0x7", "80.0x7", "80.0x8"])
    }

    @Test("Weight steps add weight at fixed reps")
    func weightSteps() {
        #expect(targets(steps, 3) == ["100.0x5", "105.0x5", "110.0x5"])
    }

    @Test("A missed session repeats the target and breaks the success streak")
    func missHolds() {
        var rule = reps
        rule.sessionsPerStep = 2
        var state = Engine.advance(Engine.initialState(rule), rule: rule, outcome: done(80, 6))
        #expect(state.successStreak == 1)
        state = Engine.advance(state, rule: rule, outcome: done(80, 5))
        #expect(state.target == ProgressionTarget(weightKg: 80, reps: 6))
        #expect(state.successStreak == 0)
        #expect(state.missStreak == 1)
    }

    @Test("Doing fewer sets than planned is a miss even when the reps were there")
    func unfinishedSetsMiss() {
        let state = Engine.advance(Engine.initialState(reps), rule: reps, outcome: done(80, 8, all: false))
        #expect(state.target == ProgressionTarget(weightKg: 80, reps: 6))
    }

    @Test("Beating the target moves to one rep above what every set reached")
    func beatingTheTarget() {
        let state = Engine.advance(Engine.initialState(reps), rule: reps, outcome: done(80, 9))
        #expect(state.target == ProgressionTarget(weightKg: 80, reps: 10))
        let atTop = Engine.advance(Engine.initialState(reps), rule: reps, outcome: done(80, 10))
        #expect(atTop.target == ProgressionTarget(weightKg: 82.5, reps: 6))
    }

    @Test("The ladder follows the weight that was actually lifted")
    func followsLiftedWeight() {
        let heavier = Engine.advance(Engine.initialState(reps), rule: reps, outcome: done(85, 6))
        #expect(heavier.target == ProgressionTarget(weightKg: 85, reps: 7))
        let lighter = Engine.advance(Engine.initialState(reps), rule: reps, outcome: done(75, 5))
        #expect(lighter.target == ProgressionTarget(weightKg: 75, reps: 6))
        // A rounding difference from another unit is not a different weight.
        let rounded = Engine.advance(Engine.initialState(reps), rule: reps, outcome: done(79.8, 6))
        #expect(rounded.target == ProgressionTarget(weightKg: 80, reps: 7))
    }

    @Test("Weight steps back off after the set number of misses in a row")
    func backsOff() {
        var state = Engine.State(target: .init(weightKg: 110, reps: 5))
        state = Engine.advance(state, rule: steps, outcome: done(110, 4))
        state = Engine.advance(state, rule: steps, outcome: done(110, 3))
        #expect(state.target.weightKg == 110)
        state = Engine.advance(state, rule: steps, outcome: done(110, 4))
        #expect(state.target == ProgressionTarget(weightKg: 100, reps: 5))
        #expect(state.missStreak == 0)
    }

    @Test("Without a weight step the rule progresses reps only")
    func repsOnly() {
        var rule = reps
        rule.incrementKg = 0
        rule.startReps = 9
        #expect(targets(rule, 3) == ["80.0x9", "80.0x10", "80.0x10"])
    }

    @Test("Rules are validated and weight steps collapse to one rep target")
    func validation() throws {
        var rule = steps
        rule.minReps = 3
        #expect(rule.normalized.minReps == 5)
        try steps.validate()
        rule = reps
        rule.minReps = 12
        #expect(throws: PlanEditError.self) { try rule.validate() }
        rule = steps
        rule.incrementKg = 0
        #expect(throws: PlanEditError.self) { try rule.validate() }
    }

    @Test("The summary states the rule in numbers")
    func summary() {
        #expect(reps.summary(unit: .kg).contains("3 × 6–10"))
        #expect(reps.summary(unit: .kg).contains("at 10, add"))
        #expect(steps.summary(unit: .kg).contains("After 3 misses in a row, drop 10%"))
    }

    // MARK: - Reading a workout

    @Test("An outcome uses the working weight, ignores warm-ups, and counts heavier sets")
    func readsOutcome() {
        let planned = PlannedExerciseSet(planExerciseId: UUID(), exerciseId: UUID(), exerciseName: "Bench", sets: 3,
            targetReps: 8, targetWeight: 80, percentageOf1RM: 0)
        let plain = Engine.outcome(planned: planned, performed: [set(40, 10, type: .warmup), set(80, 8), set(80, 8), set(80, 7)])
        #expect(plain == done(80, 7))
        let short = Engine.outcome(planned: planned, performed: [set(80, 8), set(80, 8), set(80, 8, completed: false)])
        #expect(short == done(80, 8, all: false))
        let topSet = Engine.outcome(planned: planned, performed: [set(80, 8), set(82.5, 6), set(80, 8)])
        #expect(topSet == done(80, 8))
        #expect(Engine.outcome(planned: planned, performed: [set(40, 10, type: .warmup)]) == nil)
    }

    // MARK: - Laying out a plan

    /// Eight weeks, Monday and Thursday, one bench exercise.
    private func plan(rule: ProgressionRule?, deloadEvery: Int? = 0) -> ProgressionPlan {
        var exercise = ProgressionTestHelpers.makeTestPlanExercise(name: "Bench Press", current1RM: 100)
        exercise.progression = rule
        var plan = ProgressionTestHelpers.makeTestPlan(exercises: [exercise], primaryGoal: .hypertrophy, weeklyFrequency: 2)
        plan.trainingDays = [2, 5]
        plan.configuration = PlanConfiguration(durationWeeks: 8)
        plan.configuration?.deloadEveryWeeks = deloadEvery
        plan.blocks = ProgramDesignService().generateProgram(for: plan)
        plan.targetEndDate = sessions(plan).compactMap(\.scheduledDate).max()
        ProgressionRuleEngine.reproject(&plan)
        return plan
    }

    private func sessions(_ plan: ProgressionPlan) -> [PlannedSession] {
        plan.blocks.flatMap(\.weeks).flatMap(\.sessions).sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
    }

    private func ladder(_ plan: ProgressionPlan, _ count: Int) -> [String] {
        sessions(plan).prefix(count).map { "\($0.plannedExercises[0].targetWeight)x\($0.plannedExercises[0].targetReps)" }
    }

    private func update(_ plan: inout ProgressionPlan, session id: UUID, _ change: (inout PlannedSession) -> Void) {
        for b in plan.blocks.indices {
            for w in plan.blocks[b].weeks.indices {
                for s in plan.blocks[b].weeks[w].sessions.indices where plan.blocks[b].weeks[w].sessions[s].id == id {
                    change(&plan.blocks[b].weeks[w].sessions[s])
                }
            }
        }
    }

    @Test("A new plan lays the rule's ladder over every session of the exercise")
    func laysOutLadder() {
        let plan = plan(rule: reps)
        #expect(sessions(plan).count == 16)
        #expect(ladder(plan, 6) == ["80.0x6", "80.0x7", "80.0x8", "80.0x9", "80.0x10", "82.5x6"])
        let first = sessions(plan)[0].plannedExercises[0]
        #expect(first.sets == 3)
        #expect(first.percentageOf1RM == 0)
    }

    @Test("An exercise without a rule keeps the percentage wave")
    func waveUntouched() {
        let plan = plan(rule: nil)
        #expect(sessions(plan).allSatisfy { $0.plannedExercises[0].percentageOf1RM > 0 })
    }

    @Test("Completed sessions decide where the ladder continues")
    func continuesFromCompletedSessions() {
        var plan = plan(rule: reps)
        let ids = sessions(plan).map(\.id)
        update(&plan, session: ids[0]) {
            $0.completedWorkoutId = UUID(); $0.completedAt = $0.scheduledDate
            $0.plannedExercises[0].outcome = self.done(80, 6)
        }
        update(&plan, session: ids[1]) {
            $0.completedWorkoutId = UUID(); $0.completedAt = $0.scheduledDate
            $0.plannedExercises[0].outcome = self.done(80, 6)
        }
        ProgressionRuleEngine.reproject(&plan)
        // Session 2 asked for 7 and got 6: the third session asks for 7 again.
        #expect(ladder(plan, 4) == ["80.0x6", "80.0x7", "80.0x7", "80.0x8"])
        // Laying the plan out again changes nothing.
        let once = plan
        ProgressionRuleEngine.reproject(&plan)
        #expect(plan == once)
    }

    @Test("A target set by hand is kept and the ladder continues from it")
    func continuesFromManualTarget() {
        var plan = plan(rule: reps)
        let ids = sessions(plan).map(\.id)
        update(&plan, session: ids[1]) {
            $0.plannedExercises[0].targetWeight = 90; $0.plannedExercises[0].targetReps = 6
            $0.plannedExercises[0].isUserOverride = true
        }
        ProgressionRuleEngine.reproject(&plan)
        #expect(ladder(plan, 4) == ["80.0x6", "90.0x6", "90.0x7", "90.0x8"])
    }

    @Test("A deload session repeats the current target at its deload weight and does not advance")
    func deloadRepeats() {
        let plan = plan(rule: reps, deloadEvery: 2)
        let all = sessions(plan)
        // Week 2 (sessions 3 and 4) is the deload week.
        #expect(all[2].isDeload && all[3].isDeload)
        #expect(all[2].deloadPrescription?.normalExercises[0].targetReps == 8)
        #expect(all[2].plannedExercises[0].targetWeight == 40)
        #expect(ladder(plan, 5)[4] == "80.0x8")
    }

    @Test("While the coach says deload, the next session repeats the last one")
    func holdsIncreases() {
        var plan = plan(rule: reps)
        let ids = sessions(plan).map(\.id)
        update(&plan, session: ids[0]) {
            $0.completedWorkoutId = UUID(); $0.completedAt = $0.scheduledDate
            $0.plannedExercises[0].outcome = self.done(80, 6)
        }
        plan.configuration?.holdIncreases = true
        ProgressionRuleEngine.reproject(&plan)
        #expect(ladder(plan, 3) == ["80.0x6", "80.0x6", "80.0x7"])
        plan.configuration?.holdIncreases = false
        ProgressionRuleEngine.reproject(&plan)
        #expect(ladder(plan, 3) == ["80.0x6", "80.0x7", "80.0x8"])
    }

    @Test("The deload cadence is a setting: off, or every Nth week")
    func deloadCadence() {
        #expect(sessions(plan(rule: reps, deloadEvery: 0)).allSatisfy { !$0.isDeload })
        let everyThird = sessions(plan(rule: reps, deloadEvery: 3))
        #expect(Set(everyThird.filter(\.isDeload).compactMap(\.programmingWeekNumber)) == [3, 6])
        // Without the setting an intermediate plan keeps a deload every fourth week.
        #expect(Set(sessions(plan(rule: reps, deloadEvery: nil)).filter(\.isDeload).compactMap(\.programmingWeekNumber)) == [4, 8])
    }

    // MARK: - Editing

    @Test("Giving an exercise a rule re-lays the remaining plan, and the edit can be undone")
    func setProgressionEdit() throws {
        let original = plan(rule: nil)
        let exerciseID = original.exercises[0].exerciseId
        let settings = PlanConfiguration(durationWeeks: 8)
        let request = PlanEditRequest(operation: .setProgression, exerciseID: exerciseID, progression: steps)
        let preview = try PlanEditingService.preview(plan: original, request: request, settings: settings, now: original.startDate)
        #expect(preview.summaryLines.contains { $0.contains("Bench Press: 4 × 5") })
        let edited = try PlanEditingService.applying(request, to: original, settings: settings, now: original.startDate)
        #expect(edited.exercises[0].progression == steps)
        #expect(ladder(edited, 3) == ["100.0x5", "105.0x5", "110.0x5"])
        let editID = try #require(edited.adjustments.last?.id)
        let undone = try PlanEditingService.applying(.init(operation: .undoEdit, editID: editID), to: edited, settings: settings, now: original.startDate)
        #expect(undone.exercises[0].progression == nil)
        #expect(sessions(undone).map(\.plannedExercises) == sessions(original).map(\.plannedExercises))
    }

    @Test("Removing a session moves the ladder up instead of leaving a gap")
    func removingSessionKeepsLadder() throws {
        let original = plan(rule: reps)
        let second = sessions(original)[1].id
        let edited = try PlanEditingService.applying(.init(operation: .removeSessions, sessionIDs: [second]), to: original,
            settings: PlanConfiguration(durationWeeks: 8), now: original.startDate)
        #expect(sessions(edited).count == 15)
        #expect(ladder(edited, 3) == ["80.0x6", "80.0x7", "80.0x8"])
    }

    @Test("A plan can be renamed, and an unchanged name is rejected")
    func rename() throws {
        let original = plan(rule: reps)
        let settings = PlanConfiguration(durationWeeks: 8)
        let renamed = try PlanEditingService.applying(.init(operation: .renamePlan, label: "  Winter bulk "), to: original, settings: settings, now: original.startDate)
        #expect(renamed.name == "Winter bulk")
        #expect(throws: PlanEditError.self) {
            try PlanEditingService.applying(.init(operation: .renamePlan, label: original.name), to: original, settings: settings, now: original.startDate)
        }
    }

    // MARK: - Presets

    @Test("Each pace stands for a concrete rule")
    func pacePresets() {
        let start = ProgressionTarget(weightKg: 80, reps: 8)
        let standard = Engine.defaultRule(pace: .standard, goal: .hypertrophy, category: .barbell, muscle: .chest, isCompound: true, start: start)
        #expect(standard.kind == .repsThenWeight)
        #expect(standard.minReps == 6 && standard.maxReps == 10 && standard.incrementKg == 2.5 && standard.sessionsPerStep == 1)
        #expect(standard.startWeightKg == 80 && standard.startReps == 8)
        let conservative = Engine.defaultRule(pace: .conservative, goal: .hypertrophy, category: .barbell, muscle: .quadriceps, isCompound: true, start: start)
        #expect(conservative.sessionsPerStep == 2 && conservative.incrementKg == 5)
        let aggressive = Engine.defaultRule(pace: .aggressive, goal: .strength, category: .barbell, muscle: .chest, isCompound: true, start: start)
        #expect(aggressive.kind == .fixedSteps && aggressive.maxReps == 5 && aggressive.missesBeforeBackoff == 3)
        try? aggressive.validate()
    }

    private func workout(_ exerciseID: UUID, weight: Double, reps: Int, daysAgo: Int) -> Workout {
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        let exercise = ProgressionTestHelpers.makeTestExercise(id: exerciseID, name: "Bench Press")
        return Workout(id: UUID(), name: "Bench", startedAt: date, completedAt: date, notes: nil, templateId: nil,
            exercises: [WorkoutExercise(id: UUID(), exercise: exercise, order: 0, supersetGroup: nil, notes: nil,
                restTimerSeconds: nil, sets: [set(weight, reps), set(weight, reps), set(weight, reps)])])
    }

    @Test("The start comes from the latest workout, converted when its reps are outside the range")
    func suggestedStart() {
        let id = UUID()
        let inRange = Engine.suggestedStart(exerciseID: id, workouts: [workout(id, weight: 70, reps: 12, daysAgo: 9), workout(id, weight: 80, reps: 8, daysAgo: 2)],
            range: 6...10, incrementKg: 2.5)
        #expect(inRange == ProgressionTarget(weightKg: 80, reps: 8))
        // 100 kg × 3 is a 110 kg estimate; six reps with two in reserve is 110 / (1 + 8/30) = 86.8, stepped down to 85.
        let heavy = Engine.suggestedStart(exerciseID: id, workouts: [workout(id, weight: 100, reps: 3, daysAgo: 2)], range: 6...10, incrementKg: 2.5)
        #expect(heavy == ProgressionTarget(weightKg: 85, reps: 6))
        #expect(Engine.suggestedStart(exerciseID: UUID(), workouts: [workout(id, weight: 80, reps: 8, daysAgo: 2)], range: 6...10, incrementKg: 2.5) == nil)
    }

    private func trend(_ exerciseID: UUID, start: Double, perWeek: Double, weeks: Int = 8) -> OverloadTrend {
        let monday = ProgressionTestHelpers.fixedMondayStart
        let readings = (0..<weeks).map { WeeklyE1RM(weekStart: monday.addingTimeInterval(Double($0) * 7 * 86_400), e1rm: start + perWeek * Double($0)) }
        return OverloadTrend(id: UUID(), exerciseId: exerciseID, exerciseName: "Lift", weeklyE1RMs: readings, slopePerWeek: perWeek,
            trendStatus: .progressing, overloadIndex: 0, windowStart: readings.first?.weekStart, windowEnd: readings.last?.weekStart,
            slopeMargin: nil, observationCount: weeks, meaningfulSlope: nil)
    }

    @Test("The recommended pace follows the lifter's own weekly gain")
    func recommendedPace() {
        let fast = UUID(), slow = UUID()
        let trends = [trend(fast, start: 60, perWeek: 1.2), trend(slow, start: 140, perWeek: 0.1)]
        #expect(Engine.recommendedPace(trends: trends, exerciseIDs: [fast]).pace == .aggressive)
        #expect(Engine.recommendedPace(trends: trends, exerciseIDs: [slow]).pace == .conservative)
        #expect(Engine.recommendedPace(trends: [trend(slow, start: 100, perWeek: 0.5)]).pace == .standard)
        let none = Engine.recommendedPace(trends: [trend(fast, start: 60, perWeek: 1, weeks: 2)])
        #expect(none.pace == .standard && none.weeklyGain == nil)
    }
}
