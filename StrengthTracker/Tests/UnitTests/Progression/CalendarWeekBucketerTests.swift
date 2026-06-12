import Testing
import Foundation
@testable import StrengthTrackerShared

/// Tests for the Model A calendar-week restructure: sequential microcycle dating,
/// Monday-anchored re-bucketing, skip semantics, and derived plan properties.
///
/// All dates are pinned via DateComponents — expectations never depend on Date()
/// except where a property hard-codes "today" (those tests use far-future or nil
/// dates so the expectation is stable).
@Suite("CalendarWeekBucketer")
struct CalendarWeekBucketerTests {

    // MARK: - Date Helpers (pinned)

    private var cal: Calendar { CalendarWeekBucketer.mondayCalendar }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // Pinned 2026 reference dates (June 1, 2026 is a Monday)
    private var mondayJun1: Date { date(2026, 6, 1) }
    private var sundayJun7: Date { date(2026, 6, 7) }
    private var saturdayJun13: Date { date(2026, 6, 13) }

    // MARK: - Session/Block Builders

    private func session(
        day: Int?,
        label: String = "S",
        isDeload: Bool = false,
        scheduledDate: Date? = nil,
        completed: Bool = false,
        skipped: Bool = false
    ) -> PlannedSession {
        PlannedSession(
            dayOfWeek: day,
            scheduledDate: scheduledDate,
            sessionLabel: label,
            completedWorkoutId: completed ? UUID() : nil,
            completedAt: completed ? scheduledDate : nil,
            isDeload: isDeload,
            isSkipped: skipped,
            skippedAt: skipped ? scheduledDate : nil
        )
    }

    /// One block of `microcycles` undated microcycle weeks over the given training days.
    private func microcycleBlock(
        days: [Int],
        microcycles: Int,
        deloadMicrocycles: Set<Int> = []
    ) -> TrainingBlock {
        let weeks = (1...microcycles).map { weekNum in
            TrainingWeek(
                weekNumber: weekNum,
                absoluteWeekNumber: weekNum,
                sessions: days.map {
                    session(day: $0, isDeload: deloadMicrocycles.contains(weekNum))
                },
                isDeload: deloadMicrocycles.contains(weekNum)
            )
        }
        return TrainingBlock(name: "Block 1", order: 0, durationWeeks: microcycles, weeks: weeks)
    }

    private func allSessions(_ blocks: [TrainingBlock]) -> [PlannedSession] {
        blocks.flatMap(\.weeks).flatMap(\.sessions)
    }

    // MARK: - Bucketing

    @Test("Saturday start with Sat/Mon/Wed days: week 1 holds only the weekend session, last week partial")
    func saturdayStartBuckets() {
        var blocks = [microcycleBlock(days: [7, 2, 4], microcycles: 3)] // Sat/Mon/Wed
        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: saturdayJun13)
        let bucketed = CalendarWeekBucketer.rebucket(blocks)

        let weeks = bucketed[0].weeks
        #expect(weeks.count == 4)
        #expect(bucketed[0].durationWeeks == 4)

        // Week 1: only Sat Jun 13 (Mon-anchored week Jun 8–14)
        #expect(weeks[0].absoluteWeekNumber == 1)
        #expect(weeks[0].sessions.map(\.scheduledDate) == [date(2026, 6, 13)])

