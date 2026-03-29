import Foundation

/// A suggested weight for an upcoming set based on recent performance and recovery.
public struct WeightSuggestion: Sendable {
    public let weight: Double         // rounded to nearest 2.5 kg
    public let targetReps: Int
    public let explanation: String
    public let modifiers: [String]    // e.g. ["Recovery: -5%", "Trend: +1.2 kg/wk"]

    public init(weight: Double, targetReps: Int, explanation: String, modifiers: [String] = []) {
        self.weight = weight
        self.targetReps = targetReps
        self.explanation = explanation
        self.modifiers = modifiers
    }
}
