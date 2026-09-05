import Foundation

/// Detects when the user should take a deload week.
/// Stateless: takes computed outputs from other services as input.
///
/// Design (deliberately conservative — the old version fired on any single
/// trigger and pinned a permanent recommendation for anyone who trained
/// consistently for more than six weeks):
/// - Three *primary* triggers: effort creep, performance decline, high ACWR.
/// - `overdue` is a modifier: it adds at most +0.15 when a primary trigger is
///   present, and only stands alone after ≥10 calendar weeks with load
///   trending above baseline.
/// - A recommendation fires when urgency ≥ 0.35 or two primary triggers agree.
/// - Deload sessions and today's just-finished workout are excluded from the
///   creep windows so deload → normal → normal never looks like creep.
public enum DeloadDetectionService {

    // Tunables
    public static let fireUrgency = 0.35
    public static let minimumSessions = 6
    public static let creepWindowSessions = 6
    public static let creepMinimumSessions = 3
    public static let creepMinimumSpanDays = 7.0
    public static let effortRiseThreshold = 0.05
    public static let rpeRiseThreshold = 0.75
    public static let declineMinimumExercises = 2
    public static let declineRatioThreshold = 0.4
    public static let highACWRThreshold = 1.4
    public static let overdueModifierWeeks = 6
    public static let overdueStandaloneWeeks = 10
    public static let overdueStandaloneMinACWR = 1.05

    /// Intermediate result (exposed for tests): every signal with its weight,
    /// before the fire threshold is applied.
    struct Analysis {
        var triggers: [DeloadSignal] = []
        var weights: [DeloadSignal: Double] = [:]
        var weeksSinceDeload: Int = 0

        var urgency: Double { weights.values.reduce(0, +) }
        var primaryTriggers: [DeloadSignal] { triggers.filter(\.isPrimary) }
        var fires: Bool { urgency >= fireUrgency - 1e-9 || primaryTriggers.count >= 2 }
    }

    /// Detect whether a deload is recommended. Returns nil when the signals do
    /// not clear the fire threshold.
    public static func detectDeload(
        bodyWeightKg: Double,
        workouts: [Workout],
        overloadTrends: [OverloadTrend],
        trainingLoad: TrainingLoad?,
        bestE1RM: [UUID: Double],
        now: Date = Date(),
        calendar: Calendar = .mondayStart
    ) -> DeloadRecommendation? {
        guard let analysis = analyze(
            bodyWeightKg: bodyWeightKg, workouts: workouts, overloadTrends: overloadTrends,
            trainingLoad: trainingLoad, bestE1RM: bestE1RM, now: now, calendar: calendar
        ), analysis.fires else { return nil }

        let urgency = min(analysis.urgency, 1.0)
        return DeloadRecommendation(
            urgencyScore: urgency,
            triggers: analysis.triggers,
            weeksSinceLastDeload: analysis.weeksSinceDeload,
            suggestedAction: suggestedAction(triggers: analysis.triggers, urgency: urgency, weeksSinceDeload: analysis.weeksSinceDeload)
        )
    }

