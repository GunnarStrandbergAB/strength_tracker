import Foundation

/// Runs each exercise's `ProgressionRule`: what a completed session does to the next
/// target, and what the remaining sessions ask for if every target is hit.
///
/// Everything is derived from the plan alone. A completed session carries what was done
/// against its target (`PlannedExerciseSet.outcome`), so replaying the completed sessions
/// in order gives the current state. Correcting or deleting a past workout therefore
/// never applies a step twice.
public enum ProgressionRuleEngine {
    public struct State: Equatable, Sendable {
        public var target: ProgressionTarget
        public var successStreak = 0
        public var missStreak = 0

        public init(target: ProgressionTarget) { self.target = target }
    }

    // MARK: - The rule

    public static func initialState(_ rule: ProgressionRule) -> State {
        let rule = rule.normalized
        return State(target: .init(weightKg: rule.startWeightKg, reps: rule.startReps))
    }

    /// The state after one session. A session counts as a success when every planned
    /// set was done and none fell short of the rep target.
    public static func advance(_ state: State, rule: ProgressionRule, outcome: ProgressionOutcome) -> State {
        let rule = rule.normalized
        var next = state
        // Follow the weight that was actually lifted, not the one that was asked for.
        if abs(outcome.weightKg - state.target.weightKg) > max(0.5, rule.incrementKg / 4) {
            next = State(target: .init(weightKg: outcome.weightKg, reps: state.target.reps))
        }
        guard outcome.completedAllSets, outcome.lowestReps >= next.target.reps else {
            next.successStreak = 0
            next.missStreak += 1
            if rule.missesBeforeBackoff > 0, rule.backoffPercent > 0, next.missStreak >= rule.missesBeforeBackoff {
                next.missStreak = 0
                let reduced = next.target.weightKg * Double(100 - rule.backoffPercent) / 100
                next.target.weightKg = rule.incrementKg > 0 ? max(0, reduced.rounded(toNearest: rule.incrementKg)) : reduced
            }
            return next
        }
        next.missStreak = 0
        next.successStreak += 1
        guard next.successStreak >= rule.sessionsPerStep else { return next }
        next.successStreak = 0
        switch rule.kind {
        case .fixedSteps:
            next.target.weightKg += rule.incrementKg
        case .repsThenWeight:
            let reached = max(outcome.lowestReps, next.target.reps)
            if reached < rule.maxReps {
                next.target.reps = reached + 1
            } else if rule.incrementKg > 0 {
                next.target = .init(weightKg: next.target.weightKg + rule.incrementKg, reps: rule.minReps)
            } else {
                next.target.reps = rule.maxReps
            }
        }
        return next
    }

    /// Targets for the next `count` sessions if every one is hit, starting with the current one.
    public static func projection(from state: State, rule: ProgressionRule, count: Int) -> [ProgressionTarget] {
        var cursor = state
        var targets: [ProgressionTarget] = []
        for _ in 0..<max(0, count) {
            targets.append(cursor.target)
            cursor = advance(cursor, rule: rule, outcome: hit(cursor.target))
        }
        return targets
    }

    private static func hit(_ target: ProgressionTarget) -> ProgressionOutcome {
        .init(weightKg: target.weightKg, lowestReps: target.reps, completedAllSets: true)
    }

    // MARK: - Reading a workout

    /// What was done against `planned`, or nil when no working set was completed.
    /// The working weight is the one most sets used (the heavier on a tie); only sets
    /// at that weight decide the reps, and heavier sets still count towards the total.
    public static func outcome(planned: PlannedExerciseSet, performed sets: [ExerciseSet]) -> ProgressionOutcome? {
        let working = sets.filter { $0.setType != .warmup && $0.isFullyCompleted && $0.reps != nil }
        guard !working.isEmpty else { return nil }
        func weight(_ set: ExerciseSet) -> Double { ((set.weight ?? planned.targetWeight) * 100).rounded() / 100 }
        let counts = Dictionary(grouping: working, by: weight).mapValues(\.count)
        guard let workingWeight = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else { return nil }
        let atWeight = working.filter { weight($0) == workingWeight }
        let heavier = working.filter { weight($0) > workingWeight }
        return ProgressionOutcome(weightKg: workingWeight,
            lowestReps: atWeight.compactMap(\.reps).min() ?? 0,
            completedAllSets: atWeight.count + heavier.count >= planned.sets)
    }

