import Foundation

/// Data shared between the main app and widgets via App Groups
public struct WidgetData: Codable, Sendable {
    public let lastWorkoutDate: Date?
    public let lastWorkoutName: String?
    public let lastWorkoutExerciseCount: Int
    public let lastWorkoutDuration: TimeInterval?
    public let weeklyWorkoutCount: Int
    public let weeklyGoal: Int
    public let currentStreak: Int
    public let totalWorkoutsAllTime: Int
    public let updatedAt: Date

    public static let empty = WidgetData(
        lastWorkoutDate: nil,
        lastWorkoutName: nil,
        lastWorkoutExerciseCount: 0,
        lastWorkoutDuration: nil,
        weeklyWorkoutCount: 0,
        weeklyGoal: 4,
        currentStreak: 0,
        totalWorkoutsAllTime: 0,
        updatedAt: Date()
    )

    /// Key used for App Group UserDefaults
    public static let userDefaultsKey = "widget_data"

    /// App Group identifier
    public static let appGroupId = "group.com.strengthtracker.shared"

    public init(lastWorkoutDate: Date?, lastWorkoutName: String?, lastWorkoutExerciseCount: Int, lastWorkoutDuration: TimeInterval?, weeklyWorkoutCount: Int, weeklyGoal: Int, currentStreak: Int, totalWorkoutsAllTime: Int, updatedAt: Date) {
        self.lastWorkoutDate = lastWorkoutDate
        self.lastWorkoutName = lastWorkoutName
        self.lastWorkoutExerciseCount = lastWorkoutExerciseCount
        self.lastWorkoutDuration = lastWorkoutDuration
        self.weeklyWorkoutCount = weeklyWorkoutCount
        self.weeklyGoal = weeklyGoal
        self.currentStreak = currentStreak
        self.totalWorkoutsAllTime = totalWorkoutsAllTime
        self.updatedAt = updatedAt
    }
}
