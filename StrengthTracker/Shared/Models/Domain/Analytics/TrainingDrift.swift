import Foundation

/// Measures how much recent training has diverged from the established baseline.
public struct TrainingDrift: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let overallDriftScore: Double  // 0-1, 0 = identical
    public let driftingDimensions: [DimensionDrift]

    public init(
        id: UUID = UUID(),
        overallDriftScore: Double,
        driftingDimensions: [DimensionDrift]
    ) {
        self.id = id
        self.overallDriftScore = overallDriftScore
        self.driftingDimensions = driftingDimensions
    }
}

/// A single dimension where training has drifted from baseline.
public struct DimensionDrift: Hashable, Sendable, Codable {
    public let featureName: String
    public let delta: Double  // positive = increased, negative = decreased

    public init(featureName: String, delta: Double) {
        self.featureName = featureName
        self.delta = delta
    }

    /// User-facing description of this drift. Maps raw feature names to plain English
    /// so service summaries and view code share the same vocabulary.
    public var humanReadableDescription: String {
        let direction = delta > 0 ? "Higher" : "Lower"
        switch featureName {
        case "volume_vs_prev_7d":    return "\(direction) volume than last week"
        case "volume_vs_prev_30d":   return "\(direction) volume than your monthly avg"
        case "total_volume_norm":    return "\(direction) total volume"
        case "avg_weight_norm":      return "\(direction) average weight"
        case "avg_reps_norm":        return "\(direction) reps per set"
        case "set_count_norm":       return "\(direction) number of sets"
        case "exercise_diversity":   return delta > 0 ? "More exercise variety" : "Less exercise variety"
        case "duration_norm":        return delta > 0 ? "Longer session" : "Shorter session"
        case "compound_ratio":       return delta > 0 ? "More compound lifts" : "Fewer compound lifts"
        case "avg_rpe":              return delta > 0 ? "Higher effort (RPE)" : "Lower effort (RPE)"
        case "pr_count_norm":        return delta > 0 ? "More PRs than usual" : "Fewer PRs than usual"
        default:
            let name = featureName.replacingOccurrences(of: "_", with: " ")
            return "\(direction) \(name)"
        }
    }
}
