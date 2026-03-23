import Foundation

/// Detects when the user should take a deload week.
/// Stateless: takes computed outputs from other services as input.
public enum DeloadDetectionService {

    /// Detect whether a deload is recommended.
    /// Returns nil if urgency < 0.15 (no actionable fatigue).
    public static func detectDeload(
        workouts: [Workout],
        overloadTrends: [OverloadTrend],
        trainingLoad: TrainingLoad?,
        bestE1RM: [UUID: Double]
    ) -> DeloadRecommendation? {
        let completed = workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }

        guard completed.count >= 6 else { return nil }

        var triggers: [DeloadSignal] = []
        var urgencyWeights: [Double] = []

        // 1. Performance decline: e1RM dropping in 40%+ exercises over last 2 sessions
        let regressingCount = overloadTrends.filter { $0.trendStatus == .regressing }.count
        if !overloadTrends.isEmpty {
            let ratio = Double(regressingCount) / Double(overloadTrends.count)
            if ratio >= 0.4 {
                triggers.append(.performanceDecline)
                urgencyWeights.append(0.3 * ratio)
            }
        }

        // 2. Intensity creep: effort ratios increasing over last 3 sessions
        if detectIntensityCreep(workouts: Array(completed.suffix(5)), bestE1RM: bestE1RM) {
            triggers.append(.intensityCreep)
            urgencyWeights.append(0.2)
        }

        // 3. ACWR > 1.4 sustained
        if let load = trainingLoad, load.acwr > 1.4 {
            triggers.append(.highACWR)
            urgencyWeights.append(0.3 * min((load.acwr - 1.3) / 0.5, 1.0))
        }

        // 4. Overdue: >6 weeks since volume dropped <60% of average
        let weeksSinceDeload = detectWeeksSinceDeload(workouts: completed, bestE1RM: bestE1RM)
        if weeksSinceDeload > 6 {
            triggers.append(.overdue)
            urgencyWeights.append(0.2 * min(Double(weeksSinceDeload - 6) / 4.0, 1.0))
        }

        // 5. RPE creep: average session RPE trending up over 3+ sessions
        if let rpeUrgency = detectRPECreep(workouts: Array(completed.suffix(5))) {
            triggers.append(.rpeCreep)
            urgencyWeights.append(rpeUrgency)
        }

        let urgency = urgencyWeights.reduce(0, +)
        guard urgency >= 0.15 else { return nil }

        let action = suggestedAction(triggers: triggers, urgency: urgency)

