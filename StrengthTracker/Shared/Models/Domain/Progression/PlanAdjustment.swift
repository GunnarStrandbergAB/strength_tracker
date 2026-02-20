import Foundation

/// Record of an automatic or manual plan modification
public struct PlanAdjustment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var adjustmentType: AdjustmentType
    public var trigger: AdjustmentTrigger
    public var description: String
    public var affectedExerciseIds: [UUID]
    public var affectedBlockIds: [UUID]
    public var previousValues: [String: String]
    public var newValues: [String: String]
    public var appliedAt: Date
    public var wasAccepted: Bool?
    public var coachingExplanation: String?

    public init(
        id: UUID = UUID(),
        adjustmentType: AdjustmentType,
        trigger: AdjustmentTrigger,
        description: String,
        affectedExerciseIds: [UUID] = [],
        affectedBlockIds: [UUID] = [],
        previousValues: [String: String] = [:],
        newValues: [String: String] = [:],
        appliedAt: Date = Date(),
        wasAccepted: Bool? = nil,
        coachingExplanation: String? = nil
    ) {
        self.id = id
        self.adjustmentType = adjustmentType
        self.trigger = trigger
        self.description = description
        self.affectedExerciseIds = affectedExerciseIds
        self.affectedBlockIds = affectedBlockIds
        self.previousValues = previousValues
        self.newValues = newValues
        self.appliedAt = appliedAt
        self.wasAccepted = wasAccepted
        self.coachingExplanation = coachingExplanation
    }
}
