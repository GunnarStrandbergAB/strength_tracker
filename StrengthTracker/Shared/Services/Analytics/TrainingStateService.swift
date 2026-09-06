import Foundation

public enum TrainingStateKind: String, CaseIterable, Sendable {
    case usual = "Usual pattern", volume = "More volume", heavy = "Lower-rep work"
    case light = "Lighter week", returning = "Returning after a break", mixed = "Mixed changes", building = "Building baseline"
    public var explanation: String {
        switch self {
        case .usual: return "Weekly working sets and reps are close to your previous four weeks."
        case .volume: return "Weekly working sets increased by at least 20%, without a major rep-range shift."
        case .heavy: return "Median reps fell by at least 20%, consistent with lower-rep work; this does not establish intent."
        case .light: return "A logged deload or at least 25% fewer weekly working sets."
        case .returning: return "The latest session followed a break of at least 10 days."
        case .mixed: return "Both working-set volume and rep ranges changed substantially."
        case .building: return "At least three sessions in each four-week comparison period are needed."
        }
    }
}
public struct TrainingStateSummary: Sendable {
    public struct Period: Sendable {
        public let start: Date; public let end: Date; public let sessions: Int
        public let weeklySets: Double; public let medianReps: Double; public let meanRPE: Double?
    }
    public struct Week: Identifiable, Sendable {
        public var id: Date { start }; public let start: Date; public let sets: Int; public let sessions: Int
        public let kind: TrainingStateKind
    }
    public let kind: TrainingStateKind
    public let current: Period
    public let previous: Period
    public let weeks: [Week]
}
public enum TrainingStateService {
    public struct NotableSession: Identifiable, Sendable {
        public var id: UUID { workout.id }
        public let workout: Workout
        public let detail: String
    }
    /// Compare a session with the previous three or more matching routines, never unrelated workouts.
    public static func notableSessions(workouts: [Workout], now: Date = Date()) -> [NotableSession] {
        let completed = workouts.filter { $0.completedAt != nil && $0.trainingDate <= now }.sorted { $0.trainingDate > $1.trainingDate }
        func family(_ workout: Workout) -> String {
            workout.templateId?.uuidString ?? workout.exercises.map { $0.exercise.id.uuidString }.sorted().joined(separator: ":")
        }
        func count(_ workout: Workout) -> Double {
            Double(workout.exercises.flatMap(\.sets).filter { $0.isCompleted && $0.setType != .warmup }.count)
        }
        return completed.filter { now.timeIntervalSince($0.trainingDate) <= 28 * 86400 }.compactMap { workout in
            if workout.isDeload { return NotableSession(workout: workout, detail: "Logged deload") }
            let previous = completed.filter { $0.trainingDate < workout.trainingDate && !$0.isDeload && family($0) == family(workout) }.prefix(6)
            guard previous.count >= 3 else { return nil }
            let values = previous.map(count).sorted()
            let baseline = values[values.count / 2]
            guard baseline > 0 else { return nil }
            let delta = (count(workout) / baseline - 1) * 100
            guard abs(delta) >= 25 else { return nil }
            return NotableSession(workout: workout, detail: String(format: "%.0f%% %@ working sets vs %d prior matching sessions (%.0f vs %.0f sets)", abs(delta), delta < 0 ? "fewer" : "more", previous.count, count(workout), baseline))
        }
    }

    public static func summarize(workouts: [Workout], now: Date = Date()) -> TrainingStateSummary {
        let calendar = Calendar.mondayStart
        let end = calendar.weekStart(for: now)
        let start = calendar.date(byAdding: .weekOfYear, value: -4, to: end)!
        let prior = calendar.date(byAdding: .weekOfYear, value: -4, to: start)!
        let completed = workouts.filter { $0.completedAt != nil && $0.trainingDate <= now }.sorted { $0.trainingDate < $1.trainingDate }
        func period(_ start: Date, _ end: Date) -> TrainingStateSummary.Period {
            let sessions = completed.filter { $0.trainingDate >= start && $0.trainingDate < end }
            let sets = sessions.flatMap(\.exercises).flatMap(\.sets).filter { $0.isCompleted && $0.setType != .warmup }
            let reps = sets.compactMap(\.reps).sorted()
            let rpes = sets.compactMap(\.rpe)
            return .init(start: start, end: end, sessions: sessions.count, weeklySets: Double(sets.count) / 4,
                medianReps: reps.isEmpty ? 0 : Double(reps[reps.count / 2]), meanRPE: rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count))
        }
        let current = period(start, end), previous = period(prior, start)
        let ratio = previous.weeklySets > 0 ? current.weeklySets / previous.weeklySets : 1
        let repRatio = previous.medianReps > 0 ? current.medianReps / previous.medianReps : 1
        var kind: TrainingStateKind = .usual
        if current.sessions < 3 || previous.sessions < 3 { kind = .building }
        else if ratio >= 1.2 && (repRatio <= 0.8 || repRatio >= 1.2) { kind = .mixed }
        else if ratio <= 0.75 { kind = .light }
        else if repRatio <= 0.8 { kind = .heavy }
        else if ratio >= 1.2 { kind = .volume }
        if let latest = completed.last, now.timeIntervalSince(latest.trainingDate) < 7 * 86400 {
            if latest.isDeload { kind = .light }
            else if completed.count > 1 && latest.trainingDate.timeIntervalSince(completed[completed.count - 2].trainingDate) >= 10 * 86400 { kind = .returning }
        }
        let weeks: [TrainingStateSummary.Week] = (0..<8).map { offset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: prior)!
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
            let sessions = completed.filter { $0.trainingDate >= weekStart && $0.trainingDate < weekEnd }
            let sets = sessions.flatMap(\.exercises).flatMap(\.sets).filter { $0.isCompleted && $0.setType != .warmup }.count
            return .init(start: weekStart, sets: sets, sessions: sessions.count, kind: sessions.isEmpty ? .building : (sessions.contains(where: \.isDeload) ? .light : .usual))
        }
        return .init(kind: kind, current: current, previous: previous, weeks: weeks)
    }
}
