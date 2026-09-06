import Foundation

/// Turns the raw fatigue signals into the single `TrainingVerdict` every
/// surface consults. Precedence is fixed and documented below; hysteresis
/// keeps a deload verdict from flickering between recomputes.
@MainActor
public final class TrainingAdvisor {

    public struct Input: Sendable {
        /// Completed workouts, deloads included.
        public var workouts: [Workout]
        public var trainingLoad: TrainingLoad?
        public var overloadTrends: [OverloadTrend]
        public var deloadRecommendation: DeloadRecommendation?
        public var recoveryPatterns: [RecoveryPattern]
        public var now: Date

        public init(
            workouts: [Workout],
            trainingLoad: TrainingLoad? = nil,
            overloadTrends: [OverloadTrend] = [],
            deloadRecommendation: DeloadRecommendation? = nil,
            recoveryPatterns: [RecoveryPattern] = [],
            now: Date = Date()
        ) {
            self.workouts = workouts
            self.trainingLoad = trainingLoad
            self.overloadTrends = overloadTrends
            self.deloadRecommendation = deloadRecommendation
            self.recoveryPatterns = recoveryPatterns
            self.now = now
        }
    }

    // Tunables
    public static let activeDeloadWindowDays = 7
    public static let layoffDays = 10
    public static let deloadUrgencyThreshold = 0.5
    public static let holdUrgencyThreshold = 0.35
    public static let minimumDeloadPersistenceDays = 5
    public static let clearDaysToRelease = 2
    public static let systemicFatigueGroups = 3

    private let store: any TrainingVerdictStoring
    private let calendar: Calendar

    public init(store: any TrainingVerdictStoring, calendar: Calendar = .mondayStart) {
        self.store = store
        self.calendar = calendar
    }

    /// The most recently persisted verdict (nil before the first evaluation).
    public var lastVerdict: TrainingVerdict? { store.load()?.verdict }

    public func reset() { store.save(nil) }

    /// Evaluate the verdict. With `persist` the result is reconciled against the
    /// stored state (hysteresis) and saved; without it the raw call is returned.
    @discardableResult
    public func evaluate(_ input: Input, persist: Bool = true) -> TrainingVerdict {
        let raw = rawVerdict(for: input)
        guard persist else { return raw }
        let reconciled = reconcile(raw, with: store.load(), input: input)
        store.save(reconciled)
        return reconciled.verdict
    }

    // MARK: - Raw evaluation

    private func rawVerdict(for input: Input) -> TrainingVerdict {
        let now = input.now
        let completed = input.workouts
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }
        let latest = completed.last
        let rec = input.deloadRecommendation
        let signals = rec?.triggers ?? []
        let urgency = rec?.urgencyScore ?? 0

        func make(_ kind: TrainingVerdict.Kind, _ reasons: [String], _ action: String, active: Bool = false) -> TrainingVerdict {
            TrainingVerdict(
                kind: kind,
                urgency: urgency,
                reasons: reasons,
                signals: signals,
                action: action,
                since: now,
                computedAt: now,
                isActiveDeload: active
            )
        }

        // 1. Active deload: latest session is a recent deload → hold, no warnings.
        if let latest, latest.isDeload,
           let done = latest.completedAt,
           daysBetween(done, now) <= Self.activeDeloadWindowDays {
            return make(.hold,
                        ["Your latest session was a deload"],
                        "Keep this week light as planned. Resume normal loads once the deload week is over",
                        active: true)
        }

        // 2. Layoff: ease back in rather than chase old numbers.
        if let latest, let done = latest.completedAt, daysBetween(done, now) >= Self.layoffDays {
            let days = daysBetween(done, now)
            return make(.hold,
                        ["\(days) days since your last workout"],
                        "Ease back in: repeat your last loads for a session or two before adding weight")
        }

        // 3. Load spike far above baseline.
        if let load = input.trainingLoad, load.loadZone == .danger, (rec?.primaryTriggers.count ?? 0) < 2, urgency < Self.deloadUrgencyThreshold {
            return make(.hold,
                        ["Training load is far above your 28-day baseline (ACWR \(AnalyticsFormatting.acwr(load.acwr)))"] + reasonList(rec),
                        "Review recent load and how you feel before increasing work")
        }

        // 4. Fatigue signals strong enough for a deload.
        if let rec, rec.primaryTriggers.count >= 2 || rec.urgencyScore >= Self.deloadUrgencyThreshold {
            return make(.deload, reasonList(rec), rec.suggestedAction)
        }

        // 5. A single moderate signal → hold.
        if let rec, rec.urgencyScore >= Self.holdUrgencyThreshold {
            return make(.hold,
                        reasonList(rec),
                        "Keep loads where they are this week and see if the signal clears")
        }

