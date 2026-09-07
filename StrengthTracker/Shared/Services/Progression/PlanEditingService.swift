import Foundation
import CryptoKit

public struct PlanConfiguration: Codable, Equatable, Sendable {
    public var durationWeeks: Int
    public var deloadWeightPercentage: Int
    public var deloadRestPercentage: Int
    public init(durationWeeks: Int, deloadWeightPercentage: Int = 50, deloadRestPercentage: Int = 75) {
        self.durationWeeks = durationWeeks
        self.deloadWeightPercentage = deloadWeightPercentage
        self.deloadRestPercentage = deloadRestPercentage
    }
}

/// Persist the normal prescription, so deload is an overlay rather than destructive scaling.
public struct PlanDeloadPrescription: Codable, Equatable, Sendable {
    public var normalExercises: [PlannedExerciseSet]
    public var normalLabel: String
    public var weightPercentage: Int
    public var restPercentage: Int
    public var omitted: Bool
}

public enum PlanDeloadPolicy {
    public static func apply(to session: inout PlannedSession, weightPercentage: Int, restPercentage: Int, omitted: Bool = false) {
        if session.deloadPrescription == nil {
            session.deloadPrescription = .init(normalExercises: session.plannedExercises, normalLabel: session.sessionLabel,
                weightPercentage: weightPercentage, restPercentage: restPercentage, omitted: omitted)
        }
        session.deloadPrescription?.weightPercentage = weightPercentage
        session.deloadPrescription?.restPercentage = restPercentage
        session.deloadPrescription?.omitted = omitted
        session.isDeload = true
        session.sessionLabel = "Deload · " + (session.deloadPrescription?.normalLabel ?? session.sessionLabel)
        refresh(&session)
    }
    public static func refresh(_ session: inout PlannedSession) {
        guard let policy = session.deloadPrescription else { return }
        session.plannedExercises = policy.normalExercises.map { normal in
            var value = normal
            value.targetWeight = (normal.targetWeight * Double(policy.weightPercentage) / 100 * 100).rounded() / 100
            value.percentageOf1RM = normal.percentageOf1RM * Double(policy.weightPercentage) / 100
            return value
        }
    }
    public static func remove(from session: inout PlannedSession) throws {
        guard let policy = session.deloadPrescription else {
            throw PlanEditError("This legacy deload has no saved normal prescription. Replace its targets explicitly before moving it.")
        }
        session.plannedExercises = policy.normalExercises
        session.sessionLabel = policy.normalLabel
        session.isDeload = false
        session.deloadPrescription = nil
    }
}

public struct PlanEditError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PlanEditRequest: Codable, Equatable, Sendable {
    public enum Operation: String, CaseIterable, Codable, Sendable {
        case convertDeload, insertDeload, moveDeload, removeDeload, repeatWeek, extendPlan
        case rescheduleSession, skipSession, changeTemplate, changeExercise, changeTargets
        public var displayName: String {
            switch self {
            case .convertDeload: return "Make week a deload"
            case .insertDeload: return "Insert extra deload"
            case .moveDeload: return "Move deload"
            case .removeDeload: return "Remove deload"
            case .repeatWeek: return "Repeat week"
            case .extendPlan: return "Extend plan"
            case .rescheduleSession: return "Reschedule session"
            case .skipSession: return "Skip or restore session"
            case .changeTemplate: return "Change template"
            case .changeExercise: return "Swap exercise"
            case .changeTargets: return "Change targets"
            }
        }
    }
    public enum Scope: String, CaseIterable, Codable, Sendable { case session, week, remaining }
    public var operation: Operation
    public var week: Int?
    public var destinationWeek: Int?
    public var sessionID: UUID?
    public var newDate: Date?
    public var weeks: Int
    public var scope: Scope
    public var templateID: UUID?
    public var exerciseID: UUID?
    public var replacementExerciseID: UUID?
    public var sets: Int?
    public var reps: Int?
    public var weightKg: Double?
    public var restSeconds: Int?
    public var skipped: Bool?
    public init(operation: Operation, week: Int? = nil, destinationWeek: Int? = nil, sessionID: UUID? = nil,
        newDate: Date? = nil, weeks: Int = 1, scope: Scope = .week, templateID: UUID? = nil,
        exerciseID: UUID? = nil, replacementExerciseID: UUID? = nil, sets: Int? = nil, reps: Int? = nil,
        weightKg: Double? = nil, restSeconds: Int? = nil, skipped: Bool? = nil) {
        self.operation = operation; self.week = week; self.destinationWeek = destinationWeek
        self.sessionID = sessionID; self.newDate = newDate; self.weeks = weeks; self.scope = scope
        self.templateID = templateID; self.exerciseID = exerciseID; self.replacementExerciseID = replacementExerciseID
        self.sets = sets; self.reps = reps; self.weightKg = weightKg; self.restSeconds = restSeconds; self.skipped = skipped
    }
}

