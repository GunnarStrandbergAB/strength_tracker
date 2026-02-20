import Foundation

/// A mesocycle block within the plan (3–6 weeks).
public struct TrainingBlock: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var blockPhase: BlockPhase?
    public var order: Int
    public var durationWeeks: Int
    public var weeks: [TrainingWeek]
    public var isDeload: Bool
    public var isCompleted: Bool
    public var completedAt: Date?
    public var volumeMultiplier: Double
    public var intensityFloor: Double
    public var intensityCeiling: Double
    public var notes: String?

    public init(
        id: UUID = UUID(),
        name: String,
        blockPhase: BlockPhase? = nil,
        order: Int,
        durationWeeks: Int,
        weeks: [TrainingWeek] = [],
        isDeload: Bool = false,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        volumeMultiplier: Double = 1.0,
        intensityFloor: Double = 0.65,
        intensityCeiling: Double = 0.85,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.blockPhase = blockPhase
        self.order = order
        self.durationWeeks = durationWeeks
        self.weeks = weeks
        self.isDeload = isDeload
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.volumeMultiplier = volumeMultiplier
        self.intensityFloor = intensityFloor
        self.intensityCeiling = intensityCeiling
        self.notes = notes
    }

    public var currentWeek: TrainingWeek? {
        weeks.first { !$0.allSessionsCompleted }
    }

    public var progress: Double {
        guard !weeks.isEmpty else { return 0 }
        let completed = weeks.filter { $0.allSessionsCompleted }.count
        return Double(completed) / Double(weeks.count)
    }

    public var allWeeksCompleted: Bool {
        !weeks.isEmpty && weeks.allSatisfy { $0.allSessionsCompleted }
    }
}
