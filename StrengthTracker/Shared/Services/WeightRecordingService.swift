import Foundation
import Observation

/// Reviewed metadata corrections. A durable journal makes retries idempotent;
/// undo changes only the convention, never the user's weights, reps or dates.
@MainActor @Observable
public final class WeightRecordingService {
    public struct Change: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case library, template, workout, plan, planTarget, deloadTarget }
        public var kind: Kind
        public var parentId: UUID
        public var entryId: UUID
        public var before: WeightRecording?
        public var after: WeightRecording?
    }
    public struct Preview: Codable, Sendable {
        public var id = UUID()
        public var changes: [Change]
        public var workoutCount: Int
        public var beforeVolume: Double
        public var afterVolume: Double
        public var historyFingerprint: Data
    }
    private struct State: Encodable { var workouts: [Workout]; var exercises: [Exercise]; var templates: [WorkoutTemplate]; var plans: [ProgressionPlan] }
    private struct Journal: Codable { var preview: Preview; var complete = false; var isUndo: Bool? = nil }
    public enum Failure: Error, LocalizedError {
        case stale, busy
        public var errorDescription: String? {
            self == .stale ? "Training data changed. Refresh the preview before applying it." : "A weight-logging update is already in progress."
        }
    }
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var canUndo = false
    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let templates: any TemplateRepository
    private let plans: any ProgressionPlanRepository
    private let defaults: UserDefaults
    private let key = "weight_recording_correction_journal_v1"
    public var rebuild: (@MainActor () async throws -> Void)?
    public var didChange: (@MainActor () async -> Void)?
    public init(workouts: any WorkoutRepository, exercises: any ExerciseRepository, templates: any TemplateRepository,
                plans: any ProgressionPlanRepository, defaults: UserDefaults = .standard) {
        self.workouts = workouts; self.exercises = exercises; self.templates = templates; self.plans = plans; self.defaults = defaults
        canUndo = journal?.complete == true && journal?.isUndo != true
    }
    private var journal: Journal? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Journal.self, from: data)
    }
    private func store(_ value: Journal) throws { defaults.set(try JSONEncoder().encode(value), forKey: key) }
    public func catalog() async throws -> [Exercise] { try await exercises.fetchAll().filter { $0.isDumbbell }.sorted { $0.name < $1.name } }
    public func preview(selections: [UUID: WeightRecording], history: DateInterval?, updateFuture: Bool, bodyWeightKg: Double) async throws -> Preview {
        let state = try await stateSnapshot()
        let all = state.workouts
        var changes: [Change] = [], count = 0, before = 0.0, after = 0.0
        for var workout in all where workout.completedAt != nil && history?.contains(workout.trainingDate) == true {
            let original = workout
            for i in workout.exercises.indices {
                let e = workout.exercises[i]
                guard let config = selections[e.exercise.id], e.exercise.isDumbbell, config != e.exercise.weightRecording else { continue }
                changes.append(Change(kind: .workout, parentId: workout.id, entryId: e.id, before: e.exercise.weightRecording, after: config))
                workout.exercises[i].exercise.weightRecording = config
            }
            if original != workout {
                count += 1; before += original.totalVolume(bodyWeightKg: bodyWeightKg); after += workout.totalVolume(bodyWeightKg: bodyWeightKg)
            }
        }
        if updateFuture {
            for e in state.exercises where e.isDumbbell {
                guard let config = selections[e.id], e.weightRecording != config else { continue }
                changes.append(Change(kind: .library, parentId: e.id, entryId: e.id, before: e.weightRecording, after: config))
            }
            // Existing targets with a known convention are snapshots; don't reinterpret
            // them just because the library default changed.
            for t in state.templates {
                for e in t.exercises where e.exercise.weightRecording == nil {
                    guard let config = selections[e.exercise.id] else { continue }
                    changes.append(Change(kind: .template, parentId: t.id, entryId: e.id, before: nil, after: config))
                }
            }
            for p in state.plans where p.status == .active || p.status == .draft || p.status == .paused {
                for session in p.blocks.flatMap(\.weeks).flatMap(\.sessions) where !session.isCompleted {
                    let groups: [(Change.Kind, [PlannedExerciseSet])] = [(.planTarget, session.plannedExercises), (.deloadTarget, session.deloadPrescription?.normalExercises ?? [])]
                    for (kind, targets) in groups {
                        for target in targets where target.weightRecording == nil {
                            guard let config = selections[target.exerciseId] else { continue }
                            changes.append(Change(kind: kind, parentId: p.id, entryId: target.id, before: nil, after: config))
                        }
                    }
                }
                for e in p.exercises where e.weightRecording == nil {
                    guard let config = selections[e.exerciseId] else { continue }
                    changes.append(Change(kind: .plan, parentId: p.id, entryId: e.id, before: nil, after: config))
                }
            }
        }
        return Preview(changes: changes, workoutCount: count, beforeVolume: before, afterVolume: after,
                       historyFingerprint: try fingerprint(state))
    }
    private func stateSnapshot() async throws -> State {
        State(workouts: try await workouts.fetchAll().sorted { $0.id.uuidString < $1.id.uuidString },
            exercises: try await exercises.fetchAll().sorted { $0.id.uuidString < $1.id.uuidString },
            templates: try await templates.fetchAll().sorted { $0.id.uuidString < $1.id.uuidString },
            plans: try await plans.fetchAll().sorted { $0.id.uuidString < $1.id.uuidString })
    }
    private func fingerprint(_ state: State) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }
    public func apply(_ preview: Preview) async throws {
        guard !isBusy else { throw Failure.busy }
        guard !preview.changes.isEmpty else { return }
        isBusy = true; defer { isBusy = false }
        if let journal, journal.preview.id == preview.id, journal.complete { return }
        guard journal?.complete != false else { throw Failure.busy }
        guard try await fingerprint(stateSnapshot()) == preview.historyFingerprint else { throw Failure.stale }
        try store(Journal(preview: preview))
        try await finishPending()
    }
    public func resume() async {
        guard !isBusy, journal?.complete == false else { return }
        isBusy = true; defer { isBusy = false }
        do { try await finishPending() } catch { errorMessage = error.localizedDescription }
    }
    public func undo() async throws {
        guard !isBusy else { throw Failure.busy }
        guard let old = journal, old.complete, old.isUndo != true else { return }
        isBusy = true; defer { isBusy = false }
        var reverse = old.preview; reverse.id = UUID()
        reverse.changes = reverse.changes.map { Change(kind: $0.kind, parentId: $0.parentId, entryId: $0.entryId, before: $0.after, after: $0.before) }
        // Validate all destinations before writing any of the inverse changes.
        try await validate(reverse.changes, allowAlreadyApplied: false)
        try store(Journal(preview: reverse, isUndo: true))
        try await finishPending()
    }
    private func finishPending() async throws {
        guard var j = journal, !j.complete else { return }
        errorMessage = nil
        do {
            try await validate(j.preview.changes, allowAlreadyApplied: true)
            for c in j.preview.changes {
                switch c.kind {
                case .workout:
                    guard var w = try await workouts.fetchAll().first(where: { $0.id == c.parentId }),
                          let i = w.exercises.firstIndex(where: { $0.id == c.entryId }) else { throw Failure.stale }
                    w.exercises[i].exercise.weightRecording = c.after; _ = try await workouts.save(w)
                case .library:
                    guard var e = try await exercises.fetchAll().first(where: { $0.id == c.parentId }) else { throw Failure.stale }
                    e.weightRecording = c.after; _ = try await exercises.save(e)
                case .template:
                    guard var t = try await templates.fetchAll().first(where: { $0.id == c.parentId }),
                          let i = t.exercises.firstIndex(where: { $0.id == c.entryId }) else { throw Failure.stale }
                    t.exercises[i].exercise.weightRecording = c.after; _ = try await templates.save(t)
                case .planTarget, .deloadTarget:
                    guard var p = try await plans.fetch(id: c.parentId) else { throw Failure.stale }
                    for b in p.blocks.indices {
                        for w in p.blocks[b].weeks.indices {
                            for s in p.blocks[b].weeks[w].sessions.indices {
                                if c.kind == .planTarget {
                                    if let e = p.blocks[b].weeks[w].sessions[s].plannedExercises.firstIndex(where: { $0.id == c.entryId }) {
                                        p.blocks[b].weeks[w].sessions[s].plannedExercises[e].weightRecording = c.after
                                    }
                                } else if let e = p.blocks[b].weeks[w].sessions[s].deloadPrescription?.normalExercises.firstIndex(where: { $0.id == c.entryId }) {
                                    p.blocks[b].weeks[w].sessions[s].deloadPrescription?.normalExercises[e].weightRecording = c.after
                                }
                            }
                        }
                    }
                    try await plans.save(p)
                case .plan:
                    guard var p = try await plans.fetch(id: c.parentId), let i = p.exercises.firstIndex(where: { $0.id == c.entryId }) else { throw Failure.stale }
                    p.exercises[i].weightRecording = c.after; try await plans.save(p)
                }
            }
            try await rebuild?()
            await didChange?()
            // Completion is durable only after the derived data was successfully rebuilt.
            j.complete = true; j.preview.historyFingerprint = Data(); try store(j); canUndo = j.isUndo != true
        } catch { errorMessage = error.localizedDescription; throw error }
    }
    private func validate(_ changes: [Change], allowAlreadyApplied: Bool) async throws {
        let ws = try await workouts.fetchAll(), es = try await exercises.fetchAll(), ts = try await templates.fetchAll(), ps = try await plans.fetchAll()
        for c in changes {
            let exists: Bool; let current: WeightRecording?
            switch c.kind {
            case .workout:
                let w = ws.first { $0.id == c.parentId && $0.completedAt != nil }
                let e = w?.exercises.first { $0.id == c.entryId }; exists = e != nil; current = e?.exercise.weightRecording
            case .library:
                let e = es.first { $0.id == c.entryId }; exists = e != nil; current = e?.weightRecording
            case .template:
                let e = ts.first { $0.id == c.parentId }?.exercises.first { $0.id == c.entryId }; exists = e != nil; current = e?.exercise.weightRecording
            case .planTarget, .deloadTarget:
                let sessions = ps.first { $0.id == c.parentId }?.blocks.flatMap(\.weeks).flatMap(\.sessions) ?? []
                let targets = c.kind == .planTarget ? sessions.flatMap(\.plannedExercises) : sessions.flatMap { $0.deloadPrescription?.normalExercises ?? [] }
                let e = targets.first { $0.id == c.entryId }; exists = e != nil; current = e?.weightRecording
            case .plan:
                let e = ps.first { $0.id == c.parentId }?.exercises.first { $0.id == c.entryId }; exists = e != nil; current = e?.weightRecording
            }
            guard exists && (current == c.before || (allowAlreadyApplied && current == c.after)) else { throw Failure.stale }
        }
    }
}
