import Foundation

/// Compares the current 4-week training block against the previous 4-week block.
@MainActor
public final class BlockComparisonService: Sendable {

    /// Per-dimension delta threshold for "key changes". Block centroids are smoother
    /// than per-workout vectors so this can be slightly lower than anomaly's 0.20.
    public static let dimensionDeltaThreshold = 0.15

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    /// Compare current vs previous 4-week block. Requires 8+ weeks of data.
    public func compareBlocks(vectors: [WorkoutVector]) -> BlockComparison? {
        let now = Date()
        let calendar = Calendar.mondayStart
        let fourWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -4, to: now)!
        let eightWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -8, to: now)!

        let currentBlock = vectors.filter { $0.createdAt >= fourWeeksAgo }
        let previousBlock = vectors.filter { $0.createdAt >= eightWeeksAgo && $0.createdAt < fourWeeksAgo }

        guard currentBlock.count >= 3, previousBlock.count >= 3 else { return nil }

        let currentCentroid = searchService.computeCentroid(vectors: currentBlock)
        let previousCentroid = searchService.computeCentroid(vectors: previousBlock)

        let similarity = searchService.cosineSimilarity(currentCentroid, previousCentroid)

        // Per-dimension deltas. Restrict to the signal allow-list so we don't surface
        // muscle-distribution drift, time-of-day, or the redundant volume-vs-prev pair.
        var deltas: [DimensionDrift] = []
        for i in 0..<min(currentCentroid.count, previousCentroid.count) {
            let delta = currentCentroid[i] - previousCentroid[i]
            guard abs(delta) > Self.dimensionDeltaThreshold else { continue }
            let name = i < WorkoutVector.featureNames.count ? WorkoutVector.featureNames[i] : "dim_\(i)"
            guard WorkoutVector.signalDimensionNames.contains(name) else { continue }
            deltas.append(DimensionDrift(featureName: name, delta: delta))
        }
        deltas.sort { abs($0.delta) > abs($1.delta) }

        let summary = generateSummary(deltas: deltas, similarity: similarity)

        return BlockComparison(
            blockALabel: "Previous 4 weeks",
            blockBLabel: "Current 4 weeks",
            overallSimilarity: similarity,
            dimensionDeltas: deltas,
            summaryText: summary
        )
    }

    // MARK: - Private

    private func generateSummary(deltas: [DimensionDrift], similarity: Double) -> String {
        let simPct = String(format: "%.0f%%", similarity * 100)
        if deltas.isEmpty {
            return "Blocks are \(simPct) similar. Training has been consistent between blocks."
        }

        let changes = deltas.prefix(3).map(\.humanReadableDescription)
        let changeList = changes.joined(separator: ", ")
        return "Blocks are \(simPct) similar. Key changes: \(changeList)."
    }
}
