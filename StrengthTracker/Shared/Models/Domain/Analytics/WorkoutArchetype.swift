import Foundation

public struct WorkoutArchetype: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let centroid: [Double]
    public let memberWorkoutIds: [UUID]
    public let dominantFeatures: [String]
    public let avgVolume: Double
    public let avgDuration: TimeInterval
    public let frequency: Double
    public let lastPerformed: Date?
    public let daysSinceLastPerformed: Int?

    public init(
        id: UUID = UUID(),
        label: String,
        centroid: [Double],
        memberWorkoutIds: [UUID],
        dominantFeatures: [String],
        avgVolume: Double,
        avgDuration: TimeInterval,
        frequency: Double,
        lastPerformed: Date?,
        daysSinceLastPerformed: Int?
    ) {
        self.id = id
        self.label = label
        self.centroid = centroid
        self.memberWorkoutIds = memberWorkoutIds
        self.dominantFeatures = dominantFeatures
        self.avgVolume = avgVolume
        self.avgDuration = avgDuration
        self.frequency = frequency
        self.lastPerformed = lastPerformed
        self.daysSinceLastPerformed = daysSinceLastPerformed
    }
}
