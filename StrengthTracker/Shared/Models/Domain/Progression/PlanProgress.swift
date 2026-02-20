import Foundation

public struct PlanProgress: Identifiable, Codable, Sendable {
    public let id: UUID
    public let planId: UUID
    public var snapshotDate: Date
    public var overallAdherence: Double
    public var exerciseProgress: [ExerciseProgress]
    public var blockProgress: [BlockProgress]
    public var estimatedCompletionDate: Date?
    public var isOnTrack: Bool
    public var weeklyVolumeHistory: [WeeklyVolume]
    public var deloadCount: Int
    public var adjustmentCount: Int

    public init(
        id: UUID = UUID(),
        planId: UUID,
        snapshotDate: Date = Date(),
        overallAdherence: Double = 0,
        exerciseProgress: [ExerciseProgress] = [],
        blockProgress: [BlockProgress] = [],
        estimatedCompletionDate: Date? = nil,
        isOnTrack: Bool = true,
        weeklyVolumeHistory: [WeeklyVolume] = [],
        deloadCount: Int = 0,
        adjustmentCount: Int = 0
    ) {
        self.id = id
        self.planId = planId
        self.snapshotDate = snapshotDate
        self.overallAdherence = overallAdherence
        self.exerciseProgress = exerciseProgress
        self.blockProgress = blockProgress
        self.estimatedCompletionDate = estimatedCompletionDate
        self.isOnTrack = isOnTrack
        self.weeklyVolumeHistory = weeklyVolumeHistory
        self.deloadCount = deloadCount
        self.adjustmentCount = adjustmentCount
    }
}

public struct ExerciseProgress: Identifiable, Codable, Sendable {
    public let id: UUID
    public let planExerciseId: UUID
    public var exerciseName: String
    public var starting1RM: Double
    public var current1RM: Double
    public var target1RM: Double?
    public var progressPercentage: Double
    public var lastPerformedDate: Date?
    public var totalSetsCompleted: Int
    public var totalRepsCompleted: Int
    public var totalVolumeLifted: Double
    public var personalRecordsHit: Int

    public init(
        id: UUID = UUID(),
        planExerciseId: UUID,
        exerciseName: String,
        starting1RM: Double,
        current1RM: Double,
        target1RM: Double? = nil,
        progressPercentage: Double = 0,
        lastPerformedDate: Date? = nil,
        totalSetsCompleted: Int = 0,
        totalRepsCompleted: Int = 0,
        totalVolumeLifted: Double = 0,
        personalRecordsHit: Int = 0
    ) {
        self.id = id
        self.planExerciseId = planExerciseId
        self.exerciseName = exerciseName
        self.starting1RM = starting1RM
        self.current1RM = current1RM
        self.target1RM = target1RM
        self.progressPercentage = progressPercentage
        self.lastPerformedDate = lastPerformedDate
        self.totalSetsCompleted = totalSetsCompleted
        self.totalRepsCompleted = totalRepsCompleted
        self.totalVolumeLifted = totalVolumeLifted
        self.personalRecordsHit = personalRecordsHit
    }
}

public struct BlockProgress: Identifiable, Codable, Sendable {
    public let id: UUID
    public let blockId: UUID
    public var blockName: String
    public var weeklyAdherence: [Double]
    public var averageRPE: Double?
    public var volumeTrend: Double

    public init(
        id: UUID = UUID(),
        blockId: UUID,
        blockName: String,
        weeklyAdherence: [Double] = [],
        averageRPE: Double? = nil,
        volumeTrend: Double = 0
    ) {
        self.id = id
        self.blockId = blockId
        self.blockName = blockName
        self.weeklyAdherence = weeklyAdherence
        self.averageRPE = averageRPE
        self.volumeTrend = volumeTrend
    }
}

public struct WeeklyVolume: Identifiable, Codable, Sendable {
    public let id: UUID
    public var weekNumber: Int
    public var totalVolume: Double
    public var averageIntensity: Double
    public var sessionCount: Int

    public init(
        id: UUID = UUID(),
        weekNumber: Int,
        totalVolume: Double,
        averageIntensity: Double,
        sessionCount: Int
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.totalVolume = totalVolume
        self.averageIntensity = averageIntensity
        self.sessionCount = sessionCount
    }
}
