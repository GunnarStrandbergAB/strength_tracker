import Foundation

/// An exercise selected for the progression plan with baseline metrics
public struct PlanExercise: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let exerciseId: UUID                        // References Exercise domain model
    public var exerciseName: String
    public var primaryMuscleGroup: MuscleGroup
    public var category: ExerciseCategory
    public var estimated1RM: Double                    // Always kg (app-wide convention; convert at display boundary)
    public var tested1RM: Double?                      // Actual tested value (if available)
    public var oneRMSource: OneRMSource                // How 1RM was determined
    public var targetPercentageIncrease: Double?       // Goal: e.g., 0.10 = 10% improvement
    public var target1RM: Double?                      // Absolute target
    public var current1RM: Double                      // Updated as plan progresses
    public var personalRecordId: UUID?                 // Link to PR record
    public var isCompound: Bool                        // Compound vs isolation
    public var order: Int                              // Priority ordering
    public var alternatives: [UUID]                    // Swap candidates (exercise IDs)

    public enum OneRMSource: String, Codable, Sendable {
        case tested             // Direct 1RM test
        case estimated          // Calculated from set data
        case userInput          // User entered manually
        case personalRecord     // From PersonalRecord store
        case naturalLanguage    // Parsed from NL plan creation input
    }

    public init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String,
        primaryMuscleGroup: MuscleGroup,
        category: ExerciseCategory,
        estimated1RM: Double,
        tested1RM: Double? = nil,
        oneRMSource: OneRMSource,
        targetPercentageIncrease: Double? = nil,
        target1RM: Double? = nil,
        current1RM: Double,
        personalRecordId: UUID? = nil,
        isCompound: Bool,
        order: Int,
        alternatives: [UUID] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.primaryMuscleGroup = primaryMuscleGroup
        self.category = category
        self.estimated1RM = estimated1RM
        self.tested1RM = tested1RM
        self.oneRMSource = oneRMSource
        self.targetPercentageIncrease = targetPercentageIncrease
        self.target1RM = target1RM
        self.current1RM = current1RM
        self.personalRecordId = personalRecordId
        self.isCompound = isCompound
        self.order = order
        self.alternatives = alternatives
    }

    public func targetWeight(atPercentage pct: Double) -> Double {
        (current1RM * pct).rounded(toNearest: 2.5)
    }
}

extension PlanExercise {
    /// Counts how many of the user's tracked plan exercises appear (by library exercise id)
    /// in the given template. Used by the Link Template picker to surface "N matching plan".
    public static func matchCount(template: WorkoutTemplate, planExercises: [PlanExercise]) -> Int {
        let ids = Set(planExercises.map(\.exerciseId))
        return template.exercises.filter { ids.contains($0.exercise.id) }.count
    }
}