    static func analyze(
        bodyWeightKg: Double,
        workouts: [Workout],
        overloadTrends: [OverloadTrend],
        trainingLoad: TrainingLoad?,
        bestE1RM: [UUID: Double],
        now: Date = Date(),
        calendar: Calendar = .mondayStart
    ) -> Analysis? {
        let completed = workouts
            .filter { $0.completedAt != nil }
            .sorted { $0.trainingDate < $1.trainingDate }
        guard completed.count >= minimumSessions else { return nil }

        // Creep windows: normal sessions only, and never the session finished today
        // (one hard session is not a trend).
        let history = completed.filter { !$0.isDeload && !calendar.isDate($0.trainingDate, inSameDayAs: now) }
        let window = Array(history.suffix(creepWindowSessions))

        var analysis = Analysis()

        // 1. Effort creep (effort ratio or RPE rising while e1RM is flat).
        if let magnitude = detectEffortCreep(window: window, bestE1RM: bestE1RM, bodyWeightKg: bodyWeightKg) {
            analysis.triggers.append(.effortCreep)
            analysis.weights[.effortCreep] = 0.2 * magnitude
        }

        // 2. Performance decline: ≥2 exercises regressing and ≥40% of tracked lifts.
        let regressing = overloadTrends.filter { $0.trendStatus == .regressing }.count
        if !overloadTrends.isEmpty, regressing >= declineMinimumExercises {
            let ratio = Double(regressing) / Double(overloadTrends.count)
            if ratio >= declineRatioThreshold {
                analysis.triggers.append(.performanceDecline)
                analysis.weights[.performanceDecline] = 0.35 * ratio
            }
        }

        // 3. ACWR ≥ 1.4.
        if let load = trainingLoad, load.acwr >= highACWRThreshold {
            analysis.triggers.append(.highACWR)
            analysis.weights[.highACWR] = 0.35 * min((load.acwr - 1.3) / 0.4, 1.0)
        }

        // 4. Overdue (modifier; standalone only after a very long stretch with rising load).
        let weeks = weeksSinceDeload(workouts: completed, bestE1RM: bestE1RM, bodyWeightKg: bodyWeightKg, now: now, calendar: calendar)
        analysis.weeksSinceDeload = weeks
        if !analysis.primaryTriggers.isEmpty {
            if weeks > overdueModifierWeeks {
                analysis.triggers.append(.overdue)
                analysis.weights[.overdue] = 0.15 * min(Double(weeks - overdueModifierWeeks) / 4.0, 1.0)
            }
        } else if weeks >= overdueStandaloneWeeks, let load = trainingLoad, load.acwr >= overdueStandaloneMinACWR {
            analysis.triggers.append(.overdue)
            analysis.weights[.overdue] = 0.35 + 0.15 * min(Double(weeks - overdueStandaloneWeeks) / 3.0, 1.0)
        }

        return analysis
    }

    // MARK: - Effort creep

    /// Ordinary least squares over ≥3 non-deload sessions spanning ≥7 days.
    /// Returns a 0–1 magnitude when the effort ratio rose ≥0.05 across the window,
    /// or session RPE rose ≥0.75 while e1RM stayed flat or fell.
    static func detectEffortCreep(window: [Workout], bestE1RM: [UUID: Double], bodyWeightKg: Double) -> Double? {
        guard window.count >= creepMinimumSessions, let first = window.first, let last = window.last else { return nil }
        let spanDays = last.trainingDate.timeIntervalSince(first.trainingDate) / 86_400
        guard spanDays >= creepMinimumSpanDays else { return nil }

        let xs = window.map { $0.trainingDate.timeIntervalSince(first.trainingDate) / 86_400 }
        let efforts = window.map { meanEffortRatio(of: $0, bestE1RM: bestE1RM, bodyWeightKg: bodyWeightKg) }

        var effortRise = 0.0
        let effortPairs = zip(xs, efforts).filter { $0.1 > 0 }
        if effortPairs.count >= creepMinimumSessions,
           let fit = AnalyticsCalculations.linearRegression(xs: effortPairs.map(\.0), ys: effortPairs.map(\.1)) {
            effortRise = fit.slope * spanDays
            if effortRise >= effortRiseThreshold {
                return min(effortRise / (2 * effortRiseThreshold), 1.0)
            }
        }

        let rpePairs = zip(xs, window.map(meanRPE)).compactMap { x, rpe -> (Double, Double)? in
            guard let rpe else { return nil }
            return (x, rpe)
        }
        if rpePairs.count >= creepMinimumSessions,
           let fit = AnalyticsCalculations.linearRegression(xs: rpePairs.map(\.0), ys: rpePairs.map(\.1)) {
            let rpeRise = fit.slope * spanDays
            let e1rmFlat = effortRise < 0.02
            if rpeRise >= rpeRiseThreshold, e1rmFlat {
                return min(rpeRise / (2 * rpeRiseThreshold), 1.0)
            }
        }
        return nil
    }

