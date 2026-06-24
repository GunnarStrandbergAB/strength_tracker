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
        skippedAt: Date? = nil
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
    }

    // Custom decoding for backward compatibility — existing JSON without
    // isDeload/isSkipped decodes as false (skippedAt as nil)
    private enum CodingKeys: String, CodingKey {
        case id, dayOfWeek, scheduledDate, dupSessionType, sessionLabel
        case plannedExercises, estimatedDurationMinutes, templateId
        case completedWorkoutId, completedAt, notes, userWorkoutNotes, isDeload
        case isSkipped, skippedAt
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
    }

    public var isCompleted: Bool { completedWorkoutId != nil }

    /// A session is closed when it no longer expects user action — completed or skipped.
    public var isClosed: Bool { isCompleted || isSkipped }

    /// scheduledDate Precedence Rules
    public var effectiveDate: Date? {
        completedAt ?? scheduledDate
    }

    /// M12: Converts this planned session into a WorkoutTemplate ready for execution.
    /// Each PlannedExerciseSet becomes a TemplateExercise with per-set weight targets.
    public func toWorkoutTemplate(exercises: [Exercise] = []) -> WorkoutTemplate {
        let exerciseLookup = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let templateExercises: [TemplateExercise] = plannedExercises.enumerated().map { index, planned in
            let exercise = exerciseLookup[planned.exerciseId] ?? Exercise(
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
            exercises: templateExercises
        )
    }
}
