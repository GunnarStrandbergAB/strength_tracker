import Foundation

// MARK: - Supporting Types

/// A proposed plan adjustment with priority and reasoning.
public struct ProposedAdjustment: Identifiable, Sendable {
    public let id: UUID
    public let adjustment: PlanAdjustment
    public let priority: Int  // 1 = highest
    public let reasoning: String

    public init(
        id: UUID = UUID(),
        adjustment: PlanAdjustment,
        priority: Int,
        reasoning: String
    ) {
        self.id = id
        self.adjustment = adjustment
        self.priority = priority
        self.reasoning = reasoning
    }
}

/// Internal report collecting signals from workout analysis.
public struct InsightReport: Sendable {
    public var deloadSignals: [DeloadSignal]
    public var plateauSignals: [PlateauSignal]
    public var regressionSignals: [RegressionSignal]
    public var subjectiveSignals: SubjectiveSignals?  // m12: v3 extension

    /// m12: Signals derived from workout note NLP analysis (Apple Intelligence).
    public struct SubjectiveSignals: Sendable {
        public let painReported: Bool
        public let fatigueLevel: Double?  // 0-1
        public let motivationLevel: Double?  // 0-1
        public let sleepQuality: Double?  // 0-1

        public init(
            painReported: Bool = false,
            fatigueLevel: Double? = nil,
            motivationLevel: Double? = nil,
            sleepQuality: Double? = nil
        ) {
            self.painReported = painReported
            self.fatigueLevel = fatigueLevel
            self.motivationLevel = motivationLevel
            self.sleepQuality = sleepQuality
        }
    }

    public struct DeloadSignal: Sendable {
        public let source: DeloadTrigger
        public let severity: Double  // 0-1
        public let daysSinceLastWorkout: Int?  // M4: for detraining % mapping

        public init(source: DeloadTrigger, severity: Double, daysSinceLastWorkout: Int? = nil) {
            self.source = source
            self.severity = severity
            self.daysSinceLastWorkout = daysSinceLastWorkout
        }

        /// M4: Maps detraining tier to spec-required intensity reduction percentage.
        /// 10-21 days -> 5%, 21-42 days -> 10%, 42+ days -> 15%
        public var reductionPercent: Double {
            guard let days = daysSinceLastWorkout else { return 0 }
            switch days {
            case 10..<21: return 0.05
            case 21..<42: return 0.10
            case 42...: return 0.15
            default: return 0
            }
        }
    }

    public struct PlateauSignal: Sendable {
        public let exerciseId: UUID
        public let exerciseName: String
        public let weeksStalled: Int
        public let suggestedSwapId: UUID?       // m10: v3 spec fields
        public let suggestedSwapName: String?   // m10: v3 spec fields

        public init(
            exerciseId: UUID,
            exerciseName: String,
            weeksStalled: Int,
            suggestedSwapId: UUID? = nil,
            suggestedSwapName: String? = nil
        ) {
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.weeksStalled = weeksStalled
            self.suggestedSwapId = suggestedSwapId
            self.suggestedSwapName = suggestedSwapName
        }
    }

    public struct RegressionSignal: Sendable {
        public let exerciseId: UUID
        public let exerciseName: String
        public let consecutiveMisses: Int

        public init(exerciseId: UUID, exerciseName: String, consecutiveMisses: Int) {
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.consecutiveMisses = consecutiveMisses
        }
    }

    public init(
        deloadSignals: [DeloadSignal] = [],
        plateauSignals: [PlateauSignal] = [],
        regressionSignals: [RegressionSignal] = [],
        subjectiveSignals: SubjectiveSignals? = nil
    ) {
        self.deloadSignals = deloadSignals
        self.plateauSignals = plateauSignals
        self.regressionSignals = regressionSignals
        self.subjectiveSignals = subjectiveSignals
    }
}

// MARK: - AdaptiveAdjustmentService

/// Analyzes plan state and recent workouts to propose adaptive adjustments.
/// Detects detraining gaps, beginner regression, multi-signal deload triggers,
/// and performance decline, then arbitrates into prioritized proposals.
@MainActor
public final class AdaptiveAdjustmentService: Sendable {
    private let workoutRepository: any WorkoutRepository

