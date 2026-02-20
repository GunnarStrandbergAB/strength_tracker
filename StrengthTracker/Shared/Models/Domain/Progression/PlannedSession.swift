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
}
