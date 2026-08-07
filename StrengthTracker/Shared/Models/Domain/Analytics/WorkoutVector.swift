import Foundation

/// A feature vector representing a workout's characteristics.
/// 18 dimensions capturing volume, intensity, muscle distribution, and progression.
/// L2 normalized for cosine similarity computation.
public struct WorkoutVector: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let workoutId: UUID
    public let dimensions: [Double]
    public let magnitude: Double?     // L2 magnitude before normalization
    /// The workout's training date (== workout.startedAt), NOT the wall-clock time of
    /// vectorization — recency-windowed analytics sort and filter on this.
    public let createdAt: Date

    /// Human-readable feature names for debugging and display.
    /// NOTE: dim 17 is a linear minute-of-day mapping (see WorkoutVectorizer); the legacy
    /// `_sin` suffix was misleading and has been corrected to `time_of_day`.
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
        "time_of_day",
    ]

    /// Dim names that carry programmatic-shift signal worth surfacing to the user.
    /// Excluded by design:
    ///   - `time_of_day`: life logistics, not training
    ///   - `volume_vs_prev_7d` / `volume_vs_prev_30d`: redundant with `total_volume_norm`,
    ///     stack as duplicate "reasons" when a session is just slightly off baseline
    ///   - the six muscle ratios: encode workout type (push/pull/legs), not anomaly/drift
    public static let signalDimensionNames: Set<String> = [
        "total_volume_norm",
        "avg_weight_norm",
        "avg_reps_norm",
        "set_count_norm",
        "exercise_diversity",
        "duration_norm",
        "compound_ratio",
        "avg_rpe",
        "pr_count_norm",
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