    private let userPreferencesService: UserPreferencesService?

    private let bodyWeightProvider: BodyWeightProvider?

    public init(workoutRepository: any WorkoutRepository, userPreferencesService: UserPreferencesService? = nil, bodyWeightProvider: BodyWeightProvider? = nil) {
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
        self.bodyWeightProvider = bodyWeightProvider
    }

    private var bodyWeightKg: Double {
        bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    // MARK: - Public API

    /// Analyze plan state and propose adjustments.
    /// - `verdict`: the shared coach verdict. A deload proposal needs either a
    ///   deload verdict or two distinct signal sources, and is never raised
    ///   during a week that already contains a deload session.
    public func analyzeAndPropose(
        plan: ProgressionPlan,
        recentWorkouts: [Workout],
        verdict: TrainingVerdict? = nil,
        now: Date = Date()
    ) async throws -> [ProposedAdjustment] {
        let insights = collectInsights(plan: plan, recentWorkouts: recentWorkouts)
        return arbitrate(insights: insights, plan: plan, verdict: verdict, recentWorkouts: recentWorkouts, now: now)
    }

    // MARK: - Insight Collection

    /// Collects signals from workout data and plan state.
    /// - Parameter subjectiveSignals: M13 — Optional signals from Apple Intelligence workout note analysis.
    internal func collectInsights(
        plan: ProgressionPlan,
        recentWorkouts: [Workout],
        subjectiveSignals: InsightReport.SubjectiveSignals? = nil
    ) -> InsightReport {
        var report = InsightReport()
        report.subjectiveSignals = subjectiveSignals

        // Detraining detection
        detectDetraining(recentWorkouts: recentWorkouts, report: &report)

        // Beginner regression detection (Review Fix #10)
        if plan.trainingStatus == .beginner {
            detectBeginnerRegression(plan: plan, recentWorkouts: recentWorkouts, report: &report)
        }

        // Performance decline detection
        detectPerformanceDecline(plan: plan, recentWorkouts: recentWorkouts, report: &report)

        return report
    }

    // MARK: - Detraining Detection

    /// Check gap since last workout.
    /// 10-21 days -> severity 0.3
    /// 21-42 days -> severity 0.6
    /// 42+ days -> severity 0.9
    ///
    /// - Parameter referenceDate: m13 — Injectable reference date for testability (defaults to `Date()`).
    private func detectDetraining(
        recentWorkouts: [Workout],
        report: inout InsightReport,
        referenceDate: Date = Date()
    ) {
        let completedWorkouts = recentWorkouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }

        guard let lastWorkout = completedWorkouts.first,
              let lastDate = lastWorkout.completedAt else {
            return
        }

        let daysSinceLastWorkout = Calendar.current.dateComponents(
            [.day], from: lastDate, to: referenceDate
        ).day ?? 0

        let severity: Double?
        switch daysSinceLastWorkout {
        case 10..<21:
            severity = 0.3
        case 21..<42:
            severity = 0.6
        case 42...:
            severity = 0.9
        default:
            severity = nil
        }

        if let severity = severity {
            report.deloadSignals.append(
                InsightReport.DeloadSignal(
                    source: .reactiveRecovery,
                    severity: severity,
                    daysSinceLastWorkout: daysSinceLastWorkout
                )
            )
        }
    }

    // MARK: - Beginner Regression Detection (Review Fix #10)

    /// For beginners: check consecutive sessions where actual reps < target reps for same exercise.
    /// 2 misses -> loadDecrease 5%. 3+ -> loadDecrease 10% + repeat week.
    private func detectBeginnerRegression(
        plan: ProgressionPlan,
        recentWorkouts: [Workout],
        report: inout InsightReport
    ) {
        // Sort workouts newest first
        let sortedWorkouts = recentWorkouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }

