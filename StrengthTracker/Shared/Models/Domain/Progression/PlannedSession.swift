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
        userWorkoutNotes: String? = nil
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
    }

    public var isCompleted: Bool { completedWorkoutId != nil }

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
