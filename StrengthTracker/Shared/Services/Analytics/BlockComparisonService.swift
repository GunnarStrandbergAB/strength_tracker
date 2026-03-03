import Foundation

/// Compares the current 4-week training block against the previous 4-week block.
@MainActor
public final class BlockComparisonService: Sendable {

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    /// Compare current vs previous 4-week block. Requires 8+ weeks of data.
    public func compareBlocks(vectors: [WorkoutVector]) -> BlockComparison? {
        let now = Date()
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: now)!
        let eightWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: now)!

        let currentBlock = vectors.filter { $0.createdAt >= fourWeeksAgo }
        let previousBlock = vectors.filter { $0.createdAt >= eightWeeksAgo && $0.createdAt < fourWeeksAgo }

        guard currentBlock.count >= 3, previousBlock.count >= 3 else { return nil }

        let currentCentroid = computeCentroid(vectors: currentBlock)
        let previousCentroid = computeCentroid(vectors: previousBlock)

        let similarity = searchService.cosineSimilarity(currentCentroid, previousCentroid)

        // Per-dimension deltas > 10%
        var deltas: [DimensionDrift] = []
        for i in 0..<min(currentCentroid.count, previousCentroid.count) {
            let delta = currentCentroid[i] - previousCentroid[i]
            if abs(delta) > 0.10 {
                let name = i < WorkoutVector.featureNames.count ? WorkoutVector.featureNames[i] : "dim_\(i)"
                deltas.append(DimensionDrift(featureName: name, delta: delta))
            }
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

    private func generateSummary(deltas: [DimensionDrift], similarity: Double) -> String {
        if deltas.isEmpty {
            return "Training has been consistent between blocks."
        }

        let changes = deltas.prefix(3).map { drift in
            let direction = drift.delta > 0 ? "increased" : "decreased"
            let name = drift.featureName.replacingOccurrences(of: "_", with: " ")
            return "\(name) \(direction)"
        }

        let changeList = changes.joined(separator: ", ")
        let simPct = String(format: "%.0f%%", similarity * 100)
        return "Blocks are \(simPct) similar. Key changes: \(changeList)."
    }
}
