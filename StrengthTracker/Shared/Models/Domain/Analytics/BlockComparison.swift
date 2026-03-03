import Foundation

/// Comparison between two training blocks (typically 4-week periods).
public struct BlockComparison: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let blockALabel: String
    public let blockBLabel: String
    public let overallSimilarity: Double
    public let dimensionDeltas: [DimensionDrift]
    public let summaryText: String

    public init(
        id: UUID = UUID(),
        blockALabel: String,
        blockBLabel: String,
        overallSimilarity: Double,
        dimensionDeltas: [DimensionDrift],
        summaryText: String
    ) {
        self.id = id
        self.blockALabel = blockALabel
        self.blockBLabel = blockBLabel
        self.overallSimilarity = overallSimilarity
        self.dimensionDeltas = dimensionDeltas
        self.summaryText = summaryText
    }
}
