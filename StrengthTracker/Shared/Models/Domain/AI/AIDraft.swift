import Foundation

/// A creation proposed by the AI, shown as a Save/Discard card in the chat.
/// Exercise and template drafts carry the fully built domain object; a plan
/// draft carries only the creation parameters — the deterministic program
/// generator builds blocks/weeks/sessions when the user saves.
public enum AIDraft: Codable, Sendable, Equatable {
    case exercise(Exercise)
    case template(WorkoutTemplate)
    case plan(AIPlanParameters)
    /// A destructive action awaiting the user's Confirm (never a creation).
    case action(AIPendingAction)

    public var title: String {
        switch self {
        case .exercise(let exercise): return exercise.name
        case .template(let template): return template.name
        case .plan(let parameters): return parameters.name
        case .action(let action): return action.title
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
        /// True when the 1RM came from the user's personal records (provenance).
        public var weightRecording: WeightRecording?
        public var oneRMFromPersonalRecord: Bool?
        /// How the exercise progresses; nil follows the percentage wave.
        public var progression: ProgressionRule?
        /// On the percentage wave: the sets and reps asked for every session; nil leaves that number to the wave.
        public var waveSets: Int?
        public var waveReps: Int?

        public init(
            exerciseID: UUID,
            exerciseName: String,
            primaryMuscleGroup: MuscleGroup,
            category: ExerciseCategory,
            estimated1RMKg: Double? = nil,
            oneRMFromPersonalRecord: Bool? = nil,
            weightRecording: WeightRecording? = nil
        ) {
            self.exerciseID = exerciseID
            self.exerciseName = exerciseName
            self.primaryMuscleGroup = primaryMuscleGroup
            self.category = category
            self.estimated1RMKg = estimated1RMKg
            self.oneRMFromPersonalRecord = oneRMFromPersonalRecord
            self.weightRecording = weightRecording
        }
    }

    /// Which exercises/template train on which day — maps onto DayScheduleEntry.
    public struct DaySplit: Codable, Sendable, Equatable {
        /// Calendar.weekday day number (Sun=1 … Sat=7).
        public var dayOfWeek: Int
        /// May be empty when a template carries the whole day.
        public var exerciseIDs: [UUID]
        /// Kept alongside the ids for card display.
        public var exerciseNames: [String]
        /// The user template the day's workout is copied from; the plan's exercises
        /// in it get progression targets. The plan does not follow the template afterwards.
        public var templateID: UUID?
        public var templateName: String?
        /// Exercises the day also trains at fixed targets, without progression.
        public var otherExercises: [FixedExercise]?

        public init(
            dayOfWeek: Int,
            exerciseIDs: [UUID],
            exerciseNames: [String],
            templateID: UUID? = nil,
            templateName: String? = nil
        ) {
            self.dayOfWeek = dayOfWeek
            self.exerciseIDs = exerciseIDs
            self.exerciseNames = exerciseNames
            self.templateID = templateID
            self.templateName = templateName
        }
    }

    /// An exercise a day trains at fixed targets: the plan does not progress it.
    public struct FixedExercise: Codable, Sendable, Equatable {
        public var exerciseID: UUID
        public var exerciseName: String
        public var sets: Int
        public var reps: Int?
        public var weightKg: Double?
        public var durationSeconds: Int?
        public var distanceMeters: Double?

        public init(exerciseID: UUID, exerciseName: String, sets: Int, reps: Int? = nil, weightKg: Double? = nil,
                    durationSeconds: Int? = nil, distanceMeters: Double? = nil) {
            self.exerciseID = exerciseID; self.exerciseName = exerciseName; self.sets = sets; self.reps = reps
            self.weightKg = weightKg; self.durationSeconds = durationSeconds; self.distanceMeters = distanceMeters
        }
    }

    /// One session of a deload week that has its own schedule: any weekday, training a
    /// template or the workout of one of the plan's training days.
    public struct DeloadSplit: Codable, Sendable, Equatable {
        public var dayOfWeek: Int
        public var templateID: UUID?
        public var templateName: String?
        public var sameAsDay: Int?

        public init(dayOfWeek: Int, templateID: UUID? = nil, templateName: String? = nil, sameAsDay: Int? = nil) {
            self.dayOfWeek = dayOfWeek; self.templateID = templateID; self.templateName = templateName; self.sameAsDay = sameAsDay
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
    /// Per-day exercise assignment; nil = every exercise on every training day.
    public var daySplits: [DaySplit]?
    /// Weekdays deload weeks train on; nil = same as training days.
    public var deloadDays: [Int]?
    /// User-stated training level override; nil = auto-detect at save time.
    public var durationWeeks: Int?
    public var trainingStatus: TrainingStatus?
    /// The pace the exercises' rules were preset from, when rules are used.
    public var pace: PlanPace?
    /// A deload every Nth week; 0 schedules none; nil keeps the level-based default.
    public var deloadEveryWeeks: Int?
    /// A deload week's own schedule; nil repeats the normal week on `deloadDays`.
    public var deloadSplits: [DeloadSplit]?

    public init(
        name: String,
        primaryGoal: TrainingGoal,
        programType: ProgramType? = nil,
        weeklyFrequency: Int,
        trainingDays: [Int]? = nil,
        startDate: Date = Date(),
        exercises: [ExerciseSelection],
        daySplits: [DaySplit]? = nil,
        deloadDays: [Int]? = nil,
        trainingStatus: TrainingStatus? = nil, durationWeeks: Int? = nil
    ) {
        self.durationWeeks = durationWeeks
        self.name = name
        self.primaryGoal = primaryGoal
        self.programType = programType
        self.weeklyFrequency = weeklyFrequency
        self.trainingDays = trainingDays
        self.startDate = startDate
        self.exercises = exercises
        self.daySplits = daySplits
        self.deloadDays = deloadDays
        self.trainingStatus = trainingStatus
    }
}
