import Foundation

public struct PersonalRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var exerciseId: UUID
    public var recordType: RecordType
    public var value: Double
    public var setId: UUID?
    public var achievedAt: Date
    public var weightRecordingKey: String?

    public init(id: UUID, exerciseId: UUID, recordType: RecordType, value: Double, setId: UUID?, achievedAt: Date, weightRecordingKey: String? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.recordType = recordType
        self.value = value
        self.setId = setId
        self.achievedAt = achievedAt
        self.weightRecordingKey = weightRecordingKey
    }
}

extension Array where Element == PersonalRecord {
    /// Convert only known each/total weights. Unknown or incompatible strength
    /// records remain stored, but cannot establish a baseline in another convention.
    public func matching(_ exercise: Exercise) -> [PersonalRecord] {
        if exercise.exerciseType == .bodyweightReps {
            return filter { $0.weightRecordingKey == exercise.personalRecordConvention }
        }
        guard exercise.isDumbbell else { return self }
        return compactMap { record in
            guard record.recordType != .maxVolume else { return record }
            let targetKey = exercise.weightRecording?.performanceKey
            if record.weightRecordingKey == targetKey { return record }
            guard let key = record.weightRecordingKey, let target = exercise.weightRecording else { return nil }
            let parts = key.split(separator: "/").map(String.init)
            guard parts.count == 3, parts[0] == target.equipment.rawValue,
                  parts[2] == (target.repetitions == .totalAlternating ? "alternating" : "perMovement"),
                  let entry = WeightRecording.WeightEntry(rawValue: parts[1]) else { return nil }
            var copy = record
            if record.recordType == .maxWeight || record.recordType == .estimatedOneRepMax {
                copy.value = (try? WeightRecordingHistory.inputWeight(record.value, entry: entry, for: exercise)) ?? record.value
            }
            copy.weightRecordingKey = targetKey
            return copy
        }
    }

    /// The best record per type: highest value wins; achievedAt breaks value ties
    /// (newest). Never pick by date alone — retro-logged records can carry a past
    /// achievedAt while holding the best value.
    public func bestPerType() -> [PersonalRecord] {
        var best: [RecordType: PersonalRecord] = [:]
        for record in self {
            if let existing = best[record.recordType] {
                if record.value > existing.value ||
                    (record.value == existing.value && record.achievedAt > existing.achievedAt) {
                    best[record.recordType] = record
                }
            } else {
                best[record.recordType] = record
            }
        }
        return Array(best.values)
    }
}
