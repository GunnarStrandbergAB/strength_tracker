import Foundation

/// A reference to a similar workout with its similarity score.
/// References the workout by ID only (DDD: cross-aggregate references by identity).
/// Denormalized fields allow display without fetching the full Workout aggregate.
public struct SimilarWorkout: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let workoutId: UUID
    public let workoutName: String
    public let workoutDate: Date
    public let totalVolume: Double
    public let similarityScore: Double
    public let matchedFeatures: [String]

    public init(
        id: UUID = UUID(),
        workoutId: UUID,
        workoutName: String,
        workoutDate: Date,
        totalVolume: Double,
        similarityScore: Double,
        matchedFeatures: [String]
    ) {
        self.id = id
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.workoutDate = workoutDate
        self.totalVolume = totalVolume
        self.similarityScore = similarityScore
        self.matchedFeatures = matchedFeatures
    }
}
