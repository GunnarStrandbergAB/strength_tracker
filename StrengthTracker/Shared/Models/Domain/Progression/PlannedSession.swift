import Foundation

/// A single planned workout session
public struct PlannedSession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var dayOfWeek: Int?
    public var scheduledDate: Date?
    public var dupSessionType: DUPSessionType?
    public var sessionLabel: String
    public var plannedExercises: [PlannedExerciseSet]
    public var estimatedDurationMinutes: Int
    public var templateId: UUID?                        // M6: For tier 2 session-linkage matching
    public var completedWorkoutId: UUID?
    public var completedAt: Date?
    public var notes: String?
    public var userWorkoutNotes: String?               // Free-text notes from completed workout
    public var isDeload: Bool
    public var isSkipped: Bool
    public var skippedAt: Date?
    public var programmingWeekID: UUID?
    public var programmingWeekNumber: Int?
    public var insertedGroupID: UUID?
    public var deloadPrescription: PlanDeloadPrescription?
    /// Full normal workout captured when its contents are edited. A linked reusable
    /// template can no longer reintroduce removed exercises into this session.
    public var exerciseSnapshot: WorkoutTemplate?
    public var customLabel: Bool?
    public var isOmitted: Bool { deloadPrescription?.omitted == true }

    public init(
        id: UUID = UUID(),
        dayOfWeek: Int? = nil,
        scheduledDate: Date? = nil,
        dupSessionType: DUPSessionType? = nil,
        sessionLabel: String,
        plannedExercises: [PlannedExerciseSet] = [],
        estimatedDurationMinutes: Int = 60,
        templateId: UUID? = nil,
        completedWorkoutId: UUID? = nil,
        completedAt: Date? = nil,
        notes: String? = nil,
        userWorkoutNotes: String? = nil,
        isDeload: Bool = false,
        isSkipped: Bool = false,
        skippedAt: Date? = nil,
        programmingWeekID: UUID? = nil, programmingWeekNumber: Int? = nil,
        insertedGroupID: UUID? = nil, deloadPrescription: PlanDeloadPrescription? = nil,
        exerciseSnapshot: WorkoutTemplate? = nil, customLabel: Bool? = nil
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.scheduledDate = scheduledDate
        self.dupSessionType = dupSessionType
        self.sessionLabel = sessionLabel
        self.plannedExercises = plannedExercises
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.templateId = templateId
        self.completedWorkoutId = completedWorkoutId
        self.completedAt = completedAt
        self.notes = notes
        self.userWorkoutNotes = userWorkoutNotes
        self.isDeload = isDeload
        self.isSkipped = isSkipped
        self.skippedAt = skippedAt
        self.programmingWeekID = programmingWeekID
        self.programmingWeekNumber = programmingWeekNumber
        self.insertedGroupID = insertedGroupID
        self.deloadPrescription = deloadPrescription
        self.exerciseSnapshot = exerciseSnapshot
        self.customLabel = customLabel
    }

    // Custom decoding for backward compatibility — existing JSON without
    // isDeload/isSkipped decodes as false (skippedAt as nil)
    private enum CodingKeys: String, CodingKey {
        case id, dayOfWeek, scheduledDate, dupSessionType, sessionLabel
        case plannedExercises, estimatedDurationMinutes, templateId
        case completedWorkoutId, completedAt, notes, userWorkoutNotes, isDeload
        case isSkipped, skippedAt, programmingWeekID, programmingWeekNumber, insertedGroupID, deloadPrescription
        case exerciseSnapshot, customLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        dayOfWeek = try container.decodeIfPresent(Int.self, forKey: .dayOfWeek)
        scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        dupSessionType = try container.decodeIfPresent(DUPSessionType.self, forKey: .dupSessionType)
        sessionLabel = try container.decode(String.self, forKey: .sessionLabel)
        plannedExercises = try container.decode([PlannedExerciseSet].self, forKey: .plannedExercises)
        estimatedDurationMinutes = try container.decode(Int.self, forKey: .estimatedDurationMinutes)
        templateId = try container.decodeIfPresent(UUID.self, forKey: .templateId)
        completedWorkoutId = try container.decodeIfPresent(UUID.self, forKey: .completedWorkoutId)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        userWorkoutNotes = try container.decodeIfPresent(String.self, forKey: .userWorkoutNotes)
        isDeload = try container.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
        isSkipped = try container.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
        skippedAt = try container.decodeIfPresent(Date.self, forKey: .skippedAt)
        programmingWeekID = try container.decodeIfPresent(UUID.self, forKey: .programmingWeekID)
        programmingWeekNumber = try container.decodeIfPresent(Int.self, forKey: .programmingWeekNumber)
        insertedGroupID = try container.decodeIfPresent(UUID.self, forKey: .insertedGroupID)
        deloadPrescription = try container.decodeIfPresent(PlanDeloadPrescription.self, forKey: .deloadPrescription)
        exerciseSnapshot = try container.decodeIfPresent(WorkoutTemplate.self, forKey: .exerciseSnapshot)
        customLabel = try container.decodeIfPresent(Bool.self, forKey: .customLabel)
    }

    public var isCompleted: Bool { completedWorkoutId != nil }

    /// A session is closed when it no longer expects user action — completed or skipped.
    public var isClosed: Bool { isCompleted || isSkipped || isOmitted }

    /// scheduledDate Precedence Rules
    public var effectiveDate: Date? {
        completedAt ?? scheduledDate
    }

    /// M12: Converts this planned session into a WorkoutTemplate ready for execution.
    /// Each PlannedExerciseSet becomes a TemplateExercise with per-set weight targets.
    public func toWorkoutTemplate(exercises: [Exercise] = []) -> WorkoutTemplate {
        if let snapshot = exerciseSnapshot { return resolvedSnapshot(snapshot) }
        let exerciseLookup = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let templateExercises: [TemplateExercise] = plannedExercises.enumerated().map { index, planned in
            var exercise = exerciseLookup[planned.exerciseId] ?? Exercise(
                id: planned.exerciseId,
                name: planned.exerciseName,
                primaryMuscleGroup: .other,
                secondaryMuscleGroups: [],
                category: .barbell,
                exerciseType: .weightedReps,
                instructions: nil,
                isCustom: false,
                isArchived: false
            )

            exercise.weightRecording = planned.weightRecording
            let setTargets = planned.generateSetTargets()

            return TemplateExercise(
                id: planned.id,
                exercise: exercise,
                order: index,
                supersetGroup: nil,
                notes: planned.notes,
                restTimerSeconds: planned.restSeconds,
                targetSets: planned.sets,
                targetReps: planned.targetReps,
                targetWeight: planned.targetWeight,
                targetDurationSeconds: nil,
                targetDistanceMeters: nil,
                setTargets: setTargets,
                isWarmUp: planned.isWarmup
            )
        }

        return WorkoutTemplate(
            id: templateId ?? UUID(),
            name: sessionLabel,
            notes: notes,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: templateExercises, deloadRestPercentage: deloadPrescription?.restPercentage
        )
    }

    /// Snapshot preserves equipment, per-set targets, timed targets, supersets and
    /// bodyweight conventions. The planned prescription remains the load authority.
    public func resolvedSnapshot(_ snapshot: WorkoutTemplate) -> WorkoutTemplate {
        var result = snapshot
        result.name = displayLabel
        result.notes = notes ?? snapshot.notes
        result.deloadRestPercentage = deloadPrescription?.restPercentage
        result.exercises = snapshot.exercises.sorted { $0.order < $1.order }.map { source in
            var value = source
            if let p = plannedExercises.first(where: { $0.id == source.id }) {
                value.targetSets = p.sets; value.targetReps = p.targetReps > 0 ? p.targetReps : source.targetReps
                value.targetWeight = [.weightedReps, .bodyweightReps, .weightedCardio].contains(source.exercise.exerciseType) ? p.targetWeight : source.targetWeight
                value.restTimerSeconds = p.restSeconds; value.notes = p.notes ?? source.notes
                value.exercise.weightRecording = p.weightRecording
                let normal = deloadPrescription?.normalExercises.first { $0.id == p.id } ?? p
                let changedNormal = normal.sets != source.targetSets || normal.targetReps != (source.targetReps ?? 0) || abs(normal.targetWeight - (source.targetWeight ?? 0)) > 0.00001
                if let rpe = p.targetRPE { value.notes = [value.notes, "Target RPE \(rpe)"].compactMap { $0 }.joined(separator: "\n") }
                if p.isUserOverride == true || source.setTargets.isEmpty || changedNormal {
                    value.setTargets = (0..<p.sets).map { index in
                        TemplateSetTarget(order: index, targetReps: value.targetReps, targetWeight: value.targetWeight,
                            targetDurationSeconds: value.targetDurationSeconds, targetDistanceMeters: value.targetDistanceMeters,
                            setType: p.isWarmup ? .warmup : .normal)
                    }
                } else if let policy = deloadPrescription {
                    value.setTargets = source.setTargets.map { target in
                        var t = target
                        t.targetWeight = t.targetWeight.map { ($0 * Double(policy.weightPercentage)).rounded() / 100 }
                        return t
                    }
                }
            }
            return value
        }
        return result
    }

    /// Dates and deload badges are displayed separately from the workout name.
    public var displayLabel: String {
        var label = sessionLabel
        for prefix in ["Deload · ", "Deload - "] where label.hasPrefix(prefix) { label.removeFirst(prefix.count) }
        return label
    }
}

