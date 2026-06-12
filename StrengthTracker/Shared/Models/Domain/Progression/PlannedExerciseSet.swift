import Foundation

/// Target prescription for an exercise within a session
public struct PlannedExerciseSet: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var planExerciseId: UUID
    public var exerciseId: UUID
    public var exerciseName: String
    public var sets: Int
    public var targetReps: Int
    public var targetWeight: Double
    public var percentageOf1RM: Double
    public var targetRPE: Double?
    public var restSeconds: Int
    public var isWarmup: Bool
    public var notes: String?

    public init(
        id: UUID = UUID(),
        planExerciseId: UUID,
        exerciseId: UUID,
        exerciseName: String,
        sets: Int,
        targetReps: Int,
        targetWeight: Double,
        percentageOf1RM: Double,
        targetRPE: Double? = nil,
        restSeconds: Int = 120,
        isWarmup: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.planExerciseId = planExerciseId
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.sets = sets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.percentageOf1RM = percentageOf1RM
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.notes = notes
    }

    /// APRE adjustment: recalculate weight based on actual reps achieved.
    /// Percentage-based, computed from ACTUAL workingWeight.
    public func apreAdjustedWeight(
        actualReps: Int,
        workingWeight: Double,
        isCompound: Bool,
        isLowerBody: Bool
    ) -> Double {
        let adjustmentPct: Double
        switch (targetReps, actualReps) {
        // 3RM Protocol (strength focus)
        case (3, let actual) where actual <= 1:
            adjustmentPct = -0.05
        case (3, 2...3):
            adjustmentPct = 0
        case (3, 4...5):
            adjustmentPct = 0.025
        case (3, let actual) where actual >= 6:
            adjustmentPct = 0.05

        // 6RM Protocol (hypertrophy focus)
        case (6, let actual) where actual <= 3:
            adjustmentPct = -0.05
        case (6, 4...5):
            adjustmentPct = -0.025
        case (6, 6...7):
            adjustmentPct = 0
        case (6, 8...9):
            adjustmentPct = 0.025
        case (6, let actual) where actual >= 10:
            adjustmentPct = 0.05

        // 10RM Protocol (endurance focus)
        case (10, let actual) where actual <= 6:
            adjustmentPct = -0.05
        case (10, 7...8):
            adjustmentPct = -0.025
        case (10, 9...11):
            adjustmentPct = 0
        case (10, 12...14):
            adjustmentPct = 0.025
        case (10, let actual) where actual >= 15:
            adjustmentPct = 0.05

        default:
            let deviation = Double(actualReps - targetReps) / Double(max(1, targetReps))
            adjustmentPct = min(max(deviation, -0.10), 0.10)
        }

        // Computed as w + w*pct rather than w * (1+pct) to avoid floating-point
        // drift at rounding midpoints (e.g. 100 * 1.025 == 102.4999... would
        // incorrectly round down to 100 instead of up to 105).
        let rawAdjusted = workingWeight + workingWeight * adjustmentPct

        // m6: Lower-body compounds use 5kg rounding for plate-friendly jumps
        let increment: Double
        if rawAdjusted < 40.0 || !isCompound {
            increment = 1.0
        } else if isLowerBody {
            increment = 5.0
        } else {
            increment = 2.5
        }

        return max(0, rawAdjusted.rounded(toNearest: increment))
    }

    /// M12: Generates TemplateSetTarget array for workout template creation.
    public func generateSetTargets() -> [TemplateSetTarget] {
        (0..<sets).map { setIndex in
            TemplateSetTarget(
                order: setIndex,
                targetReps: targetReps,
                targetWeight: targetWeight,
                setType: isWarmup ? .warmup : .normal
            )
        }
    }
}