    /// Stores what each completed session did against its rule-driven targets, and
    /// clears what no longer has a workout behind it.
    public static func recordOutcomes(in plan: inout ProgressionPlan, workoutsById: [UUID: Workout]) {
        let ruled = plan.exercises.filter { $0.progression != nil }
        guard !ruled.isEmpty else { return }
        for b in plan.blocks.indices {
            for w in plan.blocks[b].weeks.indices {
                for s in plan.blocks[b].weeks[w].sessions.indices {
                    let session = plan.blocks[b].weeks[w].sessions[s]
                    let workout = session.completedWorkoutId.flatMap { workoutsById[$0] }
                    for e in session.plannedExercises.indices {
                        let planned = session.plannedExercises[e]
                        guard let exercise = ruled.first(where: { matches(planned, $0) }) else { continue }
                        var outcome: ProgressionOutcome?
                        // Percentage-wave targets from before the rule are not part of its history.
                        if let workout, planned.percentageOf1RM == 0, !session.isDeload, !workout.isDeload,
                           let logged = workout.exercises.first(where: { $0.exercise.id == planned.exerciseId }),
                           logged.exercise.exerciseType == .weightedReps,
                           exercise.sharesLoggingConvention(with: logged.exercise) {
                            outcome = self.outcome(planned: planned, performed: logged.sets)
                        }
                        plan.blocks[b].weeks[w].sessions[s].plannedExercises[e].outcome = outcome
                    }
                }
            }
        }
    }

    // MARK: - Laying out the plan

    /// Where a rule-driven exercise stands after its completed sessions, and the last
    /// target it was actually trained at.
    public static func currentState(of exercise: PlanExercise, in plan: ProgressionPlan) -> (state: State, lastTrained: ProgressionTarget?)? {
        guard let rule = exercise.progression?.normalized else { return nil }
        var state = initialState(rule)
        var lastTrained: ProgressionTarget?
        let completed = plan.blocks.flatMap(\.weeks).flatMap(\.sessions).filter(\.isCompleted)
            .sorted { ($0.completedAt ?? $0.scheduledDate ?? .distantPast) < ($1.completedAt ?? $1.scheduledDate ?? .distantPast) }
        for session in completed where !session.isDeload {
            guard let planned = session.plannedExercises.first(where: { matches($0, exercise) }),
                  let outcome = planned.outcome,
                  let asked = planTarget(of: planned, for: exercise) else { continue }
            if !same(asked, state.target) { state = State(target: asked) }
            let performed = ProgressionOutcome(
                weightKg: WeightRecordingHistory.convertWeight(outcome.weightKg, from: planned.weightRecording ?? exercise.weightRecording, to: exercise.weightRecording) ?? outcome.weightKg,
                lowestReps: outcome.lowestReps, completedAllSets: outcome.completedAllSets)
            state = advance(state, rule: rule, outcome: performed)
            lastTrained = asked
        }
        // A rule changed mid-plan keeps the weight and brings the reps inside its range.
        state.target.reps = min(max(state.target.reps, rule.minReps), rule.maxReps)
        return (state, lastTrained)
    }

