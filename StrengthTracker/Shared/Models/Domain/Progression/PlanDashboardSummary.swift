import Foundation

/// What the dashboard shows of a running plan: this week day by day, what comes next,
/// and how far the lifts have come. Derived from the plan alone, for one moment in time.
public struct PlanDashboardSummary: Equatable, Sendable {
    public enum DayStatus: Equatable, Sendable {
        /// Nothing planned.
        case rest
        /// A session later this week.
        case planned
        /// A session planned for today, not done yet.
        case today
        case done
        /// An open session whose day has passed.
        case missed
        case skipped
    }

    /// One weekday of the current Monday–Sunday week.
    public struct Day: Equatable, Sendable, Identifiable {
        /// 0 is Monday.
        public let index: Int
        public let status: DayStatus
        public let isToday: Bool
        public let isDeload: Bool
        public let sessionID: UUID?
        /// The logged workout of a session that is done.
        public let workoutID: UUID?
        public var id: Int { index }
    }

    /// Where a lift started in the plan and what it asks for now.
    public struct Lift: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let start: ProgressionTarget
        public let now: ProgressionTarget
        /// True when the numbers are an estimated 1RM (a percentage-wave lift) rather
        /// than a working target.
        public let isEstimatedMax: Bool
        public var hasMoved: Bool { now.isAbove(start) }
    }

    public let days: [Day]
    public let doneThisWeek: Int
    public let plannedThisWeek: Int
    /// Open sessions whose day has passed, anywhere in the plan.
    public let overdueCount: Int
    /// The open session that comes first; an overdue one before a later one.
    public let next: PlannedSession?
    public let nextIsOverdue: Bool
    public let week: Int?
    public let totalWeeks: Int
    public let isDeloadWeek: Bool
    /// Calendar weeks until the next week with a deload session; nil when none is left.
    public let weeksUntilDeload: Int?
    public let sessionsDone: Int
    public let sessionsTotal: Int
    public let lifts: [Lift]
    /// The coach suggests a deload, so rule targets repeat instead of rising.
    public let targetsOnHold: Bool

    public init(plan: ProgressionPlan, progress: PlanProgress? = nil, now: Date = Date(), liftLimit: Int = 3) {
        let calendar = CalendarWeekBucketer.mondayCalendar
        let today = calendar.startOfDay(for: now)
        let weekStart = CalendarWeekBucketer.weekStart(of: now)
        let sessions = plan.blocks.flatMap(\.weeks).flatMap(\.sessions).filter { !$0.isOmitted }
        func day(of session: PlannedSession) -> Date? { (session.completedAt ?? session.scheduledDate).map(calendar.startOfDay) }
        func index(of session: PlannedSession) -> Int? {
            guard let date = day(of: session), let offset = calendar.dateComponents([.day], from: weekStart, to: date).day,
                  (0..<7).contains(offset) else { return nil }
            return offset
        }
        func status(of session: PlannedSession) -> DayStatus {
            if session.isCompleted { return .done }
            if session.isSkipped { return .skipped }
            guard let date = day(of: session) else { return .planned }
            return date < today ? .missed : (date == today ? .today : .planned)
        }
        // Two sessions on one day: the circle shows the one that matters most right now.
        let rank: [DayStatus: Int] = [.today: 5, .done: 4, .planned: 3, .missed: 2, .skipped: 1, .rest: 0]
        let thisWeek = sessions.filter { index(of: $0) != nil }
        let todayIndex = calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0
        days = (0..<7).map { offset in
            let onDay = thisWeek.filter { index(of: $0) == offset }
            let shown = onDay.max { (rank[status(of: $0)] ?? 0) < (rank[status(of: $1)] ?? 0) }
            return Day(index: offset, status: shown.map(status) ?? .rest, isToday: offset == todayIndex,
                isDeload: shown?.isDeload ?? false, sessionID: shown?.id, workoutID: shown?.completedWorkoutId)
        }
        doneThisWeek = thisWeek.filter(\.isCompleted).count
        plannedThisWeek = thisWeek.count

        let open = sessions.filter { !$0.isClosed }
        overdueCount = open.filter { ($0.scheduledDate.map(calendar.startOfDay) ?? .distantFuture) < today }.count
        next = open.min { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
        nextIsOverdue = (next?.scheduledDate.map(calendar.startOfDay) ?? .distantFuture) < today

        week = plan.currentWeek(asOf: now)?.absoluteWeekNumber
        totalWeeks = plan.totalWeeks
        isDeloadWeek = thisWeek.contains(where: \.isDeload)
        let nextDeload = sessions.filter { $0.isDeload && !$0.isClosed }.compactMap(\.scheduledDate)
            .map { CalendarWeekBucketer.weekStart(of: $0) }.filter { $0 > weekStart }.min()
        weeksUntilDeload = nextDeload.flatMap { calendar.dateComponents([.day], from: weekStart, to: $0).day }.map { $0 / 7 }
        sessionsDone = sessions.filter(\.isCompleted).count
        sessionsTotal = sessions.count

        lifts = plan.exercises.sorted { $0.order < $1.order }.compactMap { exercise -> Lift? in
            if let rule = exercise.progression?.normalized {
                let start = ProgressionTarget(weightKg: rule.startWeightKg, reps: rule.startReps)
                let current = ProgressionRuleEngine.currentState(of: exercise, in: plan)?.state.target ?? start
                return Lift(id: exercise.id, name: exercise.exerciseName, start: start, now: current, isEstimatedMax: false)
            }
            // A wave lift is followed through its estimated 1RM; one without a baseline has nothing to show.
            guard exercise.estimated1RM > 0 else { return nil }
            let measured = progress?.exerciseProgress.first { $0.planExerciseId == exercise.id }
            return Lift(id: exercise.id, name: exercise.exerciseName,
                start: .init(weightKg: measured?.starting1RM ?? exercise.estimated1RM, reps: 1),
                now: .init(weightKg: measured?.current1RM ?? exercise.current1RM, reps: 1), isEstimatedMax: true)
        }.prefix(max(0, liftLimit)).map { $0 }
        targetsOnHold = plan.configuration?.holdIncreases == true
    }
}

