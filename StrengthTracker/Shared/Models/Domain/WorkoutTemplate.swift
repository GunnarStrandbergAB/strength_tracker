import Foundation

struct WorkoutTemplate: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var name: String
    var notes: String?
    var sortOrder: Int
    var lastUsedAt: Date?
    var timesUsed: Int
    var exercises: [TemplateExercise]
}

struct TemplateExercise: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var exercise: Exercise
    var order: Int
    var supersetGroup: Int?
    var notes: String?
    var restTimerSeconds: Int?
    var targetSets: Int
    var targetReps: Int?
    var targetWeight: Double?
    var targetDurationSeconds: Int?
    var targetDistanceMeters: Double?
}

struct TemplateFolder: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var name: String
    var sortOrder: Int
}