    /// Rewrites the open sessions of every rule-driven exercise from where it stands
    /// now. A target the user set by hand is kept, and the ladder continues from it.
    /// Deload sessions repeat the current target under their deload percentage.
    public static func reproject(_ plan: inout ProgressionPlan, protected: Set<UUID> = []) {
        let hold = plan.configuration?.holdIncreases == true
        var open: [(block: Int, week: Int, session: Int, date: Date)] = []
        for b in plan.blocks.indices {
            for w in plan.blocks[b].weeks.indices {
                for s in plan.blocks[b].weeks[w].sessions.indices {
                    let session = plan.blocks[b].weeks[w].sessions[s]
                    guard !session.isClosed, !protected.contains(session.id) else { continue }
                    open.append((b, w, s, session.scheduledDate ?? .distantFuture))
                }
            }
        }
        open.sort { $0.date < $1.date }

        for exercise in plan.exercises {
            guard let rule = exercise.progression?.normalized,
                  let current = currentState(of: exercise, in: plan) else { continue }
            var cursor = current.state
            // While the coach says deload, the next session repeats the last one.
            if hold, let last = current.lastTrained, cursor.target.isAbove(last) { cursor = State(target: last) }

            for slot in open {
                var session = plan.blocks[slot.block].weeks[slot.week].sessions[slot.session]
                // A deload without a saved normal prescription holds its own reduced targets.
                if session.isDeload, session.deloadPrescription == nil { continue }
                var sets = session.deloadPrescription?.normalExercises ?? session.plannedExercises
                guard let index = sets.firstIndex(where: { matches($0, exercise) }) else { continue }

                if sets[index].isUserOverride == true {
                    if let manual = planTarget(of: sets[index], for: exercise) { cursor = State(target: manual) }
                } else {
                    let recording = sets[index].weightRecording ?? exercise.weightRecording
                    guard let weight = WeightRecordingHistory.convertWeight(cursor.target.weightKg, from: exercise.weightRecording, to: recording) else { continue }
                    sets[index].sets = rule.sets
                    sets[index].targetReps = cursor.target.reps
                    sets[index].targetWeight = weight
                    sets[index].percentageOf1RM = 0
                    sets[index].restSeconds = rule.restSeconds
                    sets[index].outcome = nil
                    if session.deloadPrescription != nil {
                        session.deloadPrescription?.normalExercises = sets
                        PlanDeloadPolicy.refresh(&session)
                    } else {
                        session.plannedExercises = sets
                    }
                    plan.blocks[slot.block].weeks[slot.week].sessions[slot.session] = session
                }
                if !session.isDeload { cursor = advance(cursor, rule: rule, outcome: hit(cursor.target)) }
            }
        }
    }

    private static func matches(_ planned: PlannedExerciseSet, _ exercise: PlanExercise) -> Bool {
        planned.planExerciseId == exercise.id || planned.exerciseId == exercise.exerciseId
    }

    private static func same(_ a: ProgressionTarget, _ b: ProgressionTarget) -> Bool {
        a.reps == b.reps && abs(a.weightKg - b.weightKg) < 0.01
    }

    /// A planned set's target in the plan exercise's logging convention.
    private static func planTarget(of planned: PlannedExerciseSet, for exercise: PlanExercise) -> ProgressionTarget? {
        WeightRecordingHistory.convertWeight(planned.targetWeight, from: planned.weightRecording ?? exercise.weightRecording, to: exercise.weightRecording)
            .map { ProgressionTarget(weightKg: $0, reps: planned.targetReps) }
    }

    // MARK: - Presets

    private static let lowerBody: Set<MuscleGroup> = [.quadriceps, .hamstrings, .glutes, .calves]

    /// The smallest step that is practical on the equipment.
    public static func defaultIncrementKg(category: ExerciseCategory, muscle: MuscleGroup) -> Double {
        switch category {
        case .barbell, .trapBar, .smithMachine:
            return lowerBody.contains(muscle) ? 5 : 2.5
        case .dumbbell, .kettlebell:
            return 2
        case .machine:
            return lowerBody.contains(muscle) ? 5 : 2.5
        default:
            return 2.5
        }
    }

    public static func defaultRepRange(goal: TrainingGoal, isCompound: Bool) -> ClosedRange<Int> {
        switch goal {
        case .strength, .powerlifting: return isCompound ? 3...5 : 6...10
        case .hypertrophy: return isCompound ? 6...10 : 8...12
        case .muscularEndurance: return 12...20
        case .generalFitness: return 8...12
        }
    }

