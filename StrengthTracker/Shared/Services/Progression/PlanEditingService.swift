import Foundation
import CryptoKit

public struct PlanConfiguration: Codable, Equatable, Sendable {
    public var durationWeeks: Int
    public var deloadWeightPercentage: Int
    public var deloadRestPercentage: Int
    public var calendarAnchorDate: Date?
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
        case batch, setWeekSchedule, addSession, duplicateSession, removeSessions, updateSession
        case setSessionExercises, changeSchedule, shiftSchedule, insertRestWeek, shortenPlan, undoEdit, restoreSession
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
            case .batch: return "Update plan"
            case .setWeekSchedule: return "Replace week's schedule"
            case .addSession: return "Add session"
            case .duplicateSession: return "Duplicate session"
            case .removeSessions: return "Remove from plan"
            case .updateSession: return "Rename or annotate session"
            case .setSessionExercises: return "Edit session contents"
            case .changeSchedule: return "Change weekly schedule"
            case .shiftSchedule: return "Shift remaining schedule"
            case .insertRestWeek: return "Insert rest week"
            case .shortenPlan: return "Change finish date"
            case .undoEdit: return "Undo plan edit"
            case .restoreSession: return "Restore removed session"
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
    public var operations: [PlanEditRequest]?
    public var sessionIDs: [UUID]?
    public var schedule: [PlanSessionPlacement]?
    public var weeklySchedule: [PlanDayRule]?
    public var contents: [PlanExercisePrescription]?
    public var label: String?
    public var notes: String?
    public var endWeek: Int?
    public var days: Int?
    public var editID: UUID?
    public var isDeload: Bool?
    public var deloadWeightPercentage: Int?
    public var deloadRestPercentage: Int?
    public var remainingOnly: Bool?
    public var correctionReason: String?
    public var targetRPE: Double?
    public init(operation: Operation, week: Int? = nil, destinationWeek: Int? = nil, sessionID: UUID? = nil,
        newDate: Date? = nil, weeks: Int = 1, scope: Scope = .week, templateID: UUID? = nil,
        exerciseID: UUID? = nil, replacementExerciseID: UUID? = nil, sets: Int? = nil, reps: Int? = nil,
        weightKg: Double? = nil, restSeconds: Int? = nil, skipped: Bool? = nil,
        operations: [PlanEditRequest]? = nil, sessionIDs: [UUID]? = nil, schedule: [PlanSessionPlacement]? = nil,
        weeklySchedule: [PlanDayRule]? = nil, contents: [PlanExercisePrescription]? = nil,
        label: String? = nil, notes: String? = nil, endWeek: Int? = nil, days: Int? = nil,
        editID: UUID? = nil, isDeload: Bool? = nil, deloadWeightPercentage: Int? = nil,
        deloadRestPercentage: Int? = nil, remainingOnly: Bool? = nil, correctionReason: String? = nil,
        targetRPE: Double? = nil) {
        self.operation = operation; self.week = week; self.destinationWeek = destinationWeek
        self.sessionID = sessionID; self.newDate = newDate; self.weeks = weeks; self.scope = scope
        self.templateID = templateID; self.exerciseID = exerciseID; self.replacementExerciseID = replacementExerciseID
        self.sets = sets; self.reps = reps; self.weightKg = weightKg; self.restSeconds = restSeconds; self.skipped = skipped
        self.operations = operations; self.sessionIDs = sessionIDs; self.schedule = schedule; self.weeklySchedule = weeklySchedule
        self.contents = contents; self.label = label; self.notes = notes; self.endWeek = endWeek; self.days = days
        self.editID = editID; self.isDeload = isDeload; self.deloadWeightPercentage = deloadWeightPercentage
        self.deloadRestPercentage = deloadRestPercentage; self.remainingOnly = remainingOnly
        self.correctionReason = correctionReason; self.targetRPE = targetRPE
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
    public var changeRecord: PlanEditRecord? = nil
    public var sessionChanges: [PlanSessionChange]? = nil
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
        let record = PlanEditRecord(before: .init(plan), after: .init(candidate))
        let changes = changes(from: record.before, to: record.after)
        let added = changes.filter { $0.before == nil }.count
        let removed = changes.filter { $0.after == nil }.count
        let modified = changes.count - added - removed
        var lines = ["\(plan.name) · \(request.operation.displayName)",
            "\(added) added · \(removed) removed · \(modified) changed.",
            "Schedule: \(plan.totalWeeks) → \(candidate.totalWeeks) calendar weeks.",
            "Finish: \(dateLabel(plan.targetEndDate)) → \(dateLabel(candidate.targetEndDate))."]
        let changedWeeks = Set(changes.flatMap { [$0.before?.scheduledDate, $0.after?.scheduledDate].compactMap { $0 }.map { CalendarWeekBucketer.weekStart(of: $0) } })
        for start in changedWeeks.sorted() {
            let before = record.before.sessions.filter { !$0.isOmitted && CalendarWeekBucketer.weekStart(of: $0.scheduledDate ?? .distantPast) == start }.count
            let after = record.after.sessions.filter { !$0.isOmitted && CalendarWeekBucketer.weekStart(of: $0.scheduledDate ?? .distantPast) == start }.count
            lines.append("Week of \(dateLabel(start)): \(before) → \(after) scheduled sessions\(after == 0 ? " · Rest week" : "").")
        }
        let policies = Set(changes.compactMap { change -> String? in
            guard let p = change.after?.deloadPrescription else { return nil }
            return "Deload: \(p.weightPercentage)% of normal weight; \(p.restPercentage)% of normal rest."
        })
        lines.append(contentsOf: policies.sorted())
        let today = CalendarWeekBucketer.mondayCalendar.startOfDay(for: now)
        let endOfToday = CalendarWeekBucketer.mondayCalendar.date(byAdding: .day, value: 1, to: today)!
        let elapsed = { (values: [PlannedSession]) in values.filter { !$0.isOmitted && ($0.isSkipped || ($0.scheduledDate ?? .distantPast) < endOfToday) }.count }
        if elapsed(record.before.sessions) != elapsed(record.after.sessions) {
            lines.append("Due sessions counted for adherence: \(elapsed(record.before.sessions)) → \(elapsed(record.after.sessions)).")
        }
        lines.append("Removed sessions are kept in edit history for restoration; they are not marked skipped.")
        lines.append("Completed and in-progress workouts are preserved. Reusable templates are unchanged.")
        let details = changes.map { change in
            let before = change.before.map { describeSession($0, templates: templates, exercises: exercises) } ?? "New session"
            guard let after = change.after else { return "Remove: " + before }
            return "Before: \(before)\nAfter: \(describeSession(after, templates: templates, exercises: exercises))"
        }
        var preview = PlanEditPreview(id: id, planID: plan.id, planName: plan.name, expectedVersion: version(plan),
            dependencyVersion: dependencies(templates: templates, exercises: exercises), request: request, settings: settings,
            summaryLines: lines, proposedAt: now, detailLines: details)
        preview.changeRecord = record; preview.sessionChanges = changes
        return preview
    }
    private static func describeSession(_ session: PlannedSession, templates: [WorkoutTemplate], exercises: [Exercise]) -> String {
        let workout = session.resolvedTemplate(linked: templates.first { $0.id == session.templateId }, exercises: exercises)
        var lines = ["\(dateLabel(session.scheduledDate)) · \(session.displayLabel)\(session.isDeload ? " · Deload" : "")\(session.isSkipped ? " · Skipped" : "")\(session.isOmitted ? " · Not scheduled" : "")"]
        if let notes = workout.notes, !notes.isEmpty { lines.append("Notes: " + notes) }
        for row in workout.exercises.sorted(by: { $0.order < $1.order }) {
            var targets = ["\(row.targetSets) sets"]
            if let reps = row.targetReps, reps > 0 { targets.append("\(reps) \(row.exercise.repetitionsLabel)") }
            if let weight = row.targetWeight, [.weightedReps, .bodyweightReps, .weightedCardio].contains(row.exercise.exerciseType) {
                targets.append("\(weight.formatted(.number.precision(.fractionLength(0...2)))) \(row.exercise.weightEntryLabel(.kg))")
            }
            if let duration = row.targetDurationSeconds { targets.append("\(duration) sec") }
            if let distance = row.targetDistanceMeters { targets.append("\(distance.formatted()) m") }
            if let rest = row.restTimerSeconds {
                let effective = session.isDeload ? max(15, rest * (session.deloadPrescription?.restPercentage ?? 75) / 100) : rest
                targets.append("Rest \(effective) sec")
            }
            if let notes = row.notes, !notes.isEmpty { targets.append(notes) }
            let planned = session.plannedExercises.first { $0.id == row.id } ?? session.plannedExercises.first { $0.exerciseId == row.exercise.id }
            if let rpe = planned?.targetRPE, !(row.notes ?? "").contains("Target RPE") { targets.append("Target RPE \(rpe.formatted())") }
            lines.append(row.exercise.name + ": " + targets.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }
    public static func dateLabel(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}

public extension PlanEditingService {
    /// Pure transformation. Persistence and confirmation are deliberately separate.
    static func applyingLegacy(_ request: PlanEditRequest, to original: ProgressionPlan, settings: PlanConfiguration,
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
                programmingWeekID: base.programmingWeekID, programmingWeekNumber: base.programmingWeekNumber, insertedGroupID: group,
                exerciseSnapshot: base.exerciseSnapshot, customLabel: base.customLabel)
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
                ? try shift((plan.targetEndDate ?? entries.compactMap { $0.session.scheduledDate }.max()).map { CalendarWeekBucketer.weekStart(of: $0) }, 7)
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
            if request.operation == .changeTargets && request.sets == nil && request.reps == nil && request.weightKg == nil && request.restSeconds == nil && request.targetRPE == nil {
                throw PlanEditError("Specify at least one target to change.")
            }
            var matched = 0
            for i in selected {
                var s = try normal(entries[i].session)
                let priorPolicy = entries[i].session.deloadPrescription
                let wasDeload = entries[i].session.isDeload
                if request.operation == .changeTemplate {
                    guard let template = templates.first(where: { $0.id == request.templateID }), !template.exercises.isEmpty else { throw PlanEditError("Template not found or empty.") }
                    s.templateId = template.id; s.sessionLabel = template.name; s.customLabel = true
                    let previous = s.plannedExercises
                    var used = Set<UUID>()
                    var snapshot = template
                    var targets: [PlannedExerciseSet] = []
                    snapshot.exercises = template.exercises.sorted { $0.order < $1.order }.enumerated().map { index, te in
                        let baseline = plan.exercises.first { $0.exerciseId == te.exercise.id }
                        let canReuse = te.exercise.exerciseType != .bodyweightReps || baseline?.acceptsBodyweightBasis(of: te.exercise) == true
                        let prior = canReuse ? previous.first { $0.exerciseId == te.exercise.id && $0.weightRecording == te.exercise.weightRecording && $0.isWarmup == te.isWarmUp && !used.contains($0.id) } : nil
                        let p = prior ?? PlannedExerciseSet(id: te.id, planExerciseId: baseline?.id ?? UUID(),
                            exerciseId: te.exercise.id, exerciseName: te.exercise.name, sets: te.targetSets,
                            targetReps: te.targetReps ?? 0, targetWeight: te.targetWeight ?? 0, percentageOf1RM: 0,
                            restSeconds: te.restTimerSeconds ?? 120, isWarmup: te.isWarmUp, weightRecording: te.exercise.weightRecording)
                        used.insert(p.id); targets.append(p)
                        return TemplateExercise(id: p.id, exercise: te.exercise, order: index, supersetGroup: te.supersetGroup,
                            notes: te.notes, restTimerSeconds: te.restTimerSeconds, targetSets: te.targetSets,
                            targetReps: te.targetReps, targetWeight: te.targetWeight, targetDurationSeconds: te.targetDurationSeconds,
                            targetDistanceMeters: te.targetDistanceMeters, setTargets: te.setTargets, isWarmUp: te.isWarmUp)
                    }
                    s.plannedExercises = targets; s.exerciseSnapshot = snapshot
                    matched += 1
                } else {
                    for e in s.plannedExercises.indices where request.exerciseID == nil || s.plannedExercises[e].exerciseId == request.exerciseID {
                        if request.operation == .changeExercise {
                            guard request.exerciseID != nil, let replacement = exercises.first(where: { $0.id == request.replacementExerciseID && !$0.isArchived }),
                                  let weight = request.weightKg, let reps = request.reps else { throw PlanEditError("An exercise swap needs source/replacement IDs and explicit weight_kg and reps; loads are not transferable between exercises.") }
                            s.plannedExercises[e].weightRecording = replacement.weightRecording
                            s.plannedExercises[e].exerciseId = replacement.id; s.plannedExercises[e].exerciseName = replacement.name
                            s.plannedExercises[e].planExerciseId = plan.exercises.first { $0.exerciseId == replacement.id }?.id ?? UUID()
                            s.plannedExercises[e].targetWeight = weight; s.plannedExercises[e].targetReps = reps
                        }
                        if let sets = request.sets { s.plannedExercises[e].sets = sets }
                        if let reps = request.reps { s.plannedExercises[e].targetReps = reps }
                        if let weight = request.weightKg { s.plannedExercises[e].targetWeight = (weight * 100).rounded() / 100 }
                        if let rest = request.restSeconds { s.plannedExercises[e].restSeconds = rest }
                        if let rpe = request.targetRPE { s.plannedExercises[e].targetRPE = rpe }
                        // Explicit user targets are fixed, not silently replaced by the next APRE replay.
                        if request.sets != nil || request.reps != nil || request.weightKg != nil || request.operation == .changeExercise {
                            s.plannedExercises[e].percentageOf1RM = 0
                            s.plannedExercises[e].isUserOverride = true
                        }
                        matched += 1
                    }
                }
                if let policy = priorPolicy { PlanDeloadPolicy.apply(to: &s, weightPercentage: policy.weightPercentage, restPercentage: policy.restPercentage, omitted: policy.omitted) }
                if wasDeload && priorPolicy == nil { try deload(&s) }
                entries[i].session = s
            }
            guard matched > 0 else { throw PlanEditError("That exercise is not present in the selected sessions.") }
        default: throw PlanEditError("Unsupported legacy operation.")
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

/// A retained session or a new template-based session at an explicit local date.
public struct PlanSessionPlacement: Codable, Equatable, Sendable {
    public var sessionID: UUID?
    public var templateID: UUID?
    public var date: Date
    public var label: String?
    public init(sessionID: UUID? = nil, templateID: UUID? = nil, date: Date, label: String? = nil) {
        self.sessionID = sessionID; self.templateID = templateID; self.date = date; self.label = label
    }
}

public struct PlanDayRule: Codable, Equatable, Sendable {
    public var sourceWeekday: Int?
    public var weekday: Int
    public var templateID: UUID?
    public init(sourceWeekday: Int? = nil, weekday: Int, templateID: UUID? = nil) {
        self.sourceWeekday = sourceWeekday; self.weekday = weekday; self.templateID = templateID
    }
}

/// Full ordered contents. Existing occurrence IDs retain their exact prescription;
/// new/replacement exercises require explicit, type-appropriate targets.
public struct PlanExercisePrescription: Codable, Equatable, Sendable {
    public var occurrenceID: UUID?
    public var exerciseID: UUID
    public var sets: Int?
    public var reps: Int?
    public var weightKg: Double?
    public var restSeconds: Int?
    public var targetRPE: Double?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var notes: String?
    public init(occurrenceID: UUID? = nil, exerciseID: UUID, sets: Int? = nil, reps: Int? = nil,
        weightKg: Double? = nil, restSeconds: Int? = nil, targetRPE: Double? = nil,
        durationSeconds: Int? = nil, distanceMeters: Double? = nil, notes: String? = nil) {
        self.occurrenceID = occurrenceID; self.exerciseID = exerciseID; self.sets = sets; self.reps = reps
        self.weightKg = weightKg; self.restSeconds = restSeconds; self.targetRPE = targetRPE
        self.durationSeconds = durationSeconds; self.distanceMeters = distanceMeters; self.notes = notes
    }
}

public struct PlanScheduleSnapshot: Codable, Equatable, Sendable {
    public var blocks: [TrainingBlock]
    public var exercises: [PlanExercise]
    public var configuration: PlanConfiguration?
    public var targetEndDate: Date?
    public var weeklyFrequency: Int
    public var trainingDays: [Int]?
    public var deloadDays: [Int]?
    public var daySchedule: [DayScheduleEntry]
    public init(_ plan: ProgressionPlan) {
        blocks = plan.blocks; exercises = plan.exercises; configuration = plan.configuration
        targetEndDate = plan.targetEndDate; weeklyFrequency = plan.weeklyFrequency
        trainingDays = plan.trainingDays; deloadDays = plan.deloadDays; daySchedule = plan.daySchedule
    }
    public func install(on plan: inout ProgressionPlan) {
        plan.blocks = blocks; plan.exercises = exercises; plan.configuration = configuration
        plan.targetEndDate = targetEndDate; plan.weeklyFrequency = weeklyFrequency
        plan.trainingDays = trainingDays; plan.deloadDays = deloadDays; plan.daySchedule = daySchedule
    }
    public var sessions: [PlannedSession] { blocks.flatMap(\.weeks).flatMap(\.sessions) }
}

public struct PlanEditRecord: Codable, Equatable, Sendable {
    public var before: PlanScheduleSnapshot
    public var after: PlanScheduleSnapshot
}

public struct PlanSessionChange: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var before: PlannedSession?
    public var after: PlannedSession?
    public var kind: String { before == nil ? "added" : after == nil ? "removed" : "changed" }
}

public extension PlanEditingService {
    static func sessions(_ plan: ProgressionPlan) -> [PlannedSession] { plan.blocks.flatMap(\.weeks).flatMap(\.sessions) }

    static func anchor(_ plan: ProgressionPlan) -> Date {
        plan.configuration?.calendarAnchorDate ?? plan.blocks.flatMap(\.weeks).compactMap(\.calendarStartDate).min() ?? CalendarWeekBucketer.weekStart(of: sessions(plan).compactMap(\.scheduledDate).min() ?? plan.startDate)
    }

    /// One journal entry and one save for an entire batch. No partial writes or
    /// regenerating a programme from its creation settings.
    static func applying(_ request: PlanEditRequest, to original: ProgressionPlan, settings: PlanConfiguration,
        templates: [WorkoutTemplate] = [], exercises: [Exercise] = [], protectedSessionIDs: Set<UUID> = [],
        operationID: UUID = UUID(), now: Date = Date()) throws -> ProgressionPlan {
        guard original.status == .active else { throw PlanEditError("Only an active plan can be edited.") }
        let operations = request.operation == .batch ? (request.operations ?? []) : [request]
        guard !operations.isEmpty, operations.count <= 50, !operations.contains(where: { $0.operation == .batch || $0.operations != nil }) else {
            throw PlanEditError("Supply 1–50 operations; nested batches are not supported.")
        }
        var plan = original
        for operation in operations {
            plan = try applyOperation(operation, to: plan, settings: settings, templates: templates, exercises: exercises,
                protected: protectedSessionIDs, now: now)
        }
        // Newly added exercises get an explicit, unknown strength baseline rather
        // than borrowing another movement's 1RM. Fixed user targets still execute.
        for target in sessions(plan).flatMap(\.plannedExercises) where request.operation != .undoEdit && !plan.exercises.contains(where: { $0.exerciseId == target.exerciseId }) {
            guard let exercise = exercises.first(where: { $0.id == target.exerciseId }), [.weightedReps, .bodyweightReps].contains(exercise.exerciseType) else { continue }
            plan.exercises.append(PlanExercise(id: target.planExerciseId, exerciseId: exercise.id, exerciseName: exercise.name,
                primaryMuscleGroup: exercise.primaryMuscleGroup, category: exercise.category, estimated1RM: 0,
                oneRMSource: .estimated, current1RM: 0, isCompound: [.barbell, .dumbbell].contains(exercise.category), order: plan.exercises.count,
                weightRecording: target.weightRecording, bodyweightFactor: exercise.exerciseType == .bodyweightReps ? exercise.resolvedBodyweightFactor : nil))
        }
        try validateResult(plan, original: original, protected: protectedSessionIDs)
        guard PlanScheduleSnapshot(plan) != PlanScheduleSnapshot(original) else { throw PlanEditError("The requested change makes no difference.") }
        plan.adjustments = original.adjustments
        var adjustment = PlanAdjustment(id: operationID, adjustmentType: .reforecast, trigger: .userManual,
            description: request.operation.displayName, previousValues: ["endDate": dateLabel(original.targetEndDate)],
            newValues: ["endDate": dateLabel(plan.targetEndDate)], appliedAt: now, wasAccepted: true)
        adjustment.editRecord = .init(before: .init(original), after: .init(plan))
        plan.adjustments.append(adjustment)
        // Keep a bounded undo journal without removing the lightweight audit trail.
        let journalIndices = plan.adjustments.indices.filter { plan.adjustments[$0].editRecord != nil }
        for i in journalIndices.dropLast(10) { plan.adjustments[i].editRecord = nil }
        plan.updatedAt = now
        return plan
    }

    static func validateResult(_ plan: ProgressionPlan, original: ProgressionPlan, protected: Set<UUID>) throws {
        let all = sessions(plan)
        guard all.count <= 1000, Set(all.map(\.id)).count == all.count else { throw PlanEditError("A plan must have unique session IDs and at most 1,000 sessions.") }
        guard plan.totalWeeks <= 156 else { throw PlanEditError("The schedule exceeds 156 calendar weeks.") }
        let newByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        for session in sessions(original) where session.isCompleted || protected.contains(session.id) {
            guard newByID[session.id] == session else { throw PlanEditError("Completed and in-progress sessions cannot be changed or removed.") }
        }
        for s in all {
            guard let date = s.scheduledDate, date >= anchor(plan),
                  CalendarWeekBucketer.mondayCalendar.component(.weekday, from: date) == s.dayOfWeek else {
                throw PlanEditError("Every session needs a valid date and matching weekday within the plan.")
            }
            guard Set(s.plannedExercises.map(\.id)).count == s.plannedExercises.count else { throw PlanEditError("Exercise occurrence IDs must be unique within a session.") }
        }
    }

    static func changes(from before: PlanScheduleSnapshot, to after: PlanScheduleSnapshot) -> [PlanSessionChange] {
        let old = Dictionary(uniqueKeysWithValues: before.sessions.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.sessions.map { ($0.id, $0) })
        return Set(old.keys).union(new.keys).compactMap { id in
            old[id] == new[id] ? nil : .init(id: id, before: old[id], after: new[id])
        }.sorted {
            let a = $0.after?.scheduledDate ?? $0.before?.scheduledDate ?? .distantPast
            let b = $1.after?.scheduledDate ?? $1.before?.scheduledDate ?? .distantPast
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
    }

    /// Preserve the calendar anchor/end even when the first/last/all sessions in a
    /// week are removed. Empty weeks are real calendar periods, not missed workouts.
    static func normalizeCalendar(_ plan: inout ProgressionPlan, anchor start: Date, end: Date) {
        let cal = CalendarWeekBucketer.mondayCalendar
        // Calendar buckets do not prove the original programming duration of a legacy plan.
        plan.configuration?.calendarAnchorDate = start
        let all = plan.blocks.enumerated().flatMap { b, block in block.weeks.flatMap { $0.sessions.map { (b, $0) } } }
        let previousWeeks = plan.blocks.map(\.weeks)
        for b in plan.blocks.indices { plan.blocks[b].weeks = [] }
        let count = max(1, (cal.dateComponents([.day], from: start, to: CalendarWeekBucketer.weekStart(of: end)).day ?? 0) / 7 + 1)
        for number in 1...count {
            let date = cal.date(byAdding: .day, value: (number - 1) * 7, to: start)!
            let weekEntries = all.filter { CalendarWeekBucketer.weekStart(of: $0.1.scheduledDate ?? start) == date }
            var owners = Set(weekEntries.map(\.0))
            if owners.isEmpty {
                let owner = previousWeeks.indices.last { index in
                    previousWeeks[index].contains { ($0.weekStartDate ?? .distantFuture) <= date }
                } ?? 0
                owners.insert(owner)
            }
            for b in owners.sorted() where plan.blocks.indices.contains(b) {
                let prior = previousWeeks[b].first { $0.weekStartDate == date }
                var values: [PlannedSession] = []
                for entry in weekEntries where entry.0 == b { values.append(entry.1) }
                values.sort { left, right in
                    if left.scheduledDate == right.scheduledDate { return left.id.uuidString < right.id.uuidString }
                    return (left.scheduledDate ?? .distantFuture) < (right.scheduledDate ?? .distantFuture)
                }
                plan.blocks[b].weeks.append(.init(id: prior?.id ?? UUID(), weekNumber: plan.blocks[b].weeks.count + 1,
                    absoluteWeekNumber: number, sessions: values,
                    isDeload: !values.isEmpty && values.allSatisfy(\.isDeload), isCompleted: prior?.isCompleted ?? false,
                    completedAt: prior?.completedAt, calendarStartDate: date))
            }
        }
        for b in plan.blocks.indices { plan.blocks[b].durationWeeks = plan.blocks[b].weeks.count }
        plan.targetEndDate = end
    }
}

private extension PlanEditingService {
    static func normalSession(_ value: PlannedSession, in plan: ProgressionPlan) throws -> PlannedSession {
        var s = value
        if s.isDeload {
            if s.deloadPrescription != nil { try PlanDeloadPolicy.remove(from: &s) }
            else {
                let candidates = sessions(plan).filter { !$0.isDeload && $0.dayOfWeek == s.dayOfWeek && $0.plannedExercises.map(\.exerciseId) == s.plannedExercises.map(\.exerciseId) }
                guard let source = candidates.min(by: { abs(($0.scheduledDate ?? .distantPast).timeIntervalSince(s.scheduledDate ?? .distantPast)) < abs(($1.scheduledDate ?? .distantPast).timeIntervalSince(s.scheduledDate ?? .distantPast)) }) else {
                    throw PlanEditError("This legacy deload has no recoverable normal prescription. Copy a normal session instead.")
                }
                s.plannedExercises = source.plannedExercises; s.sessionLabel = source.sessionLabel; s.isDeload = false
            }
        }
        return s
    }

    static func materialize(_ value: PlannedSession, in plan: ProgressionPlan, templates: [WorkoutTemplate], exercises: [Exercise], settings: PlanConfiguration? = nil) throws -> PlannedSession {
        var s = try normalSession(value, in: plan)
        if s.exerciseSnapshot == nil {
            let resolved = s.resolvedTemplate(linked: templates.first { $0.id == s.templateId }, exercises: exercises, planExercises: plan.exercises)
            var snapshot = resolved
            var used = Set<UUID>()
            s.plannedExercises = resolved.exercises.sorted { $0.order < $1.order }.enumerated().map { index, te in
                let existing = s.plannedExercises.first { $0.exerciseId == te.exercise.id && !used.contains($0.id) }
                var p = existing ?? PlannedExerciseSet(id: te.id, planExerciseId: plan.exercises.first { $0.exerciseId == te.exercise.id }?.id ?? UUID(),
                    exerciseId: te.exercise.id, exerciseName: te.exercise.name, sets: te.targetSets, targetReps: te.targetReps ?? 0,
                    targetWeight: te.targetWeight ?? 0, percentageOf1RM: 0, restSeconds: te.restTimerSeconds ?? 120,
                    isWarmup: te.isWarmUp, notes: te.notes, weightRecording: te.exercise.weightRecording)
                if used.contains(p.id) { p = PlannedExerciseSet(planExerciseId: p.planExerciseId, exerciseId: p.exerciseId, exerciseName: p.exerciseName,
                    sets: p.sets, targetReps: p.targetReps, targetWeight: p.targetWeight, percentageOf1RM: p.percentageOf1RM,
                    restSeconds: p.restSeconds, weightRecording: p.weightRecording) }
                used.insert(p.id)
                snapshot.exercises[index] = TemplateExercise(id: p.id, exercise: te.exercise, order: index,
                    supersetGroup: te.supersetGroup, notes: te.notes, restTimerSeconds: te.restTimerSeconds,
                    targetSets: te.targetSets, targetReps: te.targetReps, targetWeight: te.targetWeight,
                    targetDurationSeconds: te.targetDurationSeconds, targetDistanceMeters: te.targetDistanceMeters,
                    setTargets: te.setTargets, isWarmUp: te.isWarmUp)
                return p
            }
            s.exerciseSnapshot = snapshot
        }
        if let policy = value.deloadPrescription {
            PlanDeloadPolicy.apply(to: &s, weightPercentage: policy.weightPercentage, restPercentage: policy.restPercentage, omitted: policy.omitted)
        } else if value.isDeload {
            let configuration = settings ?? plan.configuration ?? .init(durationWeeks: max(1, plan.totalWeeks))
            PlanDeloadPolicy.apply(to: &s, weightPercentage: configuration.deloadWeightPercentage, restPercentage: configuration.deloadRestPercentage)
        }
        return s
    }

    static func cleanLabel(_ session: inout PlannedSession, templates: [WorkoutTemplate], explicit: String? = nil) throws {
        if let explicit {
            let text = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 120 else { throw PlanEditError("A session name must contain 1–120 characters.") }
            session.sessionLabel = text; session.customLabel = true
            if session.deloadPrescription != nil { session.deloadPrescription?.normalLabel = text }
            return
        }
        guard session.customLabel != true else { return }
        let normal = session.deloadPrescription?.normalLabel ?? session.displayLabel
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let pieces = normal.components(separatedBy: " - ")
        guard pieces.contains(where: { weekdays.contains($0) }) else { return }
        let remaining = pieces.filter { !weekdays.contains($0) }.joined(separator: " - ")
        let label = templates.first { $0.id == session.templateId }?.name ?? (remaining.isEmpty ? "Workout" : remaining)
        session.sessionLabel = label
        if session.deloadPrescription != nil { session.deloadPrescription?.normalLabel = label }
    }

    static func syncSnapshot(_ session: inout PlannedSession, exercises: [Exercise]) throws {
        guard var snapshot = session.exerciseSnapshot else { return }
        let normal = session.deloadPrescription?.normalExercises ?? session.plannedExercises
        snapshot.exercises = try normal.enumerated().map { index, p in
            let matches = snapshot.exercises.filter { $0.exercise.id == p.exerciseId }
            let source = snapshot.exercises.first { $0.id == p.id } ?? (matches.count == 1 ? matches.first : nil)
            guard var exercise = source?.exercise.id == p.exerciseId ? source?.exercise : exercises.first(where: { $0.id == p.exerciseId }) else {
                throw PlanEditError("An exercise is no longer available. Refresh the plan and exercise library.")
            }
            exercise.weightRecording = p.weightRecording
            let sameExercise = source?.exercise.id == p.exerciseId
            return TemplateExercise(id: p.id, exercise: exercise, order: index, supersetGroup: sameExercise ? source?.supersetGroup : nil,
                notes: p.notes ?? (sameExercise ? source?.notes : nil), restTimerSeconds: p.restSeconds,
                targetSets: p.sets, targetReps: p.targetReps > 0 ? p.targetReps : nil,
                targetWeight: [.weightedReps, .bodyweightReps, .weightedCardio].contains(exercise.exerciseType) ? p.targetWeight : nil,
                targetDurationSeconds: sameExercise ? source?.targetDurationSeconds : nil,
                targetDistanceMeters: sameExercise ? source?.targetDistanceMeters : nil,
                setTargets: sameExercise && p.isUserOverride != true ? (source?.setTargets ?? []) : [], isWarmUp: p.isWarmup)
        }
        session.exerciseSnapshot = snapshot
    }

    static func applyOperation(_ request: PlanEditRequest, to original: ProgressionPlan, settings: PlanConfiguration,
        templates: [WorkoutTemplate], exercises: [Exercise], protected: Set<UUID>, now: Date) throws -> ProgressionPlan {
        let cal = CalendarWeekBucketer.mondayCalendar
        let today = cal.startOfDay(for: now)
        let start = anchor(original)
        var end = original.targetEndDate ?? sessions(original).compactMap(\.scheduledDate).max() ?? start
        var plan = original
        var policy = settings
        policy.deloadWeightPercentage = request.deloadWeightPercentage ?? settings.deloadWeightPercentage
        policy.deloadRestPercentage = request.deloadRestPercentage ?? settings.deloadRestPercentage
        guard (10...100).contains(policy.deloadWeightPercentage), (25...100).contains(policy.deloadRestPercentage) else {
            throw PlanEditError("Deload weight must be 10–100% and rest 25–100% of normal.")
        }
        if let week = request.week, week < 1 || week > original.totalWeeks { throw PlanEditError("Choose an existing calendar week.") }
        if let last = request.endWeek, last < (request.week ?? 1) || last > original.totalWeeks { throw PlanEditError("Invalid final calendar week.") }
        if let rpe = request.targetRPE, !rpe.isFinite || !(1...10).contains(rpe) { throw PlanEditError("Target RPE must be 1–10.") }
        struct Entry { var block: Int; var week: Int; var session: PlannedSession }
        var entries = plan.blocks.enumerated().flatMap { b, block in block.weeks.flatMap { w in w.sessions.map { Entry(block: b, week: w.absoluteWeekNumber, session: $0) } } }
        let targetWeek = request.week ?? request.sessionID.flatMap { id in entries.first { $0.session.id == id }?.week }
        func open(_ s: PlannedSession) -> Bool { !s.isCompleted && !protected.contains(s.id) }
        func future(_ s: PlannedSession) -> Bool { open(s) && (s.scheduledDate ?? .distantPast) >= today }
        func ensure(_ indices: [Int], allowPast: Bool = false) throws {
            guard !indices.isEmpty else { throw PlanEditError("No sessions match that scope.") }
            guard indices.allSatisfy({ allowPast ? open(entries[$0].session) : future(entries[$0].session) }) else {
                throw PlanEditError("The selection includes completed, active or past sessions. Select only remaining sessions, or explicitly correct an overdue session.")
            }
        }
        func date(_ source: Date, plus days: Int) -> Date { cal.date(byAdding: .day, value: days, to: source)! }
        func weekDate(_ number: Int) -> Date { date(start, plus: (number - 1) * 7) }
        var selected = entries.indices.filter { i in
            let matches: Bool
            if let ids = request.sessionIDs { matches = ids.contains(entries[i].session.id) }
            else {
                switch request.scope {
                case .session: matches = entries[i].session.id == request.sessionID
                case .week: matches = entries[i].week == targetWeek
                case .remaining: matches = entries[i].week >= (targetWeek ?? Int.max) && future(entries[i].session)
                }
            }
            return matches && (request.endWeek == nil || entries[i].week <= request.endWeek!) && (request.remainingOnly != true || future(entries[i].session))
        }
        if let ids = request.sessionIDs {
            guard !ids.isEmpty, Set(ids).count == ids.count, Set(ids).isSubset(of: Set(entries.map { $0.session.id })) else { throw PlanEditError("Select unique session IDs from the current plan.") }
        }
        func newSession(templateID: UUID, at date: Date, label: String?) throws -> PlannedSession {
            guard let template = templates.first(where: { $0.id == templateID }), !template.exercises.isEmpty else { throw PlanEditError("Choose a nonempty workout template.") }
            var s = PlannedSession(dayOfWeek: cal.component(.weekday, from: date), scheduledDate: cal.startOfDay(for: date),
                sessionLabel: template.name, templateId: template.id, customLabel: true)
            s = try materialize(s, in: plan, templates: templates, exercises: exercises, settings: policy)
            try cleanLabel(&s, templates: templates, explicit: label)
            return s
        }
        func deload(_ s: inout PlannedSession, enabled: Bool) throws {
            if enabled {
                if s.isDeload && s.deloadPrescription == nil { s = try normalSession(s, in: plan) }
                PlanDeloadPolicy.apply(to: &s, weightPercentage: policy.deloadWeightPercentage, restPercentage: policy.deloadRestPercentage)
            } else if s.isDeload { s = try normalSession(s, in: plan) }
        }
        func putEntries() {
            let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.session.id, $0.session) })
            let existingIDs = Set(sessions(plan).map(\.id))
            for b in plan.blocks.indices {
                for w in plan.blocks[b].weeks.indices { plan.blocks[b].weeks[w].sessions = plan.blocks[b].weeks[w].sessions.compactMap { byID[$0.id] } }
                let added = entries.filter { $0.block == b && !existingIDs.contains($0.session.id) }.map(\.session)
                if !added.isEmpty { plan.blocks[b].weeks.append(.init(weekNumber: 1, absoluteWeekNumber: 1, sessions: added)) }
            }
        }
        switch request.operation {
        case .undoEdit:
            guard let record = original.adjustments.first(where: { $0.id == request.editID })?.editRecord else { throw PlanEditError("This edit is not in the undo history.") }
            guard PlanScheduleSnapshot(original) == record.after else { throw PlanEditError("The plan changed since this edit. Restore an individual removed session or request a new edit instead.") }
            try validateRestoration(record.before, replacing: record.after, protected: protected, today: today)
            record.before.install(on: &plan)
            return plan
        case .restoreSession:
            guard let record = original.adjustments.first(where: { $0.id == request.editID })?.editRecord,
                  let source = record.before.sessions.first(where: { $0.id == request.sessionID }),
                  !record.after.sessions.contains(where: { $0.id == source.id }), !entries.contains(where: { $0.session.id == source.id }),
                  !source.isCompleted, !protected.contains(source.id) else { throw PlanEditError("Choose a removed, unperformed session from the edit history.") }
            var s = source
            if let newDate = request.newDate { s.scheduledDate = cal.startOfDay(for: newDate); s.dayOfWeek = cal.component(.weekday, from: newDate) }
            guard (s.scheduledDate ?? .distantPast) >= today else { throw PlanEditError("Choose today or a future date for the restored session.") }
            let oldBlock = record.before.blocks.firstIndex { $0.weeks.contains { $0.sessions.contains { $0.id == source.id } } } ?? 0
            entries.append(.init(block: min(oldBlock, max(0, plan.blocks.count - 1)), week: 1, session: s))
        case .addSession, .duplicateSession:
            guard let newDate = request.newDate, cal.startOfDay(for: newDate) >= today else { throw PlanEditError("Supply today or a future new_date.") }
            var s: PlannedSession
            var owner = 0
            if request.operation == .duplicateSession {
                guard let source = entries.first(where: { $0.session.id == request.sessionID }) else { throw PlanEditError("Source session not found.") }
                let normal = try normalSession(source.session, in: plan)
                s = PlannedSession(dayOfWeek: cal.component(.weekday, from: newDate), scheduledDate: cal.startOfDay(for: newDate),
                    dupSessionType: normal.dupSessionType, sessionLabel: normal.sessionLabel, plannedExercises: normal.plannedExercises,
                    estimatedDurationMinutes: normal.estimatedDurationMinutes, templateId: normal.templateId, notes: normal.notes,
                    programmingWeekID: normal.programmingWeekID, programmingWeekNumber: normal.programmingWeekNumber,
                    exerciseSnapshot: normal.exerciseSnapshot, customLabel: normal.customLabel)
                owner = source.block
                try cleanLabel(&s, templates: templates, explicit: request.label)
            } else {
                guard let tid = request.templateID else { throw PlanEditError("Add session requires template_id.") }
                s = try newSession(templateID: tid, at: newDate, label: request.label)
                owner = plan.blocks.indices.last { b in plan.blocks[b].weeks.contains { ($0.weekStartDate ?? .distantFuture) <= newDate } } ?? 0
            }
            if let enabled = request.isDeload { try deload(&s, enabled: enabled) }
            entries.append(.init(block: owner, week: targetWeek ?? 1, session: s))
        case .removeSessions:
            selected = entries.indices.filter { i in request.sessionIDs?.contains(entries[i].session.id) ?? (entries[i].session.id == request.sessionID) }
            guard request.sessionID != nil || request.sessionIDs != nil else { throw PlanEditError("Remove sessions requires explicit session IDs.") }
            let correction = !(request.correctionReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            try ensure(selected, allowPast: correction)
            let ids = Set(selected.map { entries[$0].session.id }); entries.removeAll { ids.contains($0.session.id) }
        case .updateSession:
            try ensure(selected)
            guard request.label != nil || request.notes != nil else { throw PlanEditError("Provide a name or notes to update.") }
            for i in selected {
                try cleanLabel(&entries[i].session, templates: templates, explicit: request.label)
                if let notes = request.notes { entries[i].session.notes = notes }
            }
        case .setWeekSchedule, .changeSchedule:
            guard let first = targetWeek else { throw PlanEditError("Choose the first calendar week.") }
            let last = request.operation == .changeSchedule ? (request.endWeek ?? original.totalWeeks) : first
            if request.operation == .changeSchedule {
                guard let rules = request.weeklySchedule, rules.count <= 7,
                      Set(rules.map(\.weekday)).count == rules.count,
                      rules.allSatisfy({ (1...7).contains($0.weekday) && ($0.sourceWeekday.map { (1...7).contains($0) } ?? true) }) else {
                    throw PlanEditError("Provide up to seven unique weekdays and valid source weekdays.")
                }
            }
            for number in first...last {
                let current = entries.filter { $0.week == number }
                let placements: [PlanSessionPlacement]
                if request.operation == .setWeekSchedule {
                    guard let schedule = request.schedule, schedule.count <= 14 else { throw PlanEditError("Supply schedule, including [] for a rest week.") }
                    placements = schedule
                } else {
                    placements = try (request.weeklySchedule ?? []).map { rule in
                        let candidates = current.filter { $0.session.dayOfWeek == rule.sourceWeekday }
                        if rule.sourceWeekday != nil && candidates.count != 1 { throw PlanEditError("A source weekday must match exactly one session in every selected week. Use explicit week schedules for exceptions.") }
                        guard rule.templateID != nil || !candidates.isEmpty else { throw PlanEditError("Each day needs a source weekday or template.") }
                        return .init(sessionID: candidates.first?.session.id, templateID: rule.templateID,
                            date: date(weekDate(number), plus: (rule.weekday + 5) % 7))
                    }
                }
                let effectivePlacements: [PlanSessionPlacement]
                if request.operation == .changeSchedule && request.remainingOnly == true {
                    effectivePlacements = placements.filter { placement in
                        if let id = placement.sessionID, let source = current.first(where: { $0.session.id == id }) { return future(source.session) }
                        return cal.startOfDay(for: placement.date) >= today
                    }
                } else { effectivePlacements = placements }
                let retainedIDs = effectivePlacements.compactMap(\.sessionID)
                guard Set(retainedIDs).count == retainedIDs.count else { throw PlanEditError("A session can only appear once in the new schedule.") }
                guard placements.allSatisfy({ CalendarWeekBucketer.weekStart(of: $0.date) == weekDate(number) }) else { throw PlanEditError("Every date must be in the selected calendar week.") }
                let locked = current.filter { !future($0.session) }
                if !locked.isEmpty && request.remainingOnly != true { throw PlanEditError("This week has past, completed or active sessions. Use remaining_only to preserve them and edit only upcoming sessions.") }
                guard !retainedIDs.contains(where: { id in locked.contains { $0.session.id == id } }) else { throw PlanEditError("Do not include protected or past sessions in the replacement schedule; they are preserved automatically.") }
                var replacement = locked
                for placement in effectivePlacements {
                    guard cal.startOfDay(for: placement.date) >= today else { throw PlanEditError("New schedule dates must be today or later.") }
                    var entry: Entry
                    if let id = placement.sessionID {
                        guard var existing = current.first(where: { $0.session.id == id }) else { throw PlanEditError("Retained IDs must belong to the selected week.") }
                        existing.session.scheduledDate = cal.startOfDay(for: placement.date)
                        existing.session.dayOfWeek = cal.component(.weekday, from: placement.date)
                        if let tid = placement.templateID {
                            let previousPolicy = existing.session.deloadPrescription
                            let new = try newSession(templateID: tid, at: placement.date, label: placement.label)
                            existing.session.templateId = tid; existing.session.plannedExercises = new.plannedExercises
                            existing.session.exerciseSnapshot = new.exerciseSnapshot; existing.session.sessionLabel = new.sessionLabel
                            existing.session.customLabel = new.customLabel; existing.session.isDeload = false; existing.session.deloadPrescription = nil
                            if let previousPolicy { PlanDeloadPolicy.apply(to: &existing.session, weightPercentage: previousPolicy.weightPercentage, restPercentage: previousPolicy.restPercentage) }
                        }
                        entry = existing
                    } else {
                        guard let tid = placement.templateID else { throw PlanEditError("New scheduled sessions require template_id.") }
                        entry = .init(block: current.first?.block ?? 0, week: number, session: try newSession(templateID: tid, at: placement.date, label: placement.label))
                    }
                    entry.session.isSkipped = false; entry.session.skippedAt = nil
                    entry.session.deloadPrescription?.omitted = false
                    try cleanLabel(&entry.session, templates: templates, explicit: placement.label)
                    if let enabled = request.isDeload { try deload(&entry.session, enabled: enabled) }
                    replacement.append(entry)
                }
                entries.removeAll { $0.week == number }; entries.append(contentsOf: replacement)
            }
            if request.operation == .changeSchedule, last == original.totalWeeks {
                let rules = request.weeklySchedule ?? []
                plan.weeklyFrequency = rules.count; plan.trainingDays = rules.map(\.weekday).sorted()
                plan.daySchedule = rules.map { rule in
                    let source = original.daySchedule.first { $0.dayOfWeek == rule.sourceWeekday }
                    let tid = rule.templateID ?? source?.templateId
                    return DayScheduleEntry(dayOfWeek: rule.weekday, templateId: tid,
                        templateName: templates.first { $0.id == tid }?.name, exerciseIds: source?.exerciseIds ?? [])
                }
            }
        case .shiftSchedule, .insertRestWeek:
            let from = request.newDate.map { cal.startOfDay(for: $0) } ?? targetWeek.map(weekDate)
            guard let from, from >= today else { throw PlanEditError("Choose today or a future shift/insertion date.") }
            guard from <= date(end, plus: request.operation == .insertRestWeek ? 7 : 0) else { throw PlanEditError("The shift starts after this plan. Extend the plan instead.") }
            let days = request.operation == .insertRestWeek ? request.weeks * 7 : (request.days ?? 0)
            guard days != 0, abs(days) <= 364, request.operation != .insertRestWeek || (1...12).contains(request.weeks) else { throw PlanEditError("Use a nonzero shift up to 364 days, or 1–12 rest weeks.") }
            if request.operation == .insertRestWeek && CalendarWeekBucketer.weekStart(of: from) != from { throw PlanEditError("Insert a rest week at a Monday calendar boundary.") }
            selected = entries.indices.filter { (entries[$0].session.scheduledDate ?? .distantPast) >= from }
            if !selected.isEmpty { try ensure(selected) }
            for i in selected {
                let newDate = date(entries[i].session.scheduledDate!, plus: days)
                guard newDate >= today, newDate >= start else { throw PlanEditError("The shift would move training into the past.") }
                entries[i].session.scheduledDate = newDate; entries[i].session.dayOfWeek = cal.component(.weekday, from: newDate)
                try cleanLabel(&entries[i].session, templates: templates)
            }
            end = max(start, date(end, plus: days))
        case .shortenPlan:
            guard let finish = request.newDate, cal.startOfDay(for: finish) >= today, finish >= start, finish < end else { throw PlanEditError("Choose an earlier finish date that is today or later.") }
            selected = entries.indices.filter { (entries[$0].session.scheduledDate ?? .distantPast) > cal.startOfDay(for: finish) }
            if !selected.isEmpty { try ensure(selected) }
            let ids = Set(selected.map { entries[$0].session.id }); entries.removeAll { ids.contains($0.session.id) }
            end = cal.startOfDay(for: finish)
        case .setSessionExercises:
            try ensure(selected)
            guard let contents = request.contents, !contents.isEmpty, contents.count <= 50 else { throw PlanEditError("Supply 1–50 ordered exercises. Remove the session for a rest day.") }
            for i in selected {
                var s = try materialize(entries[i].session, in: plan, templates: templates, exercises: exercises, settings: policy)
                let savedPolicy = s.deloadPrescription
                s = try normalSession(s, in: plan)
                try replaceContents(contents, in: &s, plan: plan, exercises: exercises)
                if let savedPolicy { PlanDeloadPolicy.apply(to: &s, weightPercentage: savedPolicy.weightPercentage, restPercentage: savedPolicy.restPercentage, omitted: savedPolicy.omitted) }
                entries[i].session = s
            }
        default:
            // Legacy operations retain their public API and saved proposal decoding.
            if request.remainingOnly == true || request.endWeek != nil || request.sessionIDs != nil {
                let scoped = selected.map { entries[$0].session.id }
                guard !scoped.isEmpty else { throw PlanEditError("No sessions match that scope.") }
                guard [.convertDeload, .removeDeload, .changeTargets, .changeTemplate, .changeExercise, .skipSession, .updateSession].contains(request.operation) else { throw PlanEditError("This operation requires a whole week or a single session.") }
                for id in scoped {
                    var one = request; one.sessionID = id; one.sessionIDs = nil; one.scope = .session; one.remainingOnly = nil; one.endWeek = nil
                    plan = try applyOperation(one, to: plan, settings: policy, templates: templates, exercises: exercises, protected: protected, now: now)
                }
                return plan
            }
            if [.changeTemplate, .changeExercise, .changeTargets].contains(request.operation) {
                try ensure(selected)
                for i in selected {
                    entries[i].session = try materialize(entries[i].session, in: plan, templates: templates, exercises: exercises, settings: policy)

                }
                putEntries()
            }
            let legacyNow: Date
            if [.rescheduleSession, .skipSession].contains(request.operation) {
                // Rescheduling or marking an overdue unperformed workout is legitimate;
                // completed/in-progress protection still applies inside the service.
                let earliest = selected.compactMap { entries[$0].session.scheduledDate }.min() ?? now
                legacyNow = min(now, earliest)
                if request.operation == .rescheduleSession, (request.newDate ?? .distantPast) < today { throw PlanEditError("Choose today or a future date.") }
            } else { legacyNow = now }
            plan = try applyingLegacy(request, to: plan, settings: policy, templates: templates, exercises: exercises, protectedSessionIDs: protected, now: legacyNow)
            for b in plan.blocks.indices { for w in plan.blocks[b].weeks.indices { for i in plan.blocks[b].weeks[w].sessions.indices {
                var s = plan.blocks[b].weeks[w].sessions[i]
                if let prior = entries.first(where: { $0.session.id == s.id }), prior.session != s {
                    if [.rescheduleSession, .changeTemplate].contains(request.operation) { try cleanLabel(&s, templates: templates) }
                    try syncSnapshot(&s, exercises: exercises)
                }
                plan.blocks[b].weeks[w].sessions[i] = s
            } } }
            switch request.operation {
            case .insertDeload, .repeatWeek, .extendPlan: end = date(end, plus: request.weeks * 7)
            case .removeDeload:
                let retained = Set(sessions(plan).map(\.id))
                if sessions(original).contains(where: { $0.insertedGroupID != nil && !retained.contains($0.id) }) { end = date(end, plus: -7) }
            default: break
            }
            let latest = sessions(plan).compactMap(\.scheduledDate).max() ?? start
            normalizeCalendar(&plan, anchor: start, end: max(end, latest))
            return plan
        }
        if plan.blocks.isEmpty { plan.blocks = [.init(name: "Training", order: 0, durationWeeks: 1, weeks: [])] }
        putEntries()
        normalizeCalendar(&plan, anchor: start, end: max(end, entries.compactMap { $0.session.scheduledDate }.max() ?? start))
        return plan
    }

    static func validateRestoration(_ before: PlanScheduleSnapshot, replacing after: PlanScheduleSnapshot, protected: Set<UUID>, today: Date) throws {
        for change in changes(from: after, to: before) {
            let s = change.after ?? change.before!
            guard !s.isCompleted, !protected.contains(s.id), (s.scheduledDate ?? .distantPast) >= today,
                  !(change.before?.isCompleted ?? false) else { throw PlanEditError("Undo would alter completed, active or past training. Restore a future session individually instead.") }
        }
    }
}

private extension PlanEditingService {
    static func replaceContents(_ contents: [PlanExercisePrescription], in session: inout PlannedSession,
        plan: ProgressionPlan, exercises: [Exercise]) throws {
        guard var snapshot = session.exerciseSnapshot else { throw PlanEditError("Resolve the session before editing its contents.") }
        let ids = contents.compactMap(\.occurrenceID)
        guard Set(ids).count == ids.count else { throw PlanEditError("An exercise occurrence can appear only once. Omit occurrence_id to add another occurrence.") }
        var targets: [PlannedExerciseSet] = []
        var rows: [TemplateExercise] = []
        for (index, item) in contents.enumerated() {
            let source = item.occurrenceID.flatMap { id in snapshot.exercises.first { $0.id == id } }
            if item.occurrenceID != nil && source == nil { throw PlanEditError("Exercise occurrence not found in this session.") }
            let keeping = source?.exercise.id == item.exerciseID
            guard let exercise = keeping ? source?.exercise : exercises.first(where: { $0.id == item.exerciseID && !$0.isArchived }) else { throw PlanEditError("Exercise not found in the library.") }
            var p = keeping ? session.plannedExercises.first { $0.id == item.occurrenceID } : nil
            let sets = item.sets ?? (keeping ? source?.targetSets : nil)
            let reps = item.reps ?? (keeping ? source?.targetReps : nil)
            let weight = item.weightKg ?? (keeping ? source?.targetWeight : nil)
            let duration = item.durationSeconds ?? (keeping ? source?.targetDurationSeconds : nil)
            let distance = item.distanceMeters ?? (keeping ? source?.targetDistanceMeters : nil)
            guard let sets, (1...20).contains(sets) else { throw PlanEditError("Each exercise needs 1–20 sets.") }
            if let reps, !(1...100).contains(reps) { throw PlanEditError("Reps must be 1–100.") }
            if let weight, !weight.isFinite || !(0...999.99).contains(weight) { throw PlanEditError("Weight must be 0–999.99 kg in the exercise's logging convention.") }
            if let duration, !(1...86400).contains(duration) { throw PlanEditError("Duration must be 1–86,400 seconds.") }
            if let distance, !distance.isFinite || !(0.1...1_000_000).contains(distance) { throw PlanEditError("Distance must be a positive number of metres.") }
            if let rest = item.restSeconds, !(15...900).contains(rest) { throw PlanEditError("Rest must be 15–900 seconds.") }
            if let rpe = item.targetRPE, !rpe.isFinite || !(1...10).contains(rpe) { throw PlanEditError("Target RPE must be 1–10.") }
            switch exercise.exerciseType {
            case .weightedReps, .bodyweightReps:
                guard reps != nil, weight != nil else { throw PlanEditError("New rep-based exercises require explicit reps and weight_kg, including 0 for bodyweight-only work.") }
                guard duration == nil, distance == nil else { throw PlanEditError("Rep-based exercises cannot have time/distance targets.") }
            case .duration:
                guard duration != nil, item.reps == nil, item.weightKg == nil, item.distanceMeters == nil else { throw PlanEditError("A duration exercise needs seconds, not reps or load.") }
            case .distance, .cardio:
                guard duration != nil || distance != nil, item.reps == nil, item.weightKg == nil else { throw PlanEditError("This exercise needs time or distance targets.") }
            case .weightedCardio:
                guard weight != nil, duration != nil || distance != nil, item.reps == nil else { throw PlanEditError("Weighted cardio needs load and time or distance.") }
            }
            let id = source?.id ?? UUID()
            if p == nil {
                p = PlannedExerciseSet(id: id, planExerciseId: plan.exercises.first { $0.exerciseId == exercise.id }?.id ?? UUID(),
                    exerciseId: exercise.id, exerciseName: exercise.name, sets: sets, targetReps: reps ?? 0,
                    targetWeight: weight ?? 0, percentageOf1RM: 0, restSeconds: item.restSeconds ?? source?.restTimerSeconds ?? 120,
                    isUserOverride: true, weightRecording: exercise.weightRecording)
            }
            p!.sets = sets; p!.targetReps = reps ?? 0; p!.targetWeight = weight ?? 0
            if let rest = item.restSeconds { p!.restSeconds = rest }
            if let rpe = item.targetRPE { p!.targetRPE = rpe }
            if let notes = item.notes { p!.notes = notes }
            let changedTargets = !keeping || sets != source?.targetSets || reps != source?.targetReps || weight != source?.targetWeight || duration != source?.targetDurationSeconds || distance != source?.targetDistanceMeters
            if changedTargets { p!.percentageOf1RM = 0; p!.isUserOverride = true }
            targets.append(p!)
            rows.append(TemplateExercise(id: id, exercise: exercise, order: index,
                supersetGroup: keeping ? source?.supersetGroup : nil, notes: item.notes ?? (keeping ? source?.notes : nil),
                restTimerSeconds: p!.restSeconds, targetSets: sets, targetReps: reps, targetWeight: weight,
                targetDurationSeconds: duration, targetDistanceMeters: distance,
                setTargets: keeping && !changedTargets ? (source?.setTargets ?? []) : [], isWarmUp: p!.isWarmup))
        }
        snapshot.exercises = rows; session.exerciseSnapshot = snapshot; session.plannedExercises = targets
    }
}

public extension PlanEditingService {
    static func editableContents(for session: PlannedSession, plan: ProgressionPlan,
        templates: [WorkoutTemplate], exercises: [Exercise]) throws -> [PlanExercisePrescription] {
        let resolved = try materialize(session, in: plan, templates: templates, exercises: exercises)
        let normal = try normalSession(resolved, in: plan)
        return (normal.exerciseSnapshot?.exercises ?? []).sorted { $0.order < $1.order }.map { te in
            let p = normal.plannedExercises.first { $0.id == te.id }
            return .init(occurrenceID: te.id, exerciseID: te.exercise.id, sets: te.targetSets,
                reps: te.targetReps, weightKg: te.targetWeight, restSeconds: te.restTimerSeconds,
                targetRPE: p?.targetRPE, durationSeconds: te.targetDurationSeconds, distanceMeters: te.targetDistanceMeters, notes: te.notes)
        }
    }
    static func weekSummaries(_ plan: ProgressionPlan) -> [PlanWeekSummary] {
        let weeks = plan.blocks.flatMap(\.weeks)
        return Set(weeks.map(\.absoluteWeekNumber)).sorted().map { number in
            let group = weeks.filter { $0.absoluteWeekNumber == number }
            return .init(week: number, start: group.compactMap(\.weekStartDate).min(), sessions: group.flatMap(\.sessions))
        }
    }
}