public struct PlanEditPreview: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let planID: UUID
    public let planName: String
    public let expectedVersion: String
    public let dependencyVersion: String
    public let request: PlanEditRequest
    public let settings: PlanConfiguration
    public let summaryLines: [String]
    public let proposedAt: Date
    public var detailLines: [String]? = nil
}

public enum PlanEditingService {
    public static func version<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "unavailable"
    }
    public static func dependencies(templates: [WorkoutTemplate], exercises: [Exercise]) -> String {
        version(templates.sorted { $0.id.uuidString < $1.id.uuidString }) + version(exercises.sorted { $0.id.uuidString < $1.id.uuidString })
    }
    public static func preview(plan: ProgressionPlan, request: PlanEditRequest, settings: PlanConfiguration,
        templates: [WorkoutTemplate] = [], exercises: [Exercise] = [], protectedSessionIDs: Set<UUID> = [], now: Date = Date()) throws -> PlanEditPreview {
        let id = UUID()
        let candidate = try applying(request, to: plan, settings: settings, templates: templates, exercises: exercises,
            protectedSessionIDs: protectedSessionIDs, operationID: id, now: now)
        let old = plan.blocks.flatMap(\.weeks).flatMap(\.sessions)
        let new = candidate.blocks.flatMap(\.weeks).flatMap(\.sessions)
        let changed = new.filter { s in old.first(where: { $0.id == s.id }) != s }
        let removed = old.filter { prior in !new.contains { $0.id == prior.id } }
        var lines = ["\(plan.name) · \(request.operation.displayName)",
            "\(changed.count) sessions changed; \(new.count - old.count) net sessions added.",
            "Schedule: \(plan.totalWeeks) → \(candidate.totalWeeks) calendar weeks.",
            "Finish: \(dateLabel(plan.targetEndDate)) → \(dateLabel(candidate.targetEndDate))."]
        if request.operation == .convertDeload || request.operation == .insertDeload || request.operation == .moveDeload {
            lines.append("Deload: \(settings.deloadWeightPercentage)% of normal scheduled weight; \(settings.deloadRestPercentage)% rest. Sets/reps preserved.")
        }
        var details: [String] = []
        for s in changed {
            let prior = old.first { $0.id == s.id }
            let targets = s.plannedExercises.prefix(3).map { "\($0.exerciseName): \($0.sets) × \($0.targetReps) at \($0.targetWeight) kg" }.joined(separator: "; ")
            details.append("\(dateLabel(prior?.scheduledDate)) → \(dateLabel(s.scheduledDate)): \(s.sessionLabel)\(s.isOmitted ? " (not scheduled)" : "")\(targets.isEmpty ? "" : " · " + targets)")
        }
        for session in removed { details.append("Remove: \(dateLabel(session.scheduledDate)) · \(session.sessionLabel)") }
        lines.append("Review \(details.count) session changes below.")
        lines.append("Completed and in-progress workouts are preserved. Reusable templates are unchanged.")
        return .init(id: id, planID: plan.id, planName: plan.name, expectedVersion: version(plan),
            dependencyVersion: dependencies(templates: templates, exercises: exercises), request: request, settings: settings,
            summaryLines: lines, proposedAt: now, detailLines: details)
    }
    public static func dateLabel(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}