    /// The rule a pace stands for on one exercise. Every number in it can be changed afterwards.
    public static func defaultRule(pace: PlanPace, goal: TrainingGoal, category: ExerciseCategory, muscle: MuscleGroup,
                                   isCompound: Bool, start: ProgressionTarget? = nil) -> ProgressionRule {
        let range = defaultRepRange(goal: goal, isCompound: isCompound)
        let increment = defaultIncrementKg(category: category, muscle: muscle)
        let rest = (goal.restSeconds.lowerBound + goal.restSeconds.upperBound) / 2
        let sets = goal == .strength || goal == .powerlifting ? 4 : 3
        let weight = start?.weightKg ?? 0
        // A band has no weight to add or to estimate: it progresses on reps alone, at every pace.
        if category == .resistanceBand {
            return ProgressionRule(kind: .repsThenWeight, sets: sets, minReps: range.lowerBound, maxReps: range.upperBound,
                incrementKg: 0, sessionsPerStep: pace == .conservative ? 2 : 1, startWeightKg: weight,
                startReps: start.map { min(max($0.reps, range.lowerBound), range.upperBound) }, restSeconds: rest)
        }
        switch pace {
        case .aggressive:
            let reps = goal == .strength || goal == .powerlifting ? range.upperBound : (range.lowerBound + range.upperBound) / 2
            return ProgressionRule(kind: .fixedSteps, sets: sets, minReps: reps, maxReps: reps, incrementKg: increment,
                sessionsPerStep: 1, missesBeforeBackoff: 3, backoffPercent: 10, startWeightKg: weight, startReps: reps, restSeconds: rest)
        case .standard, .conservative:
            return ProgressionRule(kind: .repsThenWeight, sets: sets, minReps: range.lowerBound, maxReps: range.upperBound,
                incrementKg: increment, sessionsPerStep: pace == .conservative ? 2 : 1, startWeightKg: weight,
                startReps: start.map { min(max($0.reps, range.lowerBound), range.upperBound) }, restSeconds: rest)
        }
    }

    /// Where to start, from the most recent workout that trained the exercise. Inside the
    /// rep range the last working weight and reps are kept. Outside it, the weight is
    /// converted (Epley) to the bottom of the range with two reps in reserve.
    /// With `weightIsOptional` (a band), a workout logged without weight gives its reps.
    public static func suggestedStart(exerciseID: UUID, workouts: [Workout], range: ClosedRange<Int>, incrementKg: Double,
                                      weightIsOptional: Bool = false) -> ProgressionTarget? {
        let recent = workouts.filter { $0.completedAt != nil && !$0.isDeload }.sorted { $0.trainingDate > $1.trainingDate }
        for workout in recent {
            guard let logged = workout.exercises.first(where: { $0.exercise.id == exerciseID }),
                  logged.exercise.exerciseType == .weightedReps else { continue }
            let reference = PlannedExerciseSet(planExerciseId: exerciseID, exerciseId: exerciseID, exerciseName: logged.exercise.name,
                sets: 1, targetReps: range.lowerBound, targetWeight: 0, percentageOf1RM: 0)
            guard let done = outcome(planned: reference, performed: logged.sets), done.lowestReps > 0 else { continue }
            if done.weightKg <= 0 {
                guard weightIsOptional else { continue }
                return .init(weightKg: 0, reps: min(max(done.lowestReps, range.lowerBound), range.upperBound))
            }
            if range.contains(done.lowestReps) { return .init(weightKg: done.weightKg, reps: done.lowestReps) }
            let oneRepMax = done.weightKg * (1 + Double(min(done.lowestReps, AnalyticsCalculations.maxRepsForE1RM)) / 30)
            let converted = oneRepMax / (1 + Double(range.lowerBound + 2) / 30)
            let step = incrementKg > 0 ? incrementKg : 2.5
            return .init(weightKg: max(step, (converted / step).rounded(.down) * step), reps: range.lowerBound)
        }
        return nil
    }

    public struct PaceRecommendation: Equatable, Sendable {
        public var pace: PlanPace
        /// Median weekly gain in estimated 1RM across the measured lifts, as a share of the lift.
        public var weeklyGain: Double?
        public var liftCount: Int
    }

    /// The pace the lifter's own recent progress suits. Lifts with fewer than four
    /// weekly readings are left out; with none left, the answer is the standard pace.
    public static func recommendedPace(trends: [OverloadTrend], exerciseIDs: Set<UUID> = []) -> PaceRecommendation {
        let measured = trends.filter { $0.recentWeeklyE1RMs.count >= 4 && ($0.recentWeeklyE1RMs.last?.e1rm ?? 0) > 0 }
        let chosen = measured.filter { exerciseIDs.contains($0.exerciseId) }
        let gains = (chosen.isEmpty ? measured : chosen)
            .map { $0.slopePerWeek / ($0.recentWeeklyE1RMs.last?.e1rm ?? 1) }.sorted()
        guard !gains.isEmpty else { return .init(pace: .standard, weeklyGain: nil, liftCount: 0) }
        let median = gains.count.isMultiple(of: 2) ? (gains[gains.count / 2 - 1] + gains[gains.count / 2]) / 2 : gains[gains.count / 2]
        return .init(pace: PlanPace.suited(toWeeklyGain: median), weeklyGain: median, liftCount: gains.count)
    }
}