        return DeloadRecommendation(
            urgencyScore: min(urgency, 1.0),
            triggers: triggers,
            weeksSinceLastDeload: weeksSinceDeload,
            suggestedAction: action
        )
    }

    // MARK: - Private

    /// Detect if mean effort ratio is consistently increasing over last 3+ sessions.
    private static func detectIntensityCreep(workouts: [Workout], bestE1RM: [UUID: Double]) -> Bool {
        guard workouts.count >= 3 else { return false }

        let recentMeanEfforts = workouts.suffix(3).map { workout -> Double in
            var ratios: [Double] = []
            for we in workout.exercises {
                for set in we.sets {
                    guard set.isCompleted, set.setType != .warmup,
                          let weight = set.weight, weight > 0,
                          let reps = set.reps, reps > 0,
                          let best = bestE1RM[we.exercise.id], best > 0 else { continue }
                    let e1rm = AnalyticsCalculations.calculateOneRM(weight: weight, reps: min(reps, 15))
                    ratios.append(e1rm / best)
                }
            }
            return ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count)
        }

        // Check if each session has higher mean effort than the previous
        guard recentMeanEfforts.count >= 3 else { return false }
        return recentMeanEfforts[1] > recentMeanEfforts[0] && recentMeanEfforts[2] > recentMeanEfforts[1]
    }

    /// Count weeks since the last deload-like volume drop (<60% of 4-week average)
    /// or any week containing an `isDeload`-tagged workout.
    private static func detectWeeksSinceDeload(workouts: [Workout], bestE1RM: [UUID: Double]) -> Int {
        let calendar = Calendar.current
        var weeklyLoads: [(weekStart: Date, load: Double)] = []
        var weeksWithTaggedDeload: Set<Int> = []

        for workout in workouts {
            let date = workout.completedAt ?? workout.startedAt
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date

            var sessionLoad = 0.0
            for we in workout.exercises {
                for set in we.sets {
                    guard set.isCompleted, set.setType != .warmup,
                          let weight = set.weight, weight > 0,
                          let reps = set.reps, reps > 0 else { continue }
                    let pct1RM: Double
                    if let best = bestE1RM[we.exercise.id], best > 0 {
                        pct1RM = min(weight / best, 1.5)
                    } else {
                        pct1RM = 0.75
                    }
                    sessionLoad += AnalyticsCalculations.setIWV(reps: reps, pct1RM: pct1RM, rpe: set.rpe)
                }
            }

            if let idx = weeklyLoads.firstIndex(where: { calendar.isDate($0.weekStart, equalTo: weekStart, toGranularity: .weekOfYear) }) {
                weeklyLoads[idx].load += sessionLoad
                if workout.isDeload { weeksWithTaggedDeload.insert(idx) }
            } else {
                weeklyLoads.append((weekStart, sessionLoad))
                if workout.isDeload { weeksWithTaggedDeload.insert(weeklyLoads.count - 1) }
            }
        }

        weeklyLoads.sort { $0.weekStart < $1.weekStart }
        guard weeklyLoads.count >= 5 else { return weeklyLoads.count }

        // Find last week where load was <60% of rolling 4-week average
        // OR the week contains a user-tagged deload workout
        var lastDeloadWeekIndex = 0
        for i in 4..<weeklyLoads.count {
            if weeksWithTaggedDeload.contains(i) {
                lastDeloadWeekIndex = i
                continue
            }
            let avg = weeklyLoads[(i-4)..<i].map(\.load).reduce(0, +) / 4.0
            if weeklyLoads[i].load < avg * 0.6 {
                lastDeloadWeekIndex = i
            }
        }

        return weeklyLoads.count - lastDeloadWeekIndex
    }

    /// Detect if average session RPE is trending up over 3+ consecutive sessions.
    /// Returns urgency weight if RPE creep is detected, nil otherwise.
    private static func detectRPECreep(workouts: [Workout]) -> Double? {
        // Compute average RPE per session (only sessions that have RPE data)
        let sessionRPEs: [Double] = workouts.compactMap { workout -> Double? in
            let rpes = workout.exercises.flatMap { we in
                we.sets.compactMap { set -> Double? in
                    guard set.isCompleted, set.setType != .warmup else { return nil }
                    return set.rpe
                }
            }
            guard !rpes.isEmpty else { return nil }
            return rpes.reduce(0, +) / Double(rpes.count)
        }

        guard sessionRPEs.count >= 3 else { return nil }

        // Check if RPE is monotonically increasing over the last 3 sessions
        let recent = Array(sessionRPEs.suffix(3))
        let isIncreasing = recent[1] > recent[0] && recent[2] > recent[1]
        guard isIncreasing else { return nil }

        // Severity proportional to total RPE increase
        let increase = recent[2] - recent[0]
        return 0.2 * min(increase / 2.0, 1.0)
    }

    private static func suggestedAction(triggers: [DeloadSignal], urgency: Double) -> String {
        if urgency > 0.6 {
            return "Take a full deload week: reduce volume by 40-50% and intensity by 10-15%"
        } else if triggers.contains(.highACWR) {
            return "Reduce training volume this week by 30% to bring load ratio back to optimal"
        } else if triggers.contains(.performanceDecline) {
            return "Consider a lighter week focusing on technique with reduced weights"
        } else if triggers.contains(.rpeCreep) {
            return "Subjective effort is rising — consider reducing intensity before performance drops"
        } else {
            return "Monitor fatigue levels; a planned deload within 1-2 weeks is recommended"
        }
    }
}