public extension PlanEditingService {
    /// Pure transformation. Persistence and confirmation are deliberately separate.
    static func applying(_ request: PlanEditRequest, to original: ProgressionPlan, settings: PlanConfiguration,
        templates: [WorkoutTemplate] = [], exercises: [Exercise] = [], protectedSessionIDs: Set<UUID> = [],
        operationID: UUID = UUID(), now: Date = Date()) throws -> ProgressionPlan {
        guard original.status == .active else { throw PlanEditError("Only an active plan can be edited.") }
        guard (1...12).contains(request.weeks), (10...100).contains(settings.deloadWeightPercentage),
              (25...100).contains(settings.deloadRestPercentage) else { throw PlanEditError("Invalid week count or deload settings.") }
        if let n = request.sets, !(1...20).contains(n) { throw PlanEditError("Sets must be 1–20.") }
        if let n = request.reps, !(1...100).contains(n) { throw PlanEditError("Reps must be 1–100.") }
        if let n = request.weightKg, !n.isFinite || !(0...999.99).contains(n) { throw PlanEditError("Weight must be 0–999.99 kg.") }
        if let n = request.restSeconds, !(15...900).contains(n) { throw PlanEditError("Rest must be 15–900 seconds.") }
        let cal = CalendarWeekBucketer.mondayCalendar
        let today = cal.startOfDay(for: now)
        var plan = original
        struct Entry { var block: Int; var week: Int; var session: PlannedSession }
        var entries = plan.blocks.enumerated().flatMap { b, block in
            block.weeks.flatMap { week in week.sessions.map { Entry(block: b, week: week.absoluteWeekNumber, session: $0) } }
        }
        func editable(_ s: PlannedSession) -> Bool {
            !s.isCompleted && !protectedSessionIDs.contains(s.id) && (s.scheduledDate ?? .distantPast) >= today
        }
        func ensure(_ indices: [Int]) throws {
            guard !indices.isEmpty else { throw PlanEditError("No sessions match that scope.") }
            guard indices.allSatisfy({ editable(entries[$0].session) }) else {
                throw PlanEditError("This change includes past, completed or in-progress sessions. Choose a future week or session.")
            }
        }
        func shift(_ date: Date?, _ days: Int) throws -> Date {
            guard let date, let result = cal.date(byAdding: .day, value: days, to: date) else { throw PlanEditError("A session has no valid scheduled date.") }
            return result
        }
        func normal(_ session: PlannedSession) throws -> PlannedSession {
            var s = session
            if s.isDeload {
                if s.deloadPrescription != nil { try PlanDeloadPolicy.remove(from: &s) }
                else {
                    // Older plans did not save a normal prescription. Recover from the nearest
                    // matching ordinary session, never divide a legacy %1RM target by today's setting.
                    let targetIDs = s.plannedExercises.map(\.exerciseId)
                    let reference = s.scheduledDate ?? now
                    var nearest: PlannedSession?
                    var distance = Double.infinity
                    for entry in entries {
                        let candidate = entry.session
                        guard !candidate.isDeload, candidate.dayOfWeek == s.dayOfWeek,
                              candidate.plannedExercises.map(\.exerciseId) == targetIDs else { continue }
                        let gap = abs((candidate.scheduledDate ?? now).timeIntervalSince(reference))
                        if gap < distance { nearest = candidate; distance = gap }
                    }
                    guard let source = nearest else { throw PlanEditError("Cannot reconstruct this legacy deload. Choose a normal week to copy or set its prescription explicitly.") }
                    s.plannedExercises = source.plannedExercises; s.sessionLabel = source.sessionLabel; s.isDeload = false
                }
            }
            return s
        }
        func deload(_ s: inout PlannedSession) throws {
            if s.isDeload && s.deloadPrescription == nil { s = try normal(s) }
            let omitted = plan.deloadDays.map { !$0.contains(s.dayOfWeek ?? 0) } ?? false
            PlanDeloadPolicy.apply(to: &s, weightPercentage: settings.deloadWeightPercentage,
                restPercentage: settings.deloadRestPercentage, omitted: omitted)
        }
        func clone(_ s: PlannedSession, date: Date, deloaded: Bool, group: UUID) throws -> PlannedSession {
            let base = try normal(s)
            var copy = PlannedSession(dayOfWeek: cal.component(.weekday, from: date), scheduledDate: date,
                dupSessionType: base.dupSessionType, sessionLabel: base.sessionLabel, plannedExercises: base.plannedExercises,
                estimatedDurationMinutes: base.estimatedDurationMinutes, templateId: base.templateId, notes: base.notes,
                programmingWeekID: base.programmingWeekID, programmingWeekNumber: base.programmingWeekNumber, insertedGroupID: group)
            if deloaded { try deload(&copy) }
            return copy
        }
        let targetWeek = request.week ?? request.sessionID.flatMap { id in entries.first { $0.session.id == id }?.week }
        var selected: [Int] = entries.indices.filter { i in
            switch request.scope {
            case .session: return entries[i].session.id == request.sessionID
            case .week: return entries[i].week == targetWeek
            case .remaining: return entries[i].week >= (targetWeek ?? Int.max) && editable(entries[i].session)
            }
        }
        switch request.operation {
        case .convertDeload:
            try ensure(selected)
            for i in selected { var session = entries[i].session; try deload(&session); entries[i].session = session }
        case .insertDeload, .repeatWeek, .extendPlan:
            let sourceWeek = request.operation == .extendPlan ? (targetWeek ?? entries.map(\.week).max()) : targetWeek
            let source = entries.filter { $0.week == sourceWeek }
            guard !source.isEmpty else { throw PlanEditError("Choose an existing calendar week to copy.") }
            guard source.allSatisfy({ $0.session.scheduledDate != nil }) else { throw PlanEditError("Source sessions need scheduled dates before copying.") }
            let sourceStart = CalendarWeekBucketer.weekStart(of: source.compactMap { $0.session.scheduledDate }.min()!)
            let insertion = request.operation == .extendPlan
                ? try shift(entries.compactMap { $0.session.scheduledDate }.max().map { CalendarWeekBucketer.weekStart(of: $0) }, 7)
                : (request.operation == .repeatWeek ? try shift(sourceStart, 7) : sourceStart)
            guard insertion >= CalendarWeekBucketer.weekStart(of: today) else { throw PlanEditError("Choose a future insertion point.") }
            let moving = entries.indices.filter { (entries[$0].session.scheduledDate ?? .distantPast) >= insertion }
            if !moving.isEmpty { try ensure(moving) }
            for i in moving { entries[i].session.scheduledDate = try shift(entries[i].session.scheduledDate, request.weeks * 7) }
            for offset in 0..<request.weeks {
                let group = UUID()
                for entry in source {
                    let days = cal.dateComponents([.day], from: sourceStart, to: entry.session.scheduledDate!).day ?? 0
                    let date = try shift(insertion, days + offset * 7)
                    guard date >= today else { throw PlanEditError("The copied week would include past dates.") }
                    entries.append(Entry(block: entry.block, week: entry.week,
                        session: try clone(entry.session, date: date, deloaded: request.operation == .insertDeload, group: group)))
                }
            }
        case .removeDeload:
            try ensure(selected)
            guard selected.allSatisfy({ entries[$0].session.isDeload }) else { throw PlanEditError("Choose only deload sessions.") }
            let groups = Set(selected.compactMap { entries[$0].session.insertedGroupID })
            if !groups.isEmpty {
                guard request.scope == .week, groups.count == 1,
                      selected.allSatisfy({ entries[$0].session.insertedGroupID != nil }),
                      entries.indices.filter({ groups.contains(entries[$0].session.insertedGroupID ?? UUID()) }).count == selected.count
                else { throw PlanEditError("Remove an inserted deload as a whole week.") }
                let start = CalendarWeekBucketer.weekStart(of: entries[selected[0]].session.scheduledDate!)
                let after = try shift(start, 7)
                let moving = entries.indices.filter { (entries[$0].session.scheduledDate ?? .distantPast) >= after }
                if !moving.isEmpty { try ensure(moving) }
                for i in moving { entries[i].session.scheduledDate = try shift(entries[i].session.scheduledDate, -7) }
                let ids = Set(selected.map { entries[$0].session.id }); entries.removeAll { ids.contains($0.session.id) }
            } else { for i in selected { entries[i].session = try normal(entries[i].session) } }
        case .moveDeload:
            guard request.scope == .week, let destination = request.destinationWeek, destination != targetWeek else { throw PlanEditError("Choose a different destination week.") }
            try ensure(selected)
            guard selected.allSatisfy({ entries[$0].session.isDeload }) else { throw PlanEditError("Select a deload week to move.") }
            let dest = entries.indices.filter { entries[$0].week == destination }; try ensure(dest)
            let groups = Set(selected.compactMap { entries[$0].session.insertedGroupID })
            if let group = groups.first {
                guard groups.count == 1, selected.allSatisfy({ entries[$0].session.insertedGroupID == group }),
                      entries.filter({ $0.session.insertedGroupID == group }).count == selected.count else {
                    throw PlanEditError("The inserted deload was split across weeks. Move its sessions individually.")
                }
                let origin = targetWeek!
                let shifting = entries.indices.filter { !selected.contains($0) && entries[$0].week >= min(origin, destination) && entries[$0].week <= max(origin, destination) }
                if !shifting.isEmpty { try ensure(shifting) }
                for i in shifting { entries[i].session.scheduledDate = try shift(entries[i].session.scheduledDate, destination > origin ? -7 : 7) }
                for i in selected { entries[i].session.scheduledDate = try shift(entries[i].session.scheduledDate, (destination - origin) * 7) }
            } else {
                guard dest.allSatisfy({ !entries[$0].session.isDeload }) else { throw PlanEditError("The destination is already a deload.") }
                for i in selected { entries[i].session = try normal(entries[i].session) }
                for i in dest { var session = entries[i].session; try deload(&session); entries[i].session = session }
            }
        case .rescheduleSession, .skipSession:
            selected = entries.indices.filter { entries[$0].session.id == request.sessionID }; try ensure(selected)
            for i in selected {
                if request.operation == .rescheduleSession {
                    guard let date = request.newDate, cal.startOfDay(for: date) >= today else { throw PlanEditError("Choose today or a future date.") }
                    entries[i].session.scheduledDate = cal.startOfDay(for: date)
                    entries[i].session.dayOfWeek = cal.component(.weekday, from: date)
                } else {
                    entries[i].session.isSkipped = request.skipped ?? true
                    entries[i].session.skippedAt = entries[i].session.isSkipped ? now : nil
                }
            }
        case .changeTemplate, .changeExercise, .changeTargets:
            try ensure(selected)
            if request.operation == .changeTargets && request.sets == nil && request.reps == nil && request.weightKg == nil && request.restSeconds == nil {
                throw PlanEditError("Specify at least one target to change.")
            }
            var matched = 0
            for i in selected {
                var s = try normal(entries[i].session)
                let priorPolicy = entries[i].session.deloadPrescription
                let wasDeload = entries[i].session.isDeload
                if request.operation == .changeTemplate {
                    guard let template = templates.first(where: { $0.id == request.templateID }), !template.exercises.isEmpty else { throw PlanEditError("Template not found or empty.") }
                    s.templateId = template.id; s.sessionLabel = template.name
                    s.plannedExercises = template.exercises.sorted { $0.order < $1.order }.map { te in
                        s.plannedExercises.first { $0.exerciseId == te.exercise.id } ?? PlannedExerciseSet(
                            planExerciseId: plan.exercises.first { $0.exerciseId == te.exercise.id }?.id ?? UUID(),
                            exerciseId: te.exercise.id, exerciseName: te.exercise.name, sets: te.targetSets,
                            targetReps: te.targetReps ?? 0, targetWeight: te.targetWeight ?? 0, percentageOf1RM: 0,
                            restSeconds: te.restTimerSeconds ?? 120, isWarmup: te.isWarmUp)
                    }
                    matched += 1
                } else {
                    for e in s.plannedExercises.indices where request.exerciseID == nil || s.plannedExercises[e].exerciseId == request.exerciseID {
                        if request.operation == .changeExercise {
                            guard request.exerciseID != nil, let replacement = exercises.first(where: { $0.id == request.replacementExerciseID && !$0.isArchived }),
                                  let weight = request.weightKg, let reps = request.reps else { throw PlanEditError("An exercise swap needs source/replacement IDs and explicit weight_kg and reps; loads are not transferable between exercises.") }
                            s.plannedExercises[e].exerciseId = replacement.id; s.plannedExercises[e].exerciseName = replacement.name
                            s.plannedExercises[e].planExerciseId = plan.exercises.first { $0.exerciseId == replacement.id }?.id ?? UUID()
                            s.plannedExercises[e].targetWeight = weight; s.plannedExercises[e].targetReps = reps
                        }
                        if let sets = request.sets { s.plannedExercises[e].sets = sets }
                        if let reps = request.reps { s.plannedExercises[e].targetReps = reps }
                        if let weight = request.weightKg { s.plannedExercises[e].targetWeight = (weight * 100).rounded() / 100 }
                        if let rest = request.restSeconds { s.plannedExercises[e].restSeconds = rest }
                        // Explicit user targets are fixed, not silently replaced by the next APRE replay.
                        s.plannedExercises[e].percentageOf1RM = 0
                        s.plannedExercises[e].isUserOverride = true
                        matched += 1
                    }
                }
                if let policy = priorPolicy { PlanDeloadPolicy.apply(to: &s, weightPercentage: policy.weightPercentage, restPercentage: policy.restPercentage, omitted: policy.omitted) }
                if wasDeload && priorPolicy == nil { try deload(&s) }
                entries[i].session = s
            }
            guard matched > 0 else { throw PlanEditError("That exercise is not present in the selected sessions.") }
        }
        guard entries.count <= 1000 else { throw PlanEditError("The edited plan exceeds 1,000 sessions. Use a smaller extension.") }
        // Preserve original week IDs/metadata where dates still share a bucket.
        let updated = Dictionary(entries.map { ($0.session.id, $0.session) }, uniquingKeysWith: { first, _ in first })
        let originalIDs = Set(original.blocks.flatMap(\.weeks).flatMap(\.sessions).map(\.id))
        for b in plan.blocks.indices {
            for w in plan.blocks[b].weeks.indices {
                plan.blocks[b].weeks[w].sessions = plan.blocks[b].weeks[w].sessions.compactMap { updated[$0.id] }
            }
            plan.blocks[b].weeks.removeAll { $0.sessions.isEmpty }
            let added = entries.filter { $0.block == b && !originalIDs.contains($0.session.id) }.map(\.session)
            if !added.isEmpty { plan.blocks[b].weeks.append(TrainingWeek(weekNumber: 1, absoluteWeekNumber: 1, sessions: added)) }
        }
        plan.blocks = CalendarWeekBucketer.rebucket(plan.blocks.filter { !$0.weeks.flatMap(\.sessions).isEmpty })
        plan.targetEndDate = entries.compactMap { $0.session.scheduledDate }.max()
        // Legacy calendar buckets do not prove the original programming duration.
        plan.configuration = original.configuration
        let oldSessions = original.blocks.flatMap(\.weeks).flatMap(\.sessions)
        guard Set(entries.map { version($0.session) }) != Set(oldSessions.map { version($0) }) else { throw PlanEditError("The requested change makes no difference.") }
        plan.adjustments.append(.init(id: operationID, adjustmentType: .reforecast, trigger: .userManual,
            description: "\(request.operation.displayName) · calendar week \(targetWeek.map(String.init) ?? "selected scope")",
            previousValues: ["scheduleVersion": version(original), "endDate": dateLabel(original.targetEndDate)],
            newValues: ["endDate": dateLabel(plan.targetEndDate), "calendarWeeks": String(plan.totalWeeks)], appliedAt: now, wasAccepted: true))
        plan.updatedAt = now
        return plan
    }
}