public extension PlannedSession {
    /// Shared by preview, phone execution and Watch sync.
    func resolvedTemplate(linked template: WorkoutTemplate?, exercises: [Exercise], planExercises: [PlanExercise] = []) -> WorkoutTemplate {
        if let snapshot = exerciseSnapshot { return resolvedSnapshot(snapshot) }
        guard let template else { return toWorkoutTemplate(exercises: exercises) }
        let session = self
        let plannedLookup = Dictionary(
            session.plannedExercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Name fallback only for UNIQUELY named planned exercises — two variants
        // of the same movement (e.g. plate-loaded vs cable machine) share a name
        // but must never cross-apply each other's targets.
        var nameCounts: [String: Int] = [:]
        for planned in session.plannedExercises {
            nameCounts[planned.exerciseName.lowercased(), default: 0] += 1
        }
        let plannedByName = Dictionary(
            uniqueKeysWithValues: session.plannedExercises
                .filter { nameCounts[$0.exerciseName.lowercased()] == 1 }
                .map { ($0.exerciseName.lowercased(), $0) }
        )

        var mergedExercises = template.exercises.map { original -> TemplateExercise in
            var te = original
            te.exercise = te.exercise.resolvingBodyweight(from: exercises)
            let planned = plannedLookup[te.exercise.id]
                ?? plannedByName[te.exercise.name.lowercased()]
            guard let planned else {
                if session.isDeload {
                    if let policy = session.deloadPrescription {
                        var copy = te
                        let factor = Double(policy.weightPercentage) / 100
                        copy.targetWeight = copy.targetWeight.map { ($0 * factor * 100).rounded() / 100 }
                        copy.setTargets = copy.setTargets.map { target in
                            var t = target; t.targetWeight = t.targetWeight.map { ($0 * factor * 100).rounded() / 100 }; return t
                        }
                        return copy
                    }
                    return te.deloaded()
                }
                return te
            }
            te.exercise.weightRecording = planned.weightRecording ?? planExercises.first { $0.exerciseId == planned.exerciseId }?.weightRecording
            return TemplateExercise(
                id: te.id,
                exercise: te.exercise,
                order: te.order,
                supersetGroup: te.supersetGroup,
                notes: planned.notes ?? te.notes,
                restTimerSeconds: planned.restSeconds,
                targetSets: planned.sets,
                targetReps: planned.targetReps,
                targetWeight: planned.targetWeight,
                targetDurationSeconds: te.targetDurationSeconds,
                targetDistanceMeters: te.targetDistanceMeters,
                setTargets: planned.generateSetTargets(),
                isWarmUp: planned.isWarmup
            )
        }

        // Append plan exercises not already covered by the template
        let coveredIds = Set(template.exercises.map { $0.exercise.id })
        let exerciseLookup = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var nextOrder = mergedExercises.count

        for planned in session.plannedExercises where !coveredIds.contains(planned.exerciseId) {
            var exercise = exerciseLookup[planned.exerciseId] ?? Exercise(
                id: planned.exerciseId,
                name: planned.exerciseName,
                primaryMuscleGroup: .other,
                secondaryMuscleGroups: [],
                category: .barbell,
                exerciseType: .weightedReps,
                instructions: nil,
                isCustom: false,
                isArchived: false
            )
            exercise.weightRecording = planned.weightRecording ?? planExercises.first { $0.exerciseId == planned.exerciseId }?.weightRecording
            mergedExercises.append(TemplateExercise(
                id: planned.id,
                exercise: exercise,
                order: nextOrder,
                supersetGroup: nil,
                notes: planned.notes,
                restTimerSeconds: planned.restSeconds,
                targetSets: planned.sets,
                targetReps: planned.targetReps,
                targetWeight: planned.targetWeight,
                targetDurationSeconds: nil,
                targetDistanceMeters: nil,
                setTargets: planned.generateSetTargets(),
                isWarmUp: planned.isWarmup
            ))
            nextOrder += 1
        }

        return WorkoutTemplate(
            id: UUID(),
            name: session.displayLabel,
            notes: session.notes ?? template.notes,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: mergedExercises, deloadRestPercentage: session.deloadPrescription?.restPercentage
        )
    }
}
