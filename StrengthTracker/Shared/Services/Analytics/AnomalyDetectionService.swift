import Foundation

/// Detects anomalous workouts that deviate significantly from established patterns.
@MainActor
public final class AnomalyDetectionService: Sendable {

    /// Minimum vector sample to attempt anomaly detection. Below this, the EWMA
    /// centroid is dominated by the last 1-2 sessions and the mean+2σ cutoff is unstable.
    public static let minimumSampleSize = 20

    /// Floor on anomaly score for surfacing. Below this, "anomalies" are effectively
    /// just normal variation — not worth flagging to the user.
    public static let surfaceScoreFloor = 0.5

    /// Per-dimension delta threshold above which a dim contributes to the reasons list.
    /// Below this, the deviation is in the noise floor of L2-normalised vector arithmetic.
    public static let dimensionDeltaThreshold = 0.20

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    /// Detect anomalous workouts. Uses EWMA centroid and flags workouts > mean + 2*stddev.
    /// Returns only anomalies with score ≥ ``surfaceScoreFloor``; results below that floor
    /// are not actionable and would dilute the signal.
    public func detectAnomalies(vectors: [WorkoutVector]) -> [WorkoutAnomaly] {
        guard vectors.count >= Self.minimumSampleSize else { return [] }

        let sorted = vectors.sorted { $0.createdAt < $1.createdAt }

        // Compute EWMA centroid (lambda=0.1)
        let dim = sorted[0].dimensions.count
        var centroid = sorted[0].dimensions
        for i in 1..<sorted.count {
            for d in 0..<dim {
                centroid[d] = 0.1 * sorted[i].dimensions[d] + 0.9 * centroid[d]
            }
        }

        // Re-normalize EWMA centroid to unit length for accurate cosine similarity
        let normalizedCentroid = AnalyticsCalculations.l2Normalize(centroid)

        // Compute anomaly scores (1 - cosine similarity with centroid)
        let scores = sorted.map { 1.0 - searchService.cosineSimilarity($0.dimensions, normalizedCentroid) }

        guard !scores.isEmpty else { return [] }

        let mean = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scores.count)
        let stddev = sqrt(variance)
        let threshold = mean + 2.0 * stddev

        // Flag anomalies
        var anomalies: [WorkoutAnomaly] = []
        for (index, score) in scores.enumerated() {
            guard score > threshold else { continue }
            // Honesty floor: don't surface "anomalies" that aren't actually different.
            guard score >= Self.surfaceScoreFloor else { continue }

            let vector = sorted[index]
            var deviating: [DimensionDrift] = []

            for d in 0..<dim {
                let delta = vector.dimensions[d] - normalizedCentroid[d]
                guard abs(delta) > Self.dimensionDeltaThreshold else { continue }
                let name = d < WorkoutVector.featureNames.count ? WorkoutVector.featureNames[d] : "dim_\(d)"
                // Suppress noise / redundant dims (life-logistics, redundant volume signals,
                // muscle-distribution which encodes workout type rather than anomaly).
                guard WorkoutVector.signalDimensionNames.contains(name) else { continue }
                deviating.append(DimensionDrift(featureName: name, delta: delta))
            }

            // Top 3 deviating dimensions
            deviating.sort { abs($0.delta) > abs($1.delta) }
            let top3 = Array(deviating.prefix(3))

            anomalies.append(WorkoutAnomaly(
                workoutId: vector.workoutId,
                anomalyScore: score,
                deviatingDimensions: top3
            ))
        }

        return anomalies.sorted { $0.anomalyScore > $1.anomalyScore }
    }
}
