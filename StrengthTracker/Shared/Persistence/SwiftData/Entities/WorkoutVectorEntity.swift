#if canImport(SwiftData)
import SwiftData
import Foundation

/// SwiftData entity storing the 18-dimensional feature vector for a workout
/// - 72 bytes for vector data (18 * Float32 = 72 bytes)
/// - Optimized for linear scan similarity search (<5ms for 2000 workouts)
@Model
public final class WorkoutVectorEntity {
    @Attribute(.unique) public var id: UUID
    public var workoutId: UUID
    public var createdAt: Date

    // Vector storage: 18 Float32 values stored as Data (72 bytes)
    // Using Float32 instead of Double64 to save 50% space (72 bytes vs 144 bytes)
    public var vectorData: Data

    // L2 magnitude before normalization (nil for legacy vectors)
    public var magnitude: Double?

    // Denormalized fields for faster querying without JOIN
    public var totalVolume: Double
    public var workoutDate: Date
    public var primaryMuscleGroups: [String] // Top 3 muscle groups by volume

    public init(
        id: UUID,
        workoutId: UUID,
        createdAt: Date,
        vectorData: Data,
        magnitude: Double? = nil,
        totalVolume: Double,
        workoutDate: Date,
        primaryMuscleGroups: [String]
    ) {
        self.id = id
        self.workoutId = workoutId
        self.createdAt = createdAt
        self.vectorData = vectorData
        self.magnitude = magnitude
        self.totalVolume = totalVolume
        self.workoutDate = workoutDate
        self.primaryMuscleGroups = primaryMuscleGroups
    }
}
#endif
