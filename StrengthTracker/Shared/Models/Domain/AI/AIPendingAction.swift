import Foundation

/// A destructive action the AI wants to take. Rendered as a Confirm/Cancel card;
/// nothing is written until the user confirms, and the confirm path executes it
/// through the same coordinator/editor code the tools use.
public struct AIPendingAction: Codable, Sendable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        /// Start a new workout, discarding the active one (`replacingWorkoutID`).
        case startWorkout(
            name: String,
            templateID: UUID?,
            plannedSessionID: UUID?,
            plannedPlanID: UUID?,
            isDeload: Bool,
            replacingWorkoutID: UUID
        )
        case cancelWorkout(workoutID: UUID)
        case removeExercise(workoutID: UUID, exerciseID: UUID)
        case removeSet(workoutID: UUID, exerciseID: UUID, setID: UUID)
    }

    public var kind: Kind
    /// e.g. "Cancel current workout?"
    public var title: String
    /// e.g. ["Push Day, started 18:02", "5 completed sets will be discarded"]
    public var summaryLines: [String]
    /// Button label, e.g. "Cancel Workout", "Replace & Start", "Remove".
    public var confirmLabel: String

    public init(kind: Kind, title: String, summaryLines: [String], confirmLabel: String) {
        self.kind = kind
        self.title = title
        self.summaryLines = summaryLines
        self.confirmLabel = confirmLabel
    }
}
