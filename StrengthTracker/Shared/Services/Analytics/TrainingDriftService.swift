import Foundation

/// Detects training drift by comparing recent workout vectors against a baseline.
@MainActor
public final class TrainingDriftService: Sendable {

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    /// Compute training drift between recent (last 14 days) and baseline (15-45 days).
    /// Returns nil if insufficient data in either window.
    public func computeDrift(vectors: [WorkoutVector]) -> TrainingDrift? {
        let now = Date()
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let fortyFiveDaysAgo = Calendar.current.date(byAdding: .day, value: -45, to: now)!

        let recent = vectors.filter { $0.createdAt >= fourteenDaysAgo }
        let baseline = vectors.filter { $0.createdAt >= fortyFiveDaysAgo && $0.createdAt < fourteenDaysAgo }

        guard recent.count >= 2, baseline.count >= 3 else { return nil }

        let recentCentroid = computeCentroid(vectors: recent)
        let baselineCentroid = computeCentroid(vectors: baseline)

        let similarity = searchService.cosineSimilarity(recentCentroid, baselineCentroid)
        let overallDrift = 1.0 - similarity

        // Per-dimension drift
        var driftingDimensions: [DimensionDrift] = []
        for i in 0..<min(recentCentroid.count, baselineCentroid.count) {
            let delta = recentCentroid[i] - baselineCentroid[i]
            if abs(delta) > 0.10 {
                let name = i < WorkoutVector.featureNames.count ? WorkoutVector.featureNames[i] : "dim_\(i)"
                driftingDimensions.append(DimensionDrift(featureName: name, delta: delta))
            }
        }

        // Sort by absolute delta descending
        driftingDimensions.sort { abs($0.delta) > abs($1.delta) }

        return TrainingDrift(
            overallDriftScore: overallDrift,
            driftingDimensions: driftingDimensions
        )
    }

    // MARK: - Private

    private func computeCentroid(vectors: [WorkoutVector]) -> [Double] {
        guard let first = vectors.first else { return [] }
        let dim = first.dimensions.count
        var sum = [Double](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<dim {
                sum[i] += v.dimensions[i]
            }
        }
        let n = Double(vectors.count)
        return sum.map { $0 / n }
    }
}
