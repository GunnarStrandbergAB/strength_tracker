#if canImport(SwiftData)
import Foundation
import SwiftData

/// SwiftData entity for persisting ProgressionPlan domain models.
/// Nested arrays (exercises, blocks, adjustments) are JSON-serialized as Data blobs
/// to avoid deep SwiftData relationship graphs (ADR-004 pattern).
@Model
public final class ProgressionPlanEntity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var status: String              // PlanStatus raw value
    public var trainingStatus: String      // TrainingStatus raw value
    public var programType: String         // ProgramType raw value
    public var primaryGoal: String         // TrainingGoal raw value
    public var secondaryGoal: String?      // TrainingGoal raw value (optional)
    public var weeklyFrequency: Int
    public var startDate: Date
    public var targetEndDate: Date?
    public var actualEndDate: Date?
    public var exercisesJSON: Data         // JSON-encoded [PlanExercise]
    public var blocksJSON: Data            // JSON-encoded [TrainingBlock]
    public var adjustmentsJSON: Data       // JSON-encoded [PlanAdjustment]
    public var createdAt: Date
    public var updatedAt: Date
    public var notes: String?
    public var creationSource: String?     // PlanCreationSource raw value
    public var schemaVersion: Int          // For future migrations

    public init(
        id: UUID,
        name: String,
        status: String,
        trainingStatus: String,
        programType: String,
        primaryGoal: String,
        secondaryGoal: String?,
        weeklyFrequency: Int,
        startDate: Date,
        targetEndDate: Date?,
        actualEndDate: Date?,
        exercisesJSON: Data,
        blocksJSON: Data,
        adjustmentsJSON: Data,
        createdAt: Date,
        updatedAt: Date,
        notes: String?,
        creationSource: String?,
        schemaVersion: Int
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.trainingStatus = trainingStatus
        self.programType = programType
        self.primaryGoal = primaryGoal
        self.secondaryGoal = secondaryGoal
        self.weeklyFrequency = weeklyFrequency
        self.startDate = startDate
        self.targetEndDate = targetEndDate
        self.actualEndDate = actualEndDate
        self.exercisesJSON = exercisesJSON
        self.blocksJSON = blocksJSON
        self.adjustmentsJSON = adjustmentsJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.creationSource = creationSource
        self.schemaVersion = schemaVersion
    }
}
#endif