        // Middle weeks: Mon/Wed of one microcycle + Sat of the next
        #expect(weeks[1].sessions.compactMap(\.scheduledDate) ==
                [date(2026, 6, 15), date(2026, 6, 17), date(2026, 6, 20)])
        #expect(weeks[2].sessions.compactMap(\.scheduledDate) ==
                [date(2026, 6, 22), date(2026, 6, 24), date(2026, 6, 27)])

        // Last week: partial (Mon/Wed of microcycle 3 only)
        #expect(weeks[3].sessions.compactMap(\.scheduledDate) ==
                [date(2026, 6, 29), date(2026, 7, 1)])
        #expect(weeks[3].absoluteWeekNumber == 4)

        // weekNumber is the 1-based ordinal within the block
        #expect(weeks.map(\.weekNumber) == [1, 2, 3, 4])
    }

    @Test("Monday start: calendar buckets are identical to microcycles")
    func mondayStartMatchesMicrocycles() {
        var blocks = [microcycleBlock(days: [2, 4, 6], microcycles: 2)] // Mon/Wed/Fri
        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: mondayJun1)
        let bucketed = CalendarWeekBucketer.rebucket(blocks)

        let weeks = bucketed[0].weeks
        #expect(weeks.count == 2)
        #expect(weeks[0].sessions.compactMap(\.scheduledDate) ==
                [date(2026, 6, 1), date(2026, 6, 3), date(2026, 6, 5)])
        #expect(weeks[1].sessions.compactMap(\.scheduledDate) ==
                [date(2026, 6, 8), date(2026, 6, 10), date(2026, 6, 12)])
        #expect(weeks.map(\.absoluteWeekNumber) == [1, 2])
    }

    @Test("Sunday start with Mon/Wed/Fri days: anchor is the first session's week, no empty week 1")
    func sundayStartNoEmptyWeekOne() {
        var blocks = [microcycleBlock(days: [2, 4, 6], microcycles: 2)] // Mon/Wed/Fri
        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: sundayJun7)
        let bucketed = CalendarWeekBucketer.rebucket(blocks)

        let weeks = bucketed[0].weeks
        // First sessions land Mon Jun 8 — the anchor week is Jun 8, not the start's week
        #expect(weeks[0].absoluteWeekNumber == 1)
        #expect(weeks[0].weekStartDate == date(2026, 6, 8))
        #expect(weeks[0].sessions.count == 3)
        #expect(weeks.allSatisfy { !$0.sessions.isEmpty })
    }

    @Test("Deload microcycle straddling two buckets: per-session truth survives, neither bucket is fully deload")
    func deloadStraddlesBuckets() {
        // Sat/Mon training, microcycle 2 is deload, microcycle 3 normal again.
        var blocks = [microcycleBlock(days: [7, 2], microcycles: 3, deloadMicrocycles: [2])]
        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: saturdayJun13)
        let bucketed = CalendarWeekBucketer.rebucket(blocks)
        let weeks = bucketed[0].weeks

        // Bucket Jun 15: Mon 15 (normal) + Sat 20 (deload)
        let mixed1 = weeks.first { $0.weekStartDate == date(2026, 6, 15) }!
        #expect(mixed1.sessions.map(\.isDeload) == [false, true])
        #expect(!mixed1.isDeload)
        #expect(mixed1.containsDeloadSessions)

        // Bucket Jun 22: Mon 22 (deload) + Sat 27 (normal)
        let mixed2 = weeks.first { $0.weekStartDate == date(2026, 6, 22) }!
        #expect(mixed2.sessions.map(\.isDeload) == [true, false])
        #expect(!mixed2.isDeload)
        #expect(mixed2.containsDeloadSessions)
    }

    @Test("rebucket is idempotent and keeps week ids stable across re-runs")
    func rebucketIdempotentAndIdStable() {
        var blocks = [microcycleBlock(days: [7, 2, 4], microcycles: 3)]
        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: saturdayJun13)
        let once = CalendarWeekBucketer.rebucket(blocks)
        let twice = CalendarWeekBucketer.rebucket(once)

        #expect(once == twice)
        #expect(once[0].weeks.map(\.id) == twice[0].weeks.map(\.id))
    }

    @Test("Rescheduling a session across a week boundary moves it to the right bucket")
    func rescheduleAcrossBuckets() {
        var blocks = [microcycleBlock(days: [2, 4], microcycles: 2)] // Mon/Wed
        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: mondayJun1)
        var bucketed = CalendarWeekBucketer.rebucket(blocks)

        let week1Id = bucketed[0].weeks[0].id
        let week2Id = bucketed[0].weeks[1].id

        // Move Wed Jun 3 (week 1) to Thu Jun 11 (week 2)
        let movedId = bucketed[0].weeks[0].sessions[1].id
        bucketed[0].weeks[0].sessions[1].scheduledDate = date(2026, 6, 11)
        let rebucketed = CalendarWeekBucketer.rebucket(bucketed)

        let weeks = rebucketed[0].weeks
        #expect(weeks.count == 2)
        #expect(weeks[0].id == week1Id)
        #expect(weeks[1].id == week2Id)
        #expect(weeks[0].sessions.count == 1)
        #expect(weeks[1].sessions.count == 3)
        #expect(weeks[1].sessions.contains { $0.id == movedId })
        // Sessions within the destination bucket stay date-sorted
        let dates = weeks[1].sessions.compactMap(\.scheduledDate)
        #expect(dates == dates.sorted())
    }

    @Test("assignSequentialDates onlyMissing preserves a manually-set date")
    func onlyMissingPreservesManualDates() {
        var blocks = [microcycleBlock(days: [2, 4], microcycles: 2)]
        let manualDate = date(2026, 6, 25)
        blocks[0].weeks[0].sessions[0].scheduledDate = manualDate

        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: mondayJun1, onlyMissing: true)

        #expect(blocks[0].weeks[0].sessions[0].scheduledDate == manualDate)
        // Undated siblings got their sequential dates
        #expect(blocks[0].weeks[0].sessions[1].scheduledDate == date(2026, 6, 3))
        #expect(blocks[0].weeks[1].sessions[0].scheduledDate == date(2026, 6, 8))
    }

    @Test("v1-shaped migration path: onlyMissing dating + rebucket yields calendar buckets")
    func migrationBucketsV1Blocks() {
        // v1 plan: microcycle weeks; one session was already user-rescheduled.
        var blocks = [microcycleBlock(days: [7, 2], microcycles: 2)] // Sat/Mon
        let rescheduled = date(2026, 6, 16) // Tue of the second calendar week
        blocks[0].weeks[0].sessions[1].scheduledDate = rescheduled

        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: saturdayJun13, onlyMissing: true)
        let migrated = CalendarWeekBucketer.rebucket(blocks)

        let weeks = migrated[0].weeks
        // Anchor week (Jun 8): Sat Jun 13 only; rescheduled session is in the Jun 15 bucket
        #expect(weeks[0].sessions.compactMap(\.scheduledDate) == [date(2026, 6, 13)])
        #expect(weeks[1].sessions.compactMap(\.scheduledDate).contains(rescheduled))
        #expect(migrated[0].durationWeeks == weeks.count)
    }

    // MARK: - PlannedSession.isClosed

    @Test("isClosed = completed or skipped")
    func isClosedSemantics() {
        #expect(!session(day: 2).isClosed)
        #expect(session(day: 2, completed: true).isClosed)
        #expect(session(day: 2, skipped: true).isClosed)
        #expect(session(day: 2, completed: true, skipped: true).isClosed)
    }

    // MARK: - ProgressionPlan derived properties

    private func bucketedPlan(
        days: [Int] = [2, 4],
        microcycles: Int = 2,
        startDate: Date
    ) -> ProgressionPlan {
        var blocks = [microcycleBlock(days: days, microcycles: microcycles)]
        CalendarWeekBucketer.assignSequentialDates(to: &blocks, startDate: startDate)
        return ProgressionTestHelpers.makeTestPlan(
            blocks: CalendarWeekBucketer.rebucket(blocks),
            startDate: startDate
        )
    }

    @Test("currentWeek(asOf:) picks this calendar week's bucket, with fallbacks")
    func currentWeekAsOf() {
        var plan = bucketedPlan(startDate: mondayJun1)

        // A date inside week 2 resolves to the week-2 bucket
        let week2 = plan.currentWeek(asOf: date(2026, 6, 9))
        #expect(week2?.weekStartDate == date(2026, 6, 8))

        // When this week's bucket is fully closed, fall back to that bucket (candidates.last)
        for si in plan.blocks[0].weeks[0].sessions.indices {
            plan.blocks[0].weeks[0].sessions[si].isSkipped = true
        }
        let closedCurrent = plan.currentWeek(asOf: date(2026, 6, 2))
        #expect(closedCurrent?.weekStartDate == date(2026, 6, 1))

        // A date outside any bucket falls back to the first open week
        let outside = plan.currentWeek(asOf: date(2026, 8, 1))
        #expect(outside?.weekStartDate == date(2026, 6, 8))
    }

    @Test("overallProgress counts skipped sessions as elapsed but not completed")
    func overallProgressWithSkips() {
        // Date-independent: completed session has nil date (always elapsed); the
        // skipped and open sessions sit in the far future (elapsed only via skip).
        let future = date(2099, 1, 5)
        let week = TrainingWeek(weekNumber: 1, absoluteWeekNumber: 1, sessions: [
            session(day: 2, completed: true),                       // elapsed + completed
            session(day: 4, scheduledDate: future, skipped: true),  // elapsed via skip
            session(day: 6, scheduledDate: future),                 // not elapsed
        ])
        let block = TrainingBlock(name: "B", order: 0, durationWeeks: 1, weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], startDate: date(2099, 1, 4))

        #expect(plan.overallProgress == 0.5)
    }

    @Test("nextPlannedSession is the earliest open session, skipping closed ones")
    func nextPlannedSessionOrdering() {
        var plan = bucketedPlan(startDate: mondayJun1)
        // Close the first two sessions (complete one, skip one)
        plan.blocks[0].weeks[0].sessions[0].completedWorkoutId = UUID()
        plan.blocks[0].weeks[0].sessions[1].isSkipped = true

        #expect(plan.nextPlannedSession?.scheduledDate == date(2026, 6, 8))

        // Undated open sessions sort last
        plan.blocks[0].weeks[1].sessions[0].scheduledDate = nil
        #expect(plan.nextPlannedSession?.scheduledDate == date(2026, 6, 10))
    }

    // MARK: - Generation-level

    @Test("Advanced Block program: 3 phases, zero deload sessions, calendar-bucketed")
    func advancedBlockProgramHasNoDeload() {
        let plan = ProgressionTestHelpers.makeTestPlan(
            exercises: ProgressionTestHelpers.standardExercises(),
            trainingStatus: .advanced,
            programType: .block,
            primaryGoal: .strength,
            weeklyFrequency: 4,
            startDate: mondayJun1
        )
        let blocks = ProgramDesignService().generateProgram(for: plan)

        #expect(blocks.count == 3)
        #expect(blocks.compactMap(\.blockPhase) == [.accumulation, .transmutation, .realization])
        #expect(allSessions(blocks).allSatisfy { !$0.isDeload })
        // Every session is dated and buckets are non-empty
        #expect(allSessions(blocks).allSatisfy { $0.scheduledDate != nil })
        #expect(blocks.flatMap(\.weeks).allSatisfy { !$0.sessions.isEmpty })
    }
}
