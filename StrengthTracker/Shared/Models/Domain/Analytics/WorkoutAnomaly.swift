import Foundation

/// A workout that deviates significantly from the user's established patterns.
public struct WorkoutAnomaly: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let workoutId: UUID
    public let anomalyScore: Double  // 0-1
    public let deviatingDimensions: [DimensionDrift]

    public init(
        id: UUID = UUID(),
        workoutId: UUID,
        anomalyScore: Double,
        deviatingDimensions: [DimensionDrift]
    ) {
        self.id = id
        self.workoutId = workoutId
        self.anomalyScore = anomalyScore
        self.deviatingDimensions = deviatingDimensions
    }
}
