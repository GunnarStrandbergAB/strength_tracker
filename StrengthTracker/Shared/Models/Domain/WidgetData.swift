import Foundation

// MARK: - Widget Support Types

public struct WidgetHighlight: Codable, Sendable, Identifiable {
    public let id: UUID
    public let icon: String        // SF Symbol name
    public let title: String
    public let detail: String
    public let color: String       // "yellow", "orange", "green", "red", "blue"

    public init(id: UUID = UUID(), icon: String, title: String, detail: String, color: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.detail = detail
        self.color = color
    }
}

public struct WidgetActiveWorkout: Codable, Sendable {
    public let workoutName: String
    public let currentExerciseName: String
    public let currentExerciseId: String  // UUID string for AppIntent
    public let completedSets: Int
    public let totalPlannedSets: Int
    public let startedAt: Date
    public let isResting: Bool
    public let restEndDate: Date?     // for Text(timerInterval:)
    public let nextSetWeight: Double?
    public let nextSetReps: Int?
    public let nextExerciseName: String?

    public init(
        workoutName: String, currentExerciseName: String, currentExerciseId: String,
        completedSets: Int, totalPlannedSets: Int, startedAt: Date,
        isResting: Bool, restEndDate: Date?,
        nextSetWeight: Double?, nextSetReps: Int?, nextExerciseName: String?
    ) {
        self.workoutName = workoutName
        self.currentExerciseName = currentExerciseName
        self.currentExerciseId = currentExerciseId
        self.completedSets = completedSets
        self.totalPlannedSets = totalPlannedSets
        self.startedAt = startedAt
        self.isResting = isResting
        self.restEndDate = restEndDate
        self.nextSetWeight = nextSetWeight
        self.nextSetReps = nextSetReps
        self.nextExerciseName = nextExerciseName
    }
}

public struct WidgetPlannedSession: Codable, Sendable {
    public let sessionName: String
    public let exerciseNames: [String]  // first 4 exercise names
    public let planName: String

    public init(sessionName: String, exerciseNames: [String], planName: String) {
        self.sessionName = sessionName
        self.exerciseNames = exerciseNames
        self.planName = planName
    }
}

// MARK: - WidgetData

/// Data shared between the main app and widgets via App Groups
public struct WidgetData: Codable, Sendable {
    // Existing fields
    public let lastWorkoutDate: Date?
    public let lastWorkoutName: String?
    public let lastWorkoutExerciseCount: Int
    public let lastWorkoutDuration: TimeInterval?
    public let weeklyWorkoutCount: Int
    public let weeklyGoal: Int
    public let currentStreak: Int
    public let totalWorkoutsAllTime: Int
    public let updatedAt: Date

    // Analytics highlights (top 3, pre-computed by the app)
    public let highlights: [WidgetHighlight]

    // 7-day training calendar [Mon..Sun]
    public let weekDaysTrained: [Bool]

    // Active workout state (nil = no workout active)
    public let activeWorkout: WidgetActiveWorkout?

    // Next planned session (from progression plan)
    public let nextPlannedSession: WidgetPlannedSession?

    // Volume trend
    public let weeklyVolume: Double?
    public let previousWeekVolume: Double?

    public static let empty = WidgetData(
        lastWorkoutDate: nil,
        lastWorkoutName: nil,
        lastWorkoutExerciseCount: 0,
        lastWorkoutDuration: nil,
        weeklyWorkoutCount: 0,
        weeklyGoal: 0,
        currentStreak: 0,
        totalWorkoutsAllTime: 0,
        updatedAt: Date(),
        highlights: [],
        weekDaysTrained: Array(repeating: false, count: 7),
        activeWorkout: nil,
        nextPlannedSession: nil,
        weeklyVolume: nil,
        previousWeekVolume: nil
    )

    /// Key used for App Group UserDefaults
    public static let userDefaultsKey = "widget_data"

    /// App Group identifier
    public static let appGroupId = "group.se.gunnarstrandberg.hellbent.shared"

    /// Key for pending set completions from widget intents
    public static let pendingCompletionsKey = "widget_pending_completions"

    public init(
        lastWorkoutDate: Date?, lastWorkoutName: String?, lastWorkoutExerciseCount: Int,
        lastWorkoutDuration: TimeInterval?, weeklyWorkoutCount: Int, weeklyGoal: Int,
        currentStreak: Int, totalWorkoutsAllTime: Int, updatedAt: Date,
        highlights: [WidgetHighlight] = [],
        weekDaysTrained: [Bool] = Array(repeating: false, count: 7),
        activeWorkout: WidgetActiveWorkout? = nil,
        nextPlannedSession: WidgetPlannedSession? = nil,
        weeklyVolume: Double? = nil,
        previousWeekVolume: Double? = nil
    ) {
        self.lastWorkoutDate = lastWorkoutDate
        self.lastWorkoutName = lastWorkoutName
        self.lastWorkoutExerciseCount = lastWorkoutExerciseCount
        self.lastWorkoutDuration = lastWorkoutDuration
        self.weeklyWorkoutCount = weeklyWorkoutCount
        self.weeklyGoal = weeklyGoal
        self.currentStreak = currentStreak
        self.totalWorkoutsAllTime = totalWorkoutsAllTime
        self.updatedAt = updatedAt
        self.highlights = highlights
        self.weekDaysTrained = weekDaysTrained
        self.activeWorkout = activeWorkout
        self.nextPlannedSession = nextPlannedSession
        self.weeklyVolume = weeklyVolume
        self.previousWeekVolume = previousWeekVolume
    }

    // Backward-compatible decoding for old data without new fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastWorkoutDate = try container.decodeIfPresent(Date.self, forKey: .lastWorkoutDate)
        lastWorkoutName = try container.decodeIfPresent(String.self, forKey: .lastWorkoutName)
        lastWorkoutExerciseCount = try container.decode(Int.self, forKey: .lastWorkoutExerciseCount)
        lastWorkoutDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .lastWorkoutDuration)
        weeklyWorkoutCount = try container.decode(Int.self, forKey: .weeklyWorkoutCount)
        weeklyGoal = try container.decode(Int.self, forKey: .weeklyGoal)
        currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        totalWorkoutsAllTime = try container.decode(Int.self, forKey: .totalWorkoutsAllTime)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        highlights = (try? container.decode([WidgetHighlight].self, forKey: .highlights)) ?? []
        weekDaysTrained = (try? container.decode([Bool].self, forKey: .weekDaysTrained)) ?? Array(repeating: false, count: 7)
        activeWorkout = try? container.decodeIfPresent(WidgetActiveWorkout.self, forKey: .activeWorkout)
        nextPlannedSession = try? container.decodeIfPresent(WidgetPlannedSession.self, forKey: .nextPlannedSession)
        weeklyVolume = try? container.decodeIfPresent(Double.self, forKey: .weeklyVolume)
        previousWeekVolume = try? container.decodeIfPresent(Double.self, forKey: .previousWeekVolume)
    }
}
