import Foundation

/// Data shared between the main app and widgets via App Groups
struct WidgetData: Codable, Sendable {
    let lastWorkoutDate: Date?
    let lastWorkoutName: String?
    let lastWorkoutExerciseCount: Int
    let lastWorkoutDuration: TimeInterval?
    let weeklyWorkoutCount: Int
    let weeklyGoal: Int
    let currentStreak: Int
    let totalWorkoutsAllTime: Int
    let updatedAt: Date

    static let empty = WidgetData(
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
    static let userDefaultsKey = "widget_data"

    /// App Group identifier
    static let appGroupId = "group.com.strengthtracker.shared"
}
