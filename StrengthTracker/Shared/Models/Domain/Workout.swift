import Foundation

struct Workout: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var notes: String?
    var templateId: UUID?
    var healthKitWorkoutId: UUID?
    var exercises: [WorkoutExercise]

    var isInProgress: Bool { completedAt == nil }

    var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.exerciseVolume }
    }
}
