import Foundation

/// Maps a training day to a template and subset of exercises.
public struct DayScheduleEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var dayOfWeek: Int          // Calendar.weekday encoding (Sun=1, Mon=2..Sat=7) — NOT ISO 8601
    public var templateId: UUID?       // linked template for this day
    public var templateName: String?   // denormalized for display
    public var exerciseIds: [UUID]     // library exercise IDs to include

    public init(id: UUID = UUID(), dayOfWeek: Int, templateId: UUID? = nil, templateName: String? = nil, exerciseIds: [UUID] = []) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.templateId = templateId
        self.templateName = templateName
        self.exerciseIds = exerciseIds
    }
}

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
    public var trainingDays: [Int]?                    // Calendar.weekday day numbers (Sun=1, Mon=2..Sat=7), nil = use defaults
    public var deloadDays: [Int]?                      // Calendar.weekday day numbers for deload weeks (nil = use trainingDays)
    public var startDate: Date
    public var targetEndDate: Date?
    public var actualEndDate: Date?
    public var exercises: [PlanExercise]                // Selected exercises with 1RM
    public var blocks: [TrainingBlock]                  // Generated program structure
    public var adjustments: [PlanAdjustment]            // Historical modifications
    public var createdAt: Date
    public var updatedAt: Date
    public var daySchedule: [DayScheduleEntry]          // Per-day template + exercise mapping (empty = legacy)
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
        deloadDays: [Int]? = nil,
        startDate: Date = Date(),
        targetEndDate: Date? = nil,
        actualEndDate: Date? = nil,
        exercises: [PlanExercise] = [],
        blocks: [TrainingBlock] = [],
        adjustments: [PlanAdjustment] = [],
        daySchedule: [DayScheduleEntry] = [],
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
        self.deloadDays = deloadDays
        self.startDate = startDate
        self.targetEndDate = targetEndDate
        self.actualEndDate = actualEndDate
        self.exercises = exercises
        self.blocks = blocks
        self.adjustments = adjustments
        self.daySchedule = daySchedule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.creationSource = creationSource
    }

    // MARK: - Computed Properties

    /// Highest calendar-week index across all blocks (weeks are calendar buckets, so a
    /// block boundary inside a calendar week makes a plain durationWeeks sum overcount).
    public var totalWeeks: Int {
        blocks.flatMap(\.weeks).map(\.absoluteWeekNumber).max() ?? 0
    }

    /// Current block = first block that has open (not closed) weeks
    public var currentBlock: TrainingBlock? {
        blocks.first { !$0.allWeeksCompleted }
    }

    /// Current week resolved against the calendar (see `currentWeek(asOf:)`).
    public var currentWeek: TrainingWeek? {
        currentWeek(asOf: Date())
    }

    /// The calendar week containing `now`, preferring a bucket with open sessions.
    /// Falls back to the last bucket of this calendar week, then to the first week
    /// anywhere with open sessions.
    public func currentWeek(asOf now: Date = Date()) -> TrainingWeek? {
        let weeks = blocks.flatMap(\.weeks)
        let nowWeekStart = CalendarWeekBucketer.weekStart(of: now)
        let candidates = weeks.filter { $0.weekStartDate == nowWeekStart }
        return candidates.first { !$0.allSessionsClosed }
            ?? candidates.last
            ?? weeks.first { !$0.allSessionsClosed }
    }

    public var overallProgress: Double {
        guard !blocks.isEmpty else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let allSessions = blocks.flatMap(\.weeks).flatMap(\.sessions)
        let elapsedSessions = allSessions.filter { session in
            guard let scheduledDate = session.scheduledDate else { return true }
            return session.isSkipped || scheduledDate < endOfToday
        }
        let completedSessions = allSessions.filter(\.isCompleted).count
        guard !elapsedSessions.isEmpty else { return 0 }
        return min(1.0, Double(completedSessions) / Double(elapsedSessions.count))
    }

    public var isActive: Bool { status == .active }

    /// Closed calendar weeks (every session completed or skipped) since plan start
    public var completedWeeks: Int {
        blocks.flatMap(\.weeks).filter(\.allSessionsClosed).count
    }

    /// Elapsed calendar weeks since the plan's anchor week (week of the earliest
    /// scheduled session, falling back to startDate).
    public var elapsedCalendarWeeks: Int {
        elapsedCalendarWeeks(asOf: Date())
    }

    public func elapsedCalendarWeeks(asOf now: Date = Date()) -> Int {
        let earliest = blocks.flatMap(\.weeks).flatMap(\.sessions).compactMap(\.scheduledDate).min()
        let anchorWeekStart = CalendarWeekBucketer.weekStart(of: earliest ?? startDate)
        let nowWeekStart = CalendarWeekBucketer.weekStart(of: now)
        let days = CalendarWeekBucketer.mondayCalendar
            .dateComponents([.day], from: anchorWeekStart, to: nowWeekStart).day ?? 0
        return max(0, days / 7)
    }

    /// First open (not completed, not skipped) session ordered by scheduled date.
    public var nextPlannedSession: PlannedSession? {
        blocks.flatMap(\.weeks).flatMap(\.sessions)
            .filter { !$0.isClosed }
            .min { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }

    /// Latest scheduled date among open sessions — nil when nothing remains.
    public var projectedEndDate: Date? {
        blocks.flatMap(\.weeks).flatMap(\.sessions)
            .filter { !$0.isClosed }
            .compactMap(\.scheduledDate)
            .max()
    }
}
