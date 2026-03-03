import Foundation

/// Detects anomalous workouts that deviate significantly from established patterns.
@MainActor
public final class AnomalyDetectionService: Sendable {

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    /// Detect anomalous workouts. Uses EWMA centroid and flags workouts > mean + 2*stddev.
    public func detectAnomalies(vectors: [WorkoutVector]) -> [WorkoutAnomaly] {
        guard vectors.count >= 5 else { return [] }

        let sorted = vectors.sorted { $0.createdAt < $1.createdAt }

        // Compute EWMA centroid (lambda=0.1)
        let dim = sorted[0].dimensions.count
        var centroid = sorted[0].dimensions
        for i in 1..<sorted.count {
            for d in 0..<dim {
                centroid[d] = 0.1 * sorted[i].dimensions[d] + 0.9 * centroid[d]
            }
        }

        // Compute anomaly scores (1 - cosine similarity with centroid)
        let scores = sorted.map { 1.0 - searchService.cosineSimilarity($0.dimensions, centroid) }

        guard !scores.isEmpty else { return [] }

        let mean = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scores.count)
        let stddev = sqrt(variance)
        let threshold = mean + 2.0 * stddev

        // Flag anomalies
        var anomalies: [WorkoutAnomaly] = []
        for (index, score) in scores.enumerated() {
            guard score > threshold else { continue }

            let vector = sorted[index]
            var deviating: [DimensionDrift] = []

            for d in 0..<dim {
                let delta = vector.dimensions[d] - centroid[d]
                if abs(delta) > 0.10 {
                    let name = d < WorkoutVector.featureNames.count ? WorkoutVector.featureNames[d] : "dim_\(d)"
                    deviating.append(DimensionDrift(featureName: name, delta: delta))
                }
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
