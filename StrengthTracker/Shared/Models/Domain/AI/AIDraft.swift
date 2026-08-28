import Foundation

/// A creation proposed by the AI, shown as a Save/Discard card in the chat.
/// Exercise and template drafts carry the fully built domain object; a plan
/// draft carries only the creation parameters — the deterministic program
/// generator builds blocks/weeks/sessions when the user saves.
public enum AIDraft: Codable, Sendable, Equatable {
    case exercise(Exercise)
    case template(WorkoutTemplate)
    case plan(AIPlanParameters)

    public var title: String {
        switch self {
        case .exercise(let exercise): return exercise.name
        case .template(let template): return template.name
        case .plan(let parameters): return parameters.name
        }
    }
}

/// Parameters for an AI-proposed training plan. Mirrors what the structured
/// creation flow collects; program generation happens on Save.
public struct AIPlanParameters: Codable, Sendable, Equatable {
    public struct ExerciseSelection: Codable, Sendable, Equatable {
        public var exerciseID: UUID
        public var exerciseName: String
        public var primaryMuscleGroup: MuscleGroup
        public var category: ExerciseCategory
        /// Estimated 1RM in kg, if known (from PRs or provided by the model).
        public var estimated1RMKg: Double?

        public init(
            exerciseID: UUID,
            exerciseName: String,
            primaryMuscleGroup: MuscleGroup,
            category: ExerciseCategory,
            estimated1RMKg: Double? = nil
        ) {
            self.exerciseID = exerciseID
            self.exerciseName = exerciseName
            self.primaryMuscleGroup = primaryMuscleGroup
            self.category = category
            self.estimated1RMKg = estimated1RMKg
        }
    }

    public var name: String
    public var primaryGoal: TrainingGoal
    public var programType: ProgramType?
    public var weeklyFrequency: Int
    /// Calendar.weekday day numbers (Sun=1 … Sat=7); nil = defaults.
    public var trainingDays: [Int]?
    public var startDate: Date
    public var exercises: [ExerciseSelection]

    public init(
        name: String,
        primaryGoal: TrainingGoal,
        programType: ProgramType? = nil,
        weeklyFrequency: Int,
        trainingDays: [Int]? = nil,
        startDate: Date = Date(),
        exercises: [ExerciseSelection]
    ) {
        self.name = name
        self.primaryGoal = primaryGoal
        self.programType = programType
        self.weeklyFrequency = weeklyFrequency
        self.trainingDays = trainingDays
        self.startDate = startDate
        self.exercises = exercises
    }
}
