import Foundation

struct ExerciseSet: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var order: Int
    var setType: SetType
    var weight: Double?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var rpe: Double?
    var isCompleted: Bool
    var isPersonalRecord: Bool
    var completedAt: Date?

    var setVolume: Double {
        guard isCompleted, setType != .warmup else { return 0 }
        return (weight ?? 0) * Double(reps ?? 0)
    }
}

struct WorkoutExercise: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var exercise: Exercise
    var order: Int
    var supersetGroup: Int?
    var notes: String?
    var restTimerSeconds: Int?
    var sets: [ExerciseSet]

    var exerciseVolume: Double {
        sets.reduce(0) { $0 + $1.setVolume }
    }
}
