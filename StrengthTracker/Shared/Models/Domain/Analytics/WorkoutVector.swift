import Foundation

/// A feature vector representing a workout's characteristics.
/// 18 dimensions capturing volume, intensity, muscle distribution, and progression.
/// L2 normalized for cosine similarity computation.
public struct WorkoutVector: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let workoutId: UUID
    public let dimensions: [Double]
    public let magnitude: Double?     // L2 magnitude before normalization
    public let createdAt: Date

    /// Human-readable feature names for debugging and display
    public static let featureNames: [String] = [
        "total_volume_norm",
        "avg_weight_norm",
        "avg_reps_norm",
        "set_count_norm",
        "exercise_diversity",
        "duration_norm",
        "chest_ratio",
        "back_ratio",
        "legs_ratio",
        "shoulders_ratio",
        "arms_ratio",
        "core_ratio",
        "compound_ratio",
        "avg_rpe",
        "volume_vs_prev_7d",
        "volume_vs_prev_30d",
        "pr_count_norm",
        "time_of_day_sin",
    ]

    public init(
        id: UUID = UUID(),
        workoutId: UUID,
        dimensions: [Double],
        magnitude: Double? = nil,
        createdAt: Date = Date()
    ) {
        precondition(dimensions.count == 18, "WorkoutVector must have exactly 18 dimensions")
        self.id = id
        self.workoutId = workoutId
        self.dimensions = dimensions
        self.magnitude = magnitude
        self.createdAt = createdAt
    }
}
