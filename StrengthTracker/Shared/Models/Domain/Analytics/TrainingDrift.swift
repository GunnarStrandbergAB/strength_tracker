import Foundation

/// Measures how much recent training has diverged from the established baseline.
public struct TrainingDrift: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let overallDriftScore: Double  // 0-1, 0 = identical
    public let driftingDimensions: [DimensionDrift]

    public init(
        id: UUID = UUID(),
        overallDriftScore: Double,
        driftingDimensions: [DimensionDrift]
    ) {
        self.id = id
        self.overallDriftScore = overallDriftScore
        self.driftingDimensions = driftingDimensions
    }
}

/// A single dimension where training has drifted from baseline.
public struct DimensionDrift: Hashable, Sendable, Codable {
    public let featureName: String
    public let delta: Double  // positive = increased, negative = decreased

    public init(featureName: String, delta: Double) {
        self.featureName = featureName
        self.delta = delta
    }
}
