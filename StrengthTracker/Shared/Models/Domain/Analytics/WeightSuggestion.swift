import Foundation

/// A suggested weight for an upcoming set based on recent performance and recovery.
public struct WeightSuggestion: Sendable {
    public let weight: Double         // entered-weight convention, stored in kg
    public let targetReps: Int
    public let explanation: String
    public let modifiers: [String]    // e.g. ["Recovery: -5%", "Trend: +1.2 kg/wk"]
    public let exercise: Exercise?
    public let evidence: [Evidence]

    public struct Evidence: Sendable, Identifiable {
        public var id: UUID { workoutId }
        public let workoutId: UUID
        public let date: Date
        public let originalExercise: Exercise
        public let originalWeight: Double
        public let reps: Int
        public let convertedWeight: Double
        public let estimatedStrength: Double

        public func description(unit: WeightUnit, reference: Exercise?) -> String {
            let original = originalExercise.recordedPerformance(weight: originalWeight, reps: reps, unit: unit)
            guard let reference, reference.performanceConvention != originalExercise.performanceConvention else { return original }
            return "\(original) → \(reference.recordedPerformance(weight: convertedWeight, reps: reps, unit: unit))"
        }
    }

    public func displayText(unit: WeightUnit) -> String {
        guard let exercise else { return "Suggested: ≈\(unit.format(weight)) for \(targetReps) reps" }
        return "Suggested: ≈\(exercise.recordedPerformance(weight: weight, reps: targetReps, unit: unit))"
    }

    public init(weight: Double, targetReps: Int, explanation: String, modifiers: [String] = [], exercise: Exercise? = nil, evidence: [Evidence] = []) {
        self.weight = weight
        self.targetReps = targetReps
        self.explanation = explanation
        self.modifiers = modifiers
        self.exercise = exercise
        self.evidence = evidence
    }
}