        for planExercise in plan.exercises {
            var consecutiveMisses = 0

            for workout in sortedWorkouts {
                // Compare against the target reps of the SESSION this workout completed.
                // Periodized programs lower target reps week over week, so comparing
                // against a single plan-wide target flags normal rep decreases as misses.
                // Ad-hoc workouts (no matching planned session) have no target to miss — skip.
                guard let targetReps = findTargetReps(
                    for: planExercise, completedWorkoutId: workout.id, in: plan
                ) else { continue }

                let exerciseSets = workout.exercises
                    .filter { $0.exercise.id == planExercise.exerciseId }
                    .flatMap(\.sets)
                    .filter { $0.isCompleted && $0.setType != .warmup }

                guard !exerciseSets.isEmpty else { continue }

                let allMissed = exerciseSets.allSatisfy { set in
                    guard let reps = set.reps else { return true }
                    return reps < targetReps
                }

                if allMissed {
                    consecutiveMisses += 1
                } else {
                    break
                }
            }

            if consecutiveMisses >= 2 {
                report.regressionSignals.append(
                    InsightReport.RegressionSignal(
                        exerciseId: planExercise.exerciseId,
                        exerciseName: planExercise.exerciseName,
                        consecutiveMisses: consecutiveMisses
                    )
                )
            }
        }
    }

    /// Target reps for a plan exercise in the specific session a workout completed.
    /// Returns nil for workouts that don't correspond to a planned session.
    private func findTargetReps(
        for planExercise: PlanExercise,
        completedWorkoutId: UUID,
        in plan: ProgressionPlan
    ) -> Int? {
        for block in plan.blocks {
            for week in block.weeks {
                for session in week.sessions where session.completedWorkoutId == completedWorkoutId {
                    if let planned = session.plannedExercises.first(where: { $0.planExerciseId == planExercise.id }) {
                        return planned.targetReps
                    }
                    return nil
                }
            }
        }
        return nil
    }

    // MARK: - Performance Decline Detection

    /// Recent 1RM estimate more than 5% below the plan's current 1RM. Emits ONE
    /// signal, and only when at least two exercises declined or one exercise has
    /// been below for two consecutive sessions — a single bad day is not a
    /// systemic signal. Deload sessions are ignored.
    static let declineThreshold = 0.05

    private func detectPerformanceDecline(
        plan: ProgressionPlan,
        recentWorkouts: [Workout],
        report: inout InsightReport
    ) {
        let sessions = recentWorkouts
            .filter { $0.completedAt != nil && !$0.isDeload }
            .sorted { $0.trainingDate > $1.trainingDate }   // newest first

        var decliningExercises = 0
        var sustainedDecline = false
        var worstDecline = 0.0

        for planExercise in plan.exercises where planExercise.current1RM > 0 {
            // Per-session best e1RM for this exercise, newest first.
            let perSession: [Double] = sessions.compactMap { workout in
                let estimates = workout.exercises
                    .filter { $0.exercise.id == planExercise.exerciseId }
                    .compactMap { we -> Double? in
                        let baseLoad = we.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                        return AnalyticsCalculations.bestE1RM(in: we.sets, baseLoadPerRep: baseLoad)
                    }
                return estimates.max()
            }
            guard let latest = perSession.first else { continue }

            let declineOf = { (e1rm: Double) -> Double in
                (planExercise.current1RM - e1rm) / planExercise.current1RM
            }
            let latestDecline = declineOf(latest)
            guard latestDecline > Self.declineThreshold else { continue }

            decliningExercises += 1
            worstDecline = max(worstDecline, latestDecline)
            if perSession.count >= 2, declineOf(perSession[1]) > Self.declineThreshold {
                sustainedDecline = true
            }
        }

        guard decliningExercises >= 2 || sustainedDecline else { return }
        report.deloadSignals.append(
            InsightReport.DeloadSignal(
                source: .reactivePerformance,
                severity: min(1.0, worstDecline * 2)
            )
        )
    }

    /// Best recent 1RM estimate for an exercise (app-wide formula: warm-ups and
    /// incomplete sets ignored, every drop segment considered, reps clamped to 15).
    private func estimateCurrent1RM(exerciseId: UUID, from workouts: [Workout]) -> Double? {
        var best: Double?
        for workout in workouts {
            for workoutExercise in workout.exercises where workoutExercise.exercise.id == exerciseId {
                let baseLoad = workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                if let estimate = AnalyticsCalculations.bestE1RM(in: workoutExercise.sets, baseLoadPerRep: baseLoad) {
                    best = max(best ?? 0, estimate)
                }
            }
        }
        return best
    }

    // MARK: - Adjustment Arbiter (Review Fix #11)

    /// Arbitrates collected insights into prioritized proposals.
    /// - Sort signals by severity/priority
    /// - Remove contradictions (can't increase AND decrease same exercise)
    /// - Cap at max 3 proposals
    /// - Deload proposals are highest priority, exercise swaps next, load adjustments last
    private func arbitrate(
        insights: InsightReport,
        plan: ProgressionPlan,
        verdict: TrainingVerdict? = nil,
        recentWorkouts: [Workout] = [],
        now: Date = Date()
    ) -> [ProposedAdjustment] {
        var proposals: [ProposedAdjustment] = []

        // M4: Detraining-specific intensity reduction proposals
        let detrainingSignals = insights.deloadSignals.filter { $0.daysSinceLastWorkout != nil && $0.reductionPercent > 0 }
        for signal in detrainingSignals {
            let pct = Int(signal.reductionPercent * 100)
            let days = signal.daysSinceLastWorkout ?? 0
            var detrainAdj = PlanAdjustment(
                adjustmentType: .loadDecrease,
                trigger: .recoverySignal,
                description: "Detraining detected (\(days) days gap). Intensity reduced by \(pct)%.",
                affectedBlockIds: plan.currentBlock.map { [$0.id] } ?? [],
                newValues: ["reductionPercent": String(pct)]
            )
            // M4: 42+ day tier gets repeat-block
            if days >= 42 {
                detrainAdj.newValues["repeatBlock"] = "true"
            }
            proposals.append(ProposedAdjustment(
                adjustment: detrainAdj,
                priority: 1,
                reasoning: "Detraining gap of \(days) days. Recommending \(pct)% intensity reduction\(days >= 42 ? " with repeat-block" : "")."
            ))
        }

        // Deload proposal: the verdict or two DISTINCT signal sources, never during
        // a week that already holds a deload session (or an active deload verdict).
        let distinctSources = Set(insights.deloadSignals.map(\.source))
        let verdictSaysDeload = verdict?.kind == .deload && !(verdict?.isActiveDeload ?? false)
        let weekStart = Calendar.mondayStart.weekStart(for: now)
        let deloadThisWeek = recentWorkouts.contains { $0.isDeload && $0.trainingDate >= weekStart }
            || (verdict?.isActiveDeload ?? false)
        let hasSignal = !insights.deloadSignals.isEmpty
        if !deloadThisWeek, (distinctSources.count >= 2 || (verdictSaysDeload && hasSignal)) {
            let maxSeverity = insights.deloadSignals.map(\.severity).max() ?? 0.5
            let reason: String
            if verdictSaysDeload {
                reason = "Coach verdict is deload" + (distinctSources.count >= 2 ? " and multiple deload signals agree" : "")
            } else {
                reason = "Multiple deload signals detected (severity up to \(String(format: "%.1f", maxSeverity)))"
            }
            let deloadAdj = PlanAdjustment(
                adjustmentType: .deload,
                trigger: .recoverySignal,
                description: "Deload triggered (\(distinctSources.count) signal source\(distinctSources.count == 1 ? "" : "s")\(verdictSaysDeload ? ", coach verdict: deload" : "")). Volume reduced by 50% for 1 week.",
                affectedBlockIds: plan.currentBlock.map { [$0.id] } ?? []
            )
            proposals.append(ProposedAdjustment(
                adjustment: deloadAdj,
                priority: 1,
                reasoning: "\(reason). Recommending volume reduction to 50% for 1 recovery week."
            ))
        }

        // Beginner regression proposals
        var affectedExerciseIds = Set<UUID>()
        for regression in insights.regressionSignals {
            let decreasePercent: Double
            let description: String
            if regression.consecutiveMisses >= 3 {
                decreasePercent = 0.10
                description = "Load decrease 10% + repeat week for \(regression.exerciseName) (\(regression.consecutiveMisses) consecutive misses)"
            } else {
                decreasePercent = 0.05
                description = "Load decrease 5% for \(regression.exerciseName) (\(regression.consecutiveMisses) consecutive misses)"
            }

            let adj = PlanAdjustment(
                adjustmentType: .loadDecrease,
                trigger: .performanceDecline,
                description: description,
                affectedExerciseIds: [regression.exerciseId],
                newValues: ["decreasePercent": String(format: "%.0f", decreasePercent * 100)]
            )
            proposals.append(ProposedAdjustment(
                adjustment: adj,
                priority: 3,
                reasoning: "Beginner regression detected: \(regression.consecutiveMisses) consecutive sessions below target reps for \(regression.exerciseName)."
            ))

            // M5: 3+ misses also generates repeat-week adjustment
            if regression.consecutiveMisses >= 3 {
                let repeatAdj = PlanAdjustment(
                    adjustmentType: .blockExtension,
                    trigger: .performanceDecline,
                    description: "Repeat current week for \(regression.exerciseName) due to \(regression.consecutiveMisses) consecutive misses",
                    affectedExerciseIds: [regression.exerciseId],
                    affectedBlockIds: plan.currentBlock.map { [$0.id] } ?? [],
                    newValues: ["repeatWeek": "true"]
                )
                proposals.append(ProposedAdjustment(
                    adjustment: repeatAdj,
                    priority: 2,
                    reasoning: "Beginner 3+ consecutive misses warrants repeating the current week at reduced load."
                ))
            }
            affectedExerciseIds.insert(regression.exerciseId)
        }

        // Remove contradictions: can't increase AND decrease same exercise
        // (Since we only generate decreases currently, this is a safeguard for future)
        proposals = removeContradictions(proposals)

        // Sort by priority (lower = higher priority); deloads win ties so they
        // always lead within a priority tier (deload proposals are highest priority)
        proposals.sort {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.adjustment.adjustmentType == .deload
                && $1.adjustment.adjustmentType != .deload
        }

        // Cap at max 3
        return Array(proposals.prefix(3))
    }

    /// Removes contradictory proposals: an increase and a decrease on the same
    /// exercise, or any increase while a block-wide deload/decrease stands.
    func removeContradictions(_ proposals: [ProposedAdjustment]) -> [ProposedAdjustment] {
        var exerciseActions: [UUID: AdjustmentType] = [:]
        var result: [ProposedAdjustment] = []
        var blockWideDecrease = false

        // First pass: deloads always win (priority 1)
        let sorted = proposals.sorted { $0.priority < $1.priority }

        for proposal in sorted {
            let exerciseIds = proposal.adjustment.affectedExerciseIds
            let adjType = proposal.adjustment.adjustmentType

            // Check for contradictions
            var hasContradiction = false
            if blockWideDecrease, adjType == .loadIncrease {
                hasContradiction = true
            }
            for exerciseId in exerciseIds {
                if let existing = exerciseActions[exerciseId] {
                    if isContradiction(existing, adjType) {
                        hasContradiction = true
                        break
                    }
                }
            }

            if !hasContradiction {
                result.append(proposal)
                for exerciseId in exerciseIds {
                    exerciseActions[exerciseId] = adjType
                }
                if exerciseIds.isEmpty, adjType == .deload || adjType == .loadDecrease {
                    blockWideDecrease = true
                }
            }
        }

        return result
    }

    /// Two adjustment types contradict if one is an increase and the other a decrease.
    private func isContradiction(_ a: AdjustmentType, _ b: AdjustmentType) -> Bool {
        let increases: Set<AdjustmentType> = [.loadIncrease]
        let decreases: Set<AdjustmentType> = [.loadDecrease, .deload]
        return (increases.contains(a) && decreases.contains(b))
            || (decreases.contains(a) && increases.contains(b))
    }
}
