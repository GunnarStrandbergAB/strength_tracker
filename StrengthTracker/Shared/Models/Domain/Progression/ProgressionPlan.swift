import Foundation

/// Root model: a user's progression plan
public struct ProgressionPlan: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var status: PlanStatus
    public var trainingStatus: TrainingStatus
    public var programType: ProgramType
    public var primaryGoal: TrainingGoal
    public var secondaryGoal: TrainingGoal?
    public var weeklyFrequency: Int                    // Training days per week
    public var trainingDays: [Int]?                    // Specific ISO 8601 day numbers (Mon=2..Sun=1), nil = use defaults
    public var startDate: Date
    public var targetEndDate: Date?
    public var actualEndDate: Date?
    public var exercises: [PlanExercise]                // Selected exercises with 1RM
    public var blocks: [TrainingBlock]                  // Generated program structure
    public var adjustments: [PlanAdjustment]            // Historical modifications
    public var createdAt: Date
    public var updatedAt: Date
    public var notes: String?
    public var creationSource: PlanCreationSource?

    public enum PlanCreationSource: String, Codable, Sendable {
        case structuredFlow          // Traditional 4-step creation
        case naturalLanguage         // Apple Intelligence guided generation
    }

    public init(
        id: UUID = UUID(),
        name: String,
        status: PlanStatus = .draft,
        trainingStatus: TrainingStatus,
        programType: ProgramType,
        primaryGoal: TrainingGoal,
        secondaryGoal: TrainingGoal? = nil,
        weeklyFrequency: Int,
        trainingDays: [Int]? = nil,
        startDate: Date = Date(),
        targetEndDate: Date? = nil,
        actualEndDate: Date? = nil,
        exercises: [PlanExercise] = [],
        blocks: [TrainingBlock] = [],
        adjustments: [PlanAdjustment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        notes: String? = nil,
        creationSource: PlanCreationSource? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.trainingStatus = trainingStatus
        self.programType = programType
        self.primaryGoal = primaryGoal
        self.secondaryGoal = secondaryGoal
        self.weeklyFrequency = weeklyFrequency
        self.trainingDays = trainingDays
        self.startDate = startDate
        self.targetEndDate = targetEndDate
        self.actualEndDate = actualEndDate
        self.exercises = exercises
        self.blocks = blocks
        self.adjustments = adjustments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.creationSource = creationSource
    }

    // MARK: - Computed Properties

    public var totalWeeks: Int {
        blocks.reduce(0) { $0 + $1.durationWeeks }
    }

    /// Current block = first block that has incomplete weeks
    public var currentBlock: TrainingBlock? {
        blocks.first { !$0.allWeeksCompleted }
    }

    /// Current week = first incomplete week in the current block
    public var currentWeek: TrainingWeek? {
        currentBlock?.currentWeek
    }

    public var overallProgress: Double {
        guard !blocks.isEmpty else { return 0 }
        let totalSessions = blocks.flatMap(\.weeks).flatMap(\.sessions).count
        let completedSessions = blocks.flatMap(\.weeks).flatMap(\.sessions).filter(\.isCompleted).count
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }

    public var isActive: Bool { status == .active }

    /// Completed microcycles since plan start
    public var completedWeeks: Int {
        blocks.flatMap(\.weeks).filter(\.allSessionsCompleted).count
    }

    /// Elapsed calendar weeks since start
    public var elapsedCalendarWeeks: Int {
        Calendar.current.dateComponents([.weekOfYear], from: startDate, to: Date()).weekOfYear ?? 0
    }

    // MARK: - Dynamic Date Projection

    public var averageDaysPerWeek: Double {
        guard completedWeeks > 0 else { return 7.0 }
        let allCompletionDates = blocks.flatMap(\.weeks).flatMap(\.sessions).compactMap(\.completedAt)
        guard let firstCompletion = allCompletionDates.min(),
              let lastCompletion = allCompletionDates.max() else { return 7.0 }
        let elapsed = lastCompletion.timeIntervalSince(firstCompletion)
        let days = max(1, elapsed / 86400)
        return days / Double(completedWeeks)
    }

    public func projectedDateRange(forAbsoluteWeek weekNum: Int) -> (start: Date, end: Date) {
        let weeksFromStart = weekNum - 1
        let daysOffset = Int(Double(weeksFromStart) * averageDaysPerWeek)
        let start = Calendar.current.date(byAdding: .day, value: daysOffset, to: startDate)!
        let end = Calendar.current.date(byAdding: .day, value: Int(averageDaysPerWeek) - 1, to: start)!
        return (start, end)
    }

    public var projectedEndDate: Date? {
        let remainingWeeks = totalWeeks - completedWeeks
        guard remainingWeeks > 0 else { return nil }
        let daysRemaining = Int(Double(remainingWeeks) * averageDaysPerWeek)
        return Calendar.current.date(byAdding: .day, value: daysRemaining, to: Date())
    }
}