/// How the plan's most recently finished session went against its targets, exercise by
/// exercise. Read from the logged workout, so it covers every exercise counted in reps,
/// whether or not a progression rule drives it.
public struct PlanSessionReview: Equatable, Sendable {
    public struct Line: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let sets: Int
        public let target: ProgressionTarget
        /// What was done at the working weight; nil when the exercise was left out.
        public let done: ProgressionOutcome?

        /// Every planned set, at the target weight or more, with no set short of the rep target.
        public var isHit: Bool {
            guard let done else { return false }
            return done.completedAllSets && done.lowestReps >= target.reps && done.weightKg >= target.weightKg - 0.26
        }
    }

    public let sessionID: UUID
    public let workoutID: UUID
    public let name: String
    public let date: Date?
    public let isDeload: Bool
    public let lines: [Line]
    public var hitCount: Int { lines.filter(\.isHit).count }

    /// Nil when no session is finished yet, its workout is gone, or it had no rep targets.
    public init?(plan: ProgressionPlan, workouts: [Workout]) {
        let finished = plan.blocks.flatMap(\.weeks).flatMap(\.sessions).filter(\.isCompleted)
        guard let session = finished.max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }),
              let workout = workouts.first(where: { $0.id == session.completedWorkoutId }) else { return nil }
        let lines = session.plannedExercises.filter { $0.targetReps > 0 }.map { planned in
            let logged = workout.exercises.first { $0.exercise.id == planned.exerciseId }
            return Line(id: planned.id, name: planned.exerciseName, sets: planned.sets,
                target: .init(weightKg: planned.targetWeight, reps: planned.targetReps),
                done: logged.flatMap { ProgressionRuleEngine.outcome(planned: planned, performed: $0.sets) })
        }
        guard !lines.isEmpty else { return nil }
        sessionID = session.id
        workoutID = workout.id
        name = session.displayLabel
        date = session.completedAt ?? session.scheduledDate
        isDeload = session.isDeload
        self.lines = lines
    }
}
