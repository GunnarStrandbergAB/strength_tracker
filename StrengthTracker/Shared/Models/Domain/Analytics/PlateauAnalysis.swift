import Foundation

/// Analysis of progress plateau for an exercise.
/// Recommendation is a computed property derived from the model's own data
/// (DDD: domain model owns its business rules).
public struct PlateauAnalysis: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let exerciseId: UUID
    public let exerciseName: String?
    public let detectedAt: Date
    public let consecutiveWeeksStalled: Int
    public let volumeCoefficient: Double
    public let lastProgressDate: Date?

    /// Business rule: recommendation derived from analysis data.
    /// Computed properties are automatically excluded from Codable synthesis.
    public var recommendation: String {
        guard let name = exerciseName else {
            if consecutiveWeeksStalled >= 4 {
                return "Consider a deload week with reduced volume."
            } else if consecutiveWeeksStalled >= 2 {
                return "Try adjusting volume or technique to break through."
            } else {
                return "Progress is on track."
            }
        }
        if consecutiveWeeksStalled >= 4 {
            return "Consider a deload for \(name) by 10-20% and focus on form."
        } else if consecutiveWeeksStalled >= 2 {
            return "Try increasing volume or adding a technique variation for \(name)."
        } else {
            return "Progress is on track for \(name). Keep pushing!"
        }
    }

    public init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String?,
        detectedAt: Date,
        consecutiveWeeksStalled: Int,
        volumeCoefficient: Double,
        lastProgressDate: Date?
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.detectedAt = detectedAt
        self.consecutiveWeeksStalled = consecutiveWeeksStalled
        self.volumeCoefficient = volumeCoefficient
        self.lastProgressDate = lastProgressDate
    }
}