    private static func meanEffortRatio(of workout: Workout, bestE1RM: [UUID: Double], bodyWeightKg: Double) -> Double {
        var ratios: [Double] = []
        for we in workout.exercises {
            guard let best = bestE1RM[we.exercise.id], best > 0 else { continue }
            let baseLoad = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
            for set in we.sets where set.isCompleted && set.setType != .warmup {
                for part in set.effectiveLoadParts(baseLoadPerRep: baseLoad) {
                    let e1rm = AnalyticsCalculations.calculateOneRM(weight: part.load, reps: min(part.reps, AnalyticsCalculations.maxRepsForE1RM))
                    ratios.append(e1rm / best)
                }
            }
        }
        return ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count)
    }

    private static func meanRPE(of workout: Workout) -> Double? {
        let rpes = workout.exercises.flatMap { we in
            we.sets.compactMap { set -> Double? in
                guard set.isCompleted, set.setType != .warmup else { return nil }
                return set.rpe
            }
        }
        guard !rpes.isEmpty else { return nil }
        return rpes.reduce(0, +) / Double(rpes.count)
    }

    // MARK: - Weeks since deload

    /// Complete Monday-start calendar weeks since the last "reset" week: a week
    /// with a tagged deload, an untrained week, or a week whose load fell below
    /// 60% of the previous four weeks. The current partial week is never tested.
    static func weeksSinceDeload(
        workouts: [Workout],
        bestE1RM: [UUID: Double],
        bodyWeightKg: Double,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let currentWeekStart = calendar.weekStart(for: now)
        var loadByWeek: [Date: Double] = [:]
        var deloadWeeks: Set<Date> = []

        for workout in workouts {
            let weekStart = calendar.weekStart(for: workout.trainingDate)
            guard weekStart < currentWeekStart else { continue }
            var sessionLoad = 0.0
            for we in workout.exercises {
                let base = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                for set in we.sets {
                    sessionLoad += AnalyticsCalculations.setIWV(for: set, bestE1RM: bestE1RM[we.exercise.id], baseLoadPerRep: base)
                }
            }
            loadByWeek[weekStart, default: 0] += sessionLoad
            if workout.isDeload { deloadWeeks.insert(weekStart) }
        }

        guard let firstWeek = loadByWeek.keys.min() else { return 0 }

        // Walk every calendar week from the first trained week to the last complete week.
        var weeks: [(start: Date, load: Double)] = []
        var cursor = firstWeek
        while cursor < currentWeekStart {
            weeks.append((cursor, loadByWeek[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard !weeks.isEmpty else { return 0 }

        var lastResetIndex: Int? = nil
        for (i, week) in weeks.enumerated() {
            if deloadWeeks.contains(week.start) || week.load <= 0 {
                lastResetIndex = i
                continue
            }
            if i >= 4 {
                let avg = weeks[(i - 4)..<i].map(\.load).reduce(0, +) / 4.0
                if avg > 0, week.load < avg * 0.6 {
                    lastResetIndex = i
                }
            }
        }

        if let lastResetIndex {
            return weeks.count - 1 - lastResetIndex
        }
        return weeks.count
    }

    // MARK: - Action copy

    private static func suggestedAction(triggers: [DeloadSignal], urgency: Double, weeksSinceDeload: Int) -> String {
        if urgency >= 0.6 {
            return "Take a full deload week: cut volume by 40-50% and intensity by 10-15%"
        } else if triggers.contains(.highACWR) {
            return "Reduce this week's volume by about 30% to bring load back toward baseline"
        } else if triggers.contains(.performanceDecline) {
            return "Take a lighter week: same lifts, 10-15% less weight, focus on technique"
        } else if triggers.contains(.effortCreep) {
            return "Effort is rising faster than performance. Keep loads flat or slightly lower this week"
        } else {
            return "It has been \(weeksSinceDeload) weeks since your last lighter week. Plan a deload within the next 1-2 weeks"
        }
    }
}