        // 6. Load rising faster than baseline.
        if let load = input.trainingLoad, load.loadZone == .caution {
            return make(.hold,
                        ["Training load is rising faster than your baseline (ACWR \(AnalyticsFormatting.acwr(load.acwr)))"],
                        "Hold volume steady this week so your baseline can catch up")
        }

        // 7. Broad regression across lifts.
        let eligibleTrends = input.overloadTrends.filter { $0.trendStatus != .inactive && $0.trendStatus != .uncertain }
        let regressing = eligibleTrends.filter { $0.trendStatus == .regressing }
        if !eligibleTrends.isEmpty, regressing.count >= 2,
           Double(regressing.count) / Double(eligibleTrends.count) >= 0.5 {
            let names = regressing.prefix(3).map(\.exerciseName).joined(separator: ", ")
            return make(.hold,
                        ["\(regressing.count) of \(eligibleTrends.count) assessed lifts are regressing (\(names))"],
                        "Repeat last session's loads and focus on clean reps before pushing again")
        }

        // 8. Systemic fatigue: several groups still fatigued that were not just trained.
        let fatigued = input.recoveryPatterns.filter { $0.recoveryStatus == .fatigued && !$0.isJustTrained(asOf: now) }
        if fatigued.count >= Self.systemicFatigueGroups {
            let names = fatigued.prefix(3).map { $0.muscleGroup.capitalized }.joined(separator: ", ")
            return make(.hold,
                        ["\(fatigued.count) muscle groups are still fatigued (\(names))"],
                        "Give recovery a day or two: keep today's loads at last session's numbers")
        }

        // 9. Clear.
        var reasons: [String] = []
        if let load = input.trainingLoad {
            switch load.loadZone {
            case .underTraining: reasons.append("Training load is below your smoothed baseline")
            case .optimal: reasons.append("Training load is near your smoothed baseline")
            default: break
            }
        }
        let progressing = input.overloadTrends.filter { $0.trendStatus == .progressing }
        if !progressing.isEmpty {
            reasons.append("\(progressing.count) of \(eligibleTrends.count) assessed lifts are progressing")
        }
        if reasons.isEmpty { reasons.append("No fatigue signals") }
        return make(.progress, reasons, "Keep progressing: add weight or reps when the target reps feel solid")
    }

    private func reasonList(_ rec: DeloadRecommendation?) -> [String] {
        guard let rec else { return [] }
        var reasons = rec.triggers.map(\.displayName)
        if rec.triggers.contains(.overdue), rec.weeksSinceLastDeload > 0 {
            reasons = reasons.map {
                $0 == DeloadSignal.overdue.displayName ? "\(rec.weeksSinceLastDeload) weeks since your last lighter week" : $0
            }
        }
        return reasons
    }

    // MARK: - Hysteresis

    private func reconcile(_ raw: TrainingVerdict, with stored: TrainingVerdictState?, input: Input) -> TrainingVerdictState {
        guard let stored else {
            return TrainingVerdictState(verdict: raw)
        }
        let previous = stored.verdict
        let now = input.now

        // Same kind: carry `since`, keep clear-day bookkeeping empty.
        if raw.kind == previous.kind {
            return TrainingVerdictState(verdict: raw.carrying(since: previous.since))
        }

        // Leaving a deload verdict needs evidence: a logged deload, or two clear
        // computations on distinct days after the minimum persistence window.
        if previous.kind == .deload {
            let deloadLogged = input.workouts.contains {
                $0.isDeload && ($0.completedAt ?? .distantPast) >= previous.since
            }
            if deloadLogged {
                return TrainingVerdictState(verdict: raw)
            }
            let day = calendar.startOfDay(for: now)
            var clearDays = stored.clearDays
            if !clearDays.contains(day) { clearDays.append(day) }

            let persistedLongEnough = daysBetween(previous.since, now) >= Self.minimumDeloadPersistenceDays
            if persistedLongEnough, clearDays.count >= Self.clearDaysToRelease {
                return TrainingVerdictState(verdict: raw)
            }
            let held = TrainingVerdict(kind: previous.kind, urgency: raw.urgency,
                reasons: ["Keeping the lighter-week recommendation while the signal settles"] + raw.reasons,
                signals: raw.signals, action: previous.action, since: previous.since, computedAt: now, isActiveDeload: false)
            return TrainingVerdictState(verdict: held, clearDays: clearDays)
        }

        // hold → progress, progress → hold, anything → deload: immediate.
        return TrainingVerdictState(verdict: raw)
    }

    private func daysBetween(_ from: Date, _ to: Date) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

private extension TrainingVerdict {
    func carrying(since: Date) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: urgency, reasons: reasons, signals: signals,
                        action: action, since: since, computedAt: computedAt, isActiveDeload: isActiveDeload)
    }

    func carrying(computedAt: Date) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: urgency, reasons: reasons, signals: signals,
                        action: action, since: since, computedAt: computedAt, isActiveDeload: isActiveDeload)
    }
}
