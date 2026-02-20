import XCTest
import Foundation
@testable import StrengthTrackerShared

// MARK: - Enum Tests

final class TrainingStatusTests: XCTestCase {

    func testBeginnerRecommendedProgramType() {
        XCTAssertEqual(TrainingStatus.beginner.recommendedProgramType, .linear)
    }

    func testIntermediateRecommendedProgramType() {
        XCTAssertEqual(TrainingStatus.intermediate.recommendedProgramType, .dailyUndulating)
    }

    func testAdvancedRecommendedProgramType() {
        XCTAssertEqual(TrainingStatus.advanced.recommendedProgramType, .block)
    }

    func testBeginnerWeeklyFrequencyRange() {
        XCTAssertEqual(TrainingStatus.beginner.weeklyFrequencyRange, 3...4)
    }

    func testIntermediateWeeklyFrequencyRange() {
        XCTAssertEqual(TrainingStatus.intermediate.weeklyFrequencyRange, 4...5)
    }

    func testAdvancedWeeklyFrequencyRange() {
        XCTAssertEqual(TrainingStatus.advanced.weeklyFrequencyRange, 4...6)
    }

    func testBeginnerProgressionRate() {
        XCTAssertEqual(TrainingStatus.beginner.progressionRate, "Session-to-session (2.5–5 kg/week)")
    }

    func testIntermediateProgressionRate() {
        XCTAssertEqual(TrainingStatus.intermediate.progressionRate, "Weekly (1–2.5 kg/week)")
    }

    func testAdvancedProgressionRate() {
        XCTAssertEqual(TrainingStatus.advanced.progressionRate, "Monthly (0.5–1 kg/month)")
    }
}

final class ProgramTypeTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(ProgramType.linear.displayName, "Linear Periodization")
        XCTAssertEqual(ProgramType.dailyUndulating.displayName, "Daily Undulating (DUP)")
        XCTAssertEqual(ProgramType.weeklyUndulating.displayName, "Weekly Undulating (WUP)")
        XCTAssertEqual(ProgramType.block.displayName, "Block Periodization")
    }

    func testLinearSuitableForBeginnerAndIntermediate() {
        let suitable = ProgramType.linear.suitableFor
        XCTAssertTrue(suitable.contains(.beginner))
        XCTAssertTrue(suitable.contains(.intermediate))
        XCTAssertFalse(suitable.contains(.advanced))
    }

    func testDUPSuitableForIntermediateAndAdvanced() {
        let suitable = ProgramType.dailyUndulating.suitableFor
        XCTAssertFalse(suitable.contains(.beginner))
        XCTAssertTrue(suitable.contains(.intermediate))
        XCTAssertTrue(suitable.contains(.advanced))
    }

    func testWUPSuitableForIntermediateAndAdvanced() {
        let suitable = ProgramType.weeklyUndulating.suitableFor
        XCTAssertFalse(suitable.contains(.beginner))
        XCTAssertTrue(suitable.contains(.intermediate))
        XCTAssertTrue(suitable.contains(.advanced))
    }

    func testBlockSuitableForAdvancedOnly() {
        let suitable = ProgramType.block.suitableFor
        XCTAssertEqual(suitable, [.advanced])
    }
}

final class TrainingGoalTests: XCTestCase {

    func testStrengthRepRange() {
        XCTAssertEqual(TrainingGoal.strength.repRange, 1...5)
    }

    func testHypertrophyRepRange() {
        XCTAssertEqual(TrainingGoal.hypertrophy.repRange, 6...12)
    }

    func testMuscularEnduranceRepRange() {
        XCTAssertEqual(TrainingGoal.muscularEndurance.repRange, 12...20)
    }

    func testPowerliftingRepRange() {
        XCTAssertEqual(TrainingGoal.powerlifting.repRange, 1...5)
    }

    func testGeneralFitnessRepRange() {
        XCTAssertEqual(TrainingGoal.generalFitness.repRange, 6...15)
    }

    func testStrengthIntensityRange() {
        XCTAssertEqual(TrainingGoal.strength.intensityRange, 0.85...1.0)
    }

    func testHypertrophyIntensityRange() {
        XCTAssertEqual(TrainingGoal.hypertrophy.intensityRange, 0.65...0.85)
    }

    func testMuscularEnduranceIntensityRange() {
        XCTAssertEqual(TrainingGoal.muscularEndurance.intensityRange, 0.50...0.65)
    }

    func testPowerliftingIntensityRange() {
        XCTAssertEqual(TrainingGoal.powerlifting.intensityRange, 0.85...1.0)
    }

    func testGeneralFitnessIntensityRange() {
        XCTAssertEqual(TrainingGoal.generalFitness.intensityRange, 0.60...0.80)
    }

    func testStrengthRestSeconds() {
        XCTAssertEqual(TrainingGoal.strength.restSeconds, 180...300)
    }

    func testHypertrophyRestSeconds() {
        XCTAssertEqual(TrainingGoal.hypertrophy.restSeconds, 60...120)
    }

    func testMuscularEnduranceRestSeconds() {
        XCTAssertEqual(TrainingGoal.muscularEndurance.restSeconds, 30...60)
    }

    func testPowerliftingRestSeconds() {
        XCTAssertEqual(TrainingGoal.powerlifting.restSeconds, 180...300)
    }

    func testGeneralFitnessRestSeconds() {
        XCTAssertEqual(TrainingGoal.generalFitness.restSeconds, 60...180)
    }
}

final class BlockPhaseTests: XCTestCase {

    func testAccumulationWeekDuration() {
        XCTAssertEqual(BlockPhase.accumulation.weekDuration, 4)
    }

    func testTransmutationWeekDuration() {
        XCTAssertEqual(BlockPhase.transmutation.weekDuration, 3)
    }

    func testRealizationWeekDuration() {
        XCTAssertEqual(BlockPhase.realization.weekDuration, 2)
    }

    func testDeloadWeekDuration() {
        XCTAssertEqual(BlockPhase.deload.weekDuration, 1)
    }
}

final class DUPSessionTypeTests: XCTestCase {

    func testHypertrophySets() {
        XCTAssertEqual(DUPSessionType.hypertrophy.sets, 3)
    }

    func testStrengthSets() {
        XCTAssertEqual(DUPSessionType.strength.sets, 4)
    }

    func testPowerSets() {
        XCTAssertEqual(DUPSessionType.power.sets, 5)
    }

    func testHypertrophyRepRange() {
        XCTAssertEqual(DUPSessionType.hypertrophy.repRange, 8...12)
    }

    func testStrengthRepRange() {
        XCTAssertEqual(DUPSessionType.strength.repRange, 3...5)
    }

    func testPowerRepRange() {
        XCTAssertEqual(DUPSessionType.power.repRange, 1...3)
    }

    func testHypertrophyIntensityRange() {
        XCTAssertEqual(DUPSessionType.hypertrophy.intensityRange, 0.65...0.75)
    }

    func testStrengthIntensityRange() {
        XCTAssertEqual(DUPSessionType.strength.intensityRange, 0.80...0.88)
    }

    func testPowerIntensityRange() {
        XCTAssertEqual(DUPSessionType.power.intensityRange, 0.88...0.95)
    }
}

// MARK: - ProgressionPlan Tests

final class ProgressionPlanTests: XCTestCase {

    // MARK: - totalWeeks

    func testTotalWeeksSumsBlockDurations() {
        let block1 = ProgressionTestHelpers.makeTestTrainingBlock(name: "Block 1", durationWeeks: 4)
        let block2 = ProgressionTestHelpers.makeTestTrainingBlock(name: "Block 2", durationWeeks: 3)
        let block3 = ProgressionTestHelpers.makeTestTrainingBlock(name: "Block 3", durationWeeks: 2)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block1, block2, block3])

        XCTAssertEqual(plan.totalWeeks, 9)
    }

    func testTotalWeeksWithEmptyBlocksIsZero() {
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [])
        XCTAssertEqual(plan.totalWeeks, 0)
    }

    func testTotalWeeksWithSingleBlock() {
        let block = ProgressionTestHelpers.makeTestTrainingBlock(durationWeeks: 6)
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])
        XCTAssertEqual(plan.totalWeeks, 6)
    }

    // MARK: - currentBlock

    func testCurrentBlockReturnsFirstIncompleteBlock() {
        // Block 1: all sessions completed
        let completedSession = ProgressionTestHelpers.makeCompletedSession()
        let completedWeek = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [completedSession])
        let completedBlock = ProgressionTestHelpers.makeTestTrainingBlock(
            name: "Completed Block", order: 0, weeks: [completedWeek]
        )

        // Block 2: incomplete
        let incompleteSession = ProgressionTestHelpers.makeIncompleteSession()
        let incompleteWeek = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [incompleteSession])
        let incompleteBlock = ProgressionTestHelpers.makeTestTrainingBlock(
            name: "Incomplete Block", order: 1, weeks: [incompleteWeek]
        )

        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [completedBlock, incompleteBlock])

        XCTAssertEqual(plan.currentBlock?.name, "Incomplete Block")
    }

    func testCurrentBlockReturnsNilWhenAllCompleted() {
        let completedSession = ProgressionTestHelpers.makeCompletedSession()
        let completedWeek = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [completedSession])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [completedWeek])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertNil(plan.currentBlock)
    }

    func testCurrentBlockReturnsNilWithEmptyBlocks() {
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [])
        XCTAssertNil(plan.currentBlock)
    }

    // MARK: - currentWeek

    func testCurrentWeekReturnsFirstIncompleteWeekInCurrentBlock() {
        let completedSession = ProgressionTestHelpers.makeCompletedSession()
        let incompleteSession = ProgressionTestHelpers.makeIncompleteSession()
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [completedSession])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [incompleteSession])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertEqual(plan.currentWeek?.weekNumber, 2)
    }

    func testCurrentWeekReturnsNilWhenAllCompleted() {
        let completedSession = ProgressionTestHelpers.makeCompletedSession()
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [completedSession])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertNil(plan.currentWeek)
    }

    // MARK: - overallProgress

    func testOverallProgressWithZeroSessionsIsZero() {
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertEqual(plan.overallProgress, 0)
    }

    func testOverallProgressWithEmptyBlocksIsZero() {
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [])
        XCTAssertEqual(plan.overallProgress, 0)
    }

    func testOverallProgressPartialCompletion() {
        let completed = ProgressionTestHelpers.makeCompletedSession(label: "Done")
        let incomplete = ProgressionTestHelpers.makeIncompleteSession(label: "Not Done")
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [completed, incomplete])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertEqual(plan.overallProgress, 0.5, accuracy: 0.001)
    }

    func testOverallProgressFullCompletion() {
        let s1 = ProgressionTestHelpers.makeCompletedSession(label: "S1")
        let s2 = ProgressionTestHelpers.makeCompletedSession(label: "S2")
        let s3 = ProgressionTestHelpers.makeCompletedSession(label: "S3")
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [s1, s2, s3])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertEqual(plan.overallProgress, 1.0, accuracy: 0.001)
    }

    func testOverallProgressAcrossMultipleBlocks() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "C1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "C2")
        let i1 = ProgressionTestHelpers.makeIncompleteSession(label: "I1")
        let i2 = ProgressionTestHelpers.makeIncompleteSession(label: "I2")

        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c1, c2])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [i1, i2])
        let block1 = ProgressionTestHelpers.makeTestTrainingBlock(name: "B1", order: 0, weeks: [week1])
        let block2 = ProgressionTestHelpers.makeTestTrainingBlock(name: "B2", order: 1, weeks: [week2])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block1, block2])

        // 2 completed out of 4 total = 0.5
        XCTAssertEqual(plan.overallProgress, 0.5, accuracy: 0.001)
    }

    // MARK: - isActive

    func testIsActiveWhenStatusActive() {
        let plan = ProgressionTestHelpers.makeTestPlan(status: .active)
        XCTAssertTrue(plan.isActive)
    }

    func testIsActiveWhenStatusDraft() {
        let plan = ProgressionTestHelpers.makeTestPlan(status: .draft)
        XCTAssertFalse(plan.isActive)
    }

    func testIsActiveWhenStatusCompleted() {
        let plan = ProgressionTestHelpers.makeTestPlan(status: .completed)
        XCTAssertFalse(plan.isActive)
    }

    func testIsActiveWhenStatusPaused() {
        let plan = ProgressionTestHelpers.makeTestPlan(status: .paused)
        XCTAssertFalse(plan.isActive)
    }

    func testIsActiveWhenStatusAbandoned() {
        let plan = ProgressionTestHelpers.makeTestPlan(status: .abandoned)
        XCTAssertFalse(plan.isActive)
    }

    // MARK: - completedWeeks

    func testCompletedWeeksCountsOnlyFullyCompleted() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "C1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "C2")
        let i1 = ProgressionTestHelpers.makeIncompleteSession(label: "I1")

        // Week 1: all completed
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c1])
        // Week 2: partially completed (1 of 2)
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [c2, i1])

        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertEqual(plan.completedWeeks, 1)
    }

    func testCompletedWeeksWithNoCompletedWeeks() {
        let i1 = ProgressionTestHelpers.makeIncompleteSession()
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [i1])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertEqual(plan.completedWeeks, 0)
    }

    func testCompletedWeeksWithEmptySessionsWeek() {
        // Week with no sessions: allSessionsCompleted returns false
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])

        XCTAssertEqual(plan.completedWeeks, 0)
    }

    // MARK: - projectedDateRange

    func testProjectedDateRangeForWeek1StartsOnPlanStartDate() {
        let startDate = Date()
        let plan = ProgressionTestHelpers.makeTestPlan(startDate: startDate)

        let range = plan.projectedDateRange(forAbsoluteWeek: 1)
        // Week 1: daysOffset = 0 * averageDaysPerWeek = 0
        let expectedStart = Calendar.current.date(byAdding: .day, value: 0, to: startDate)!
        XCTAssertEqual(
            Calendar.current.dateComponents([.year, .month, .day], from: range.start),
            Calendar.current.dateComponents([.year, .month, .day], from: expectedStart)
        )
    }

    func testProjectedDateRangeForWeek2OffsetsCorrectly() {
        let startDate = Date()
        // No completed weeks, so averageDaysPerWeek defaults to 7.0
        let plan = ProgressionTestHelpers.makeTestPlan(startDate: startDate)

        let range = plan.projectedDateRange(forAbsoluteWeek: 2)
        // Week 2: daysOffset = 1 * 7.0 = 7
        let expectedStart = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        XCTAssertEqual(
            Calendar.current.dateComponents([.year, .month, .day], from: range.start),
            Calendar.current.dateComponents([.year, .month, .day], from: expectedStart)
        )
    }

    func testProjectedDateRangeEndIsDaysPerWeekMinusOneAfterStart() {
        let startDate = Date()
        let plan = ProgressionTestHelpers.makeTestPlan(startDate: startDate)

        let range = plan.projectedDateRange(forAbsoluteWeek: 1)
        // Default averageDaysPerWeek = 7.0 => end = start + 6 days
        let expectedEnd = Calendar.current.date(byAdding: .day, value: 6, to: range.start)!
        XCTAssertEqual(
            Calendar.current.dateComponents([.year, .month, .day], from: range.end),
            Calendar.current.dateComponents([.year, .month, .day], from: expectedEnd)
        )
    }
}

// MARK: - PlanExercise Tests

final class PlanExerciseTests: XCTestCase {

    func testTargetWeightRoundsToNearest2Point5() {
        // 100 * 0.80 = 80.0, already on 2.5 boundary
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(current1RM: 100.0)
        XCTAssertEqual(exercise.targetWeight(atPercentage: 0.80), 80.0)
    }

    func testTargetWeightAt50Percent() {
        // 100 * 0.50 = 50.0
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(current1RM: 100.0)
        XCTAssertEqual(exercise.targetWeight(atPercentage: 0.50), 50.0)
    }

    func testTargetWeightAt75Percent() {
        // 100 * 0.75 = 75.0
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(current1RM: 100.0)
        XCTAssertEqual(exercise.targetWeight(atPercentage: 0.75), 75.0)
    }

    func testTargetWeightAt100Percent() {
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(current1RM: 100.0)
        XCTAssertEqual(exercise.targetWeight(atPercentage: 1.0), 100.0)
    }

    func testTargetWeightRoundsUpCorrectly() {
        // 90 * 0.80 = 72.0 -> rounds to 72.5
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(current1RM: 90.0)
        XCTAssertEqual(exercise.targetWeight(atPercentage: 0.80), 72.5)
    }

    func testTargetWeightRoundsDownCorrectly() {
        // 90 * 0.70 = 63.0 -> rounds to 62.5 (63/2.5 = 25.2, rounds to 25 * 2.5 = 62.5)
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(current1RM: 90.0)
        XCTAssertEqual(exercise.targetWeight(atPercentage: 0.70), 62.5)
    }

    func testTargetWeightNonTrivialRounding() {
        // 113 * 0.85 = 96.05 -> 96.05/2.5 = 38.42 -> rounds to 38 -> 38*2.5 = 95.0
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(current1RM: 113.0)
        XCTAssertEqual(exercise.targetWeight(atPercentage: 0.85), 95.0)
    }
}

// MARK: - TrainingBlock Tests

final class TrainingBlockTests: XCTestCase {

    func testCurrentWeekReturnsFirstIncomplete() {
        let c = ProgressionTestHelpers.makeCompletedSession()
        let i = ProgressionTestHelpers.makeIncompleteSession()
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [i])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])

        XCTAssertEqual(block.currentWeek?.weekNumber, 2)
    }

    func testCurrentWeekReturnsNilWhenAllCompleted() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "S1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "S2")
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c1])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [c2])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])

        XCTAssertNil(block.currentWeek)
    }

    func testProgressWithMixedCompletion() {
        let c = ProgressionTestHelpers.makeCompletedSession()
        let i = ProgressionTestHelpers.makeIncompleteSession()
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [i])
        let week3 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 3, sessions: [i])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2, week3])

        // 1 out of 3 weeks completed
        XCTAssertEqual(block.progress, 1.0 / 3.0, accuracy: 0.001)
    }

    func testProgressWithAllCompleted() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "S1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "S2")
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c1])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [c2])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])

        XCTAssertEqual(block.progress, 1.0, accuracy: 0.001)
    }

    func testProgressWithEmptyWeeksIsZero() {
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [])
        XCTAssertEqual(block.progress, 0)
    }

    func testAllWeeksCompletedWithEmptyWeeksReturnsFalse() {
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [])
        XCTAssertFalse(block.allWeeksCompleted)
    }

    func testAllWeeksCompletedWhenAllDone() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "S1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "S2")
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c1])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [c2])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])

        XCTAssertTrue(block.allWeeksCompleted)
    }

    func testAllWeeksCompletedWhenSomeIncomplete() {
        let c = ProgressionTestHelpers.makeCompletedSession()
        let i = ProgressionTestHelpers.makeIncompleteSession()
        let week1 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 1, sessions: [c])
        let week2 = ProgressionTestHelpers.makeTestTrainingWeek(weekNumber: 2, sessions: [i])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week1, week2])

        XCTAssertFalse(block.allWeeksCompleted)
    }
}

// MARK: - TrainingWeek Tests

final class TrainingWeekTests: XCTestCase {

    func testCompletedSessionsCountsOnlyWithCompletedWorkoutId() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "Done1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "Done2")
        let i1 = ProgressionTestHelpers.makeIncompleteSession(label: "NotDone")
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [c1, c2, i1])

        XCTAssertEqual(week.completedSessions, 2)
    }

    func testCompletedSessionsWithNoCompleted() {
        let i1 = ProgressionTestHelpers.makeIncompleteSession(label: "I1")
        let i2 = ProgressionTestHelpers.makeIncompleteSession(label: "I2")
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [i1, i2])

        XCTAssertEqual(week.completedSessions, 0)
    }

    func testCompletedSessionsWithEmptySessions() {
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [])
        XCTAssertEqual(week.completedSessions, 0)
    }

    func testAllSessionsCompletedWithEmptySessionsReturnsFalse() {
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [])
        XCTAssertFalse(week.allSessionsCompleted)
    }

    func testAllSessionsCompletedWhenAllDone() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "S1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "S2")
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [c1, c2])

        XCTAssertTrue(week.allSessionsCompleted)
    }

    func testAllSessionsCompletedWhenPartiallyDone() {
        let c = ProgressionTestHelpers.makeCompletedSession()
        let i = ProgressionTestHelpers.makeIncompleteSession()
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [c, i])

        XCTAssertFalse(week.allSessionsCompleted)
    }

    func testAdherenceRateWithPartialCompletion() {
        let c = ProgressionTestHelpers.makeCompletedSession()
        let i1 = ProgressionTestHelpers.makeIncompleteSession(label: "I1")
        let i2 = ProgressionTestHelpers.makeIncompleteSession(label: "I2")
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [c, i1, i2])

        // 1 out of 3
        XCTAssertEqual(week.adherenceRate, 1.0 / 3.0, accuracy: 0.001)
    }

    func testAdherenceRateFullCompletion() {
        let c1 = ProgressionTestHelpers.makeCompletedSession(label: "S1")
        let c2 = ProgressionTestHelpers.makeCompletedSession(label: "S2")
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [c1, c2])

        XCTAssertEqual(week.adherenceRate, 1.0, accuracy: 0.001)
    }

    func testAdherenceRateWithEmptySessions() {
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [])
        XCTAssertEqual(week.adherenceRate, 0)
    }
}

// MARK: - PlannedSession Tests

final class PlannedSessionTests: XCTestCase {

    func testIsCompletedWhenCompletedWorkoutIdPresent() {
        let session = ProgressionTestHelpers.makeCompletedSession()
        XCTAssertTrue(session.isCompleted)
    }

    func testIsCompletedWhenCompletedWorkoutIdNil() {
        let session = ProgressionTestHelpers.makeIncompleteSession()
        XCTAssertFalse(session.isCompleted)
    }

    func testEffectiveDatePrefersCompletedAtOverScheduledDate() {
        let scheduledDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let completedAt = Date()

        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: UUID(),
            completedAt: completedAt,
            scheduledDate: scheduledDate
        )

        XCTAssertEqual(session.effectiveDate, completedAt)
    }

    func testEffectiveDateFallsBackToScheduledDateWhenNotCompleted() {
        let scheduledDate = Date()
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: nil,
            completedAt: nil,
            scheduledDate: scheduledDate
        )

        XCTAssertEqual(session.effectiveDate, scheduledDate)
    }

    func testEffectiveDateIsNilWhenBothNil() {
        let session = ProgressionTestHelpers.makeTestPlannedSession(
            completedWorkoutId: nil,
            completedAt: nil,
            scheduledDate: nil
        )

        XCTAssertNil(session.effectiveDate)
    }
}

// MARK: - APRE Adjusted Weight Tests

final class APREAdjustedWeightTests: XCTestCase {

    // MARK: - 3RM Protocol

    func testAPRE3RM_0Reps_Decreases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 0, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        // 100 * 0.95 = 95.0
        XCTAssertEqual(result, 95.0)
    }

    func testAPRE3RM_1Rep_Decreases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 1, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 95.0)
    }

    func testAPRE3RM_2Reps_NoChange() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 2, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }

    func testAPRE3RM_3Reps_NoChange() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 3, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }

    func testAPRE3RM_4Reps_Increases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 4, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        // 100 * 1.025 = 102.5
        XCTAssertEqual(result, 102.5)
    }

    func testAPRE3RM_5Reps_Increases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 5, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 102.5)
    }

    func testAPRE3RM_6Reps_Increases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 6, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        // 100 * 1.05 = 105.0
        XCTAssertEqual(result, 105.0)
    }

    func testAPRE3RM_10Reps_Increases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 10, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 105.0)
    }

    // MARK: - 6RM Protocol

    func testAPRE6RM_1Rep_Decreases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 1, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 95.0)
    }

    func testAPRE6RM_3Reps_Decreases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 3, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 95.0)
    }

    func testAPRE6RM_4Reps_Decreases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 4, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        // 100 * 0.975 = 97.5
        XCTAssertEqual(result, 97.5)
    }

    func testAPRE6RM_5Reps_Decreases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 5, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 97.5)
    }

    func testAPRE6RM_6Reps_NoChange() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 6, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }

    func testAPRE6RM_7Reps_NoChange() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 7, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }

    func testAPRE6RM_8Reps_Increases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 8, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 102.5)
    }

    func testAPRE6RM_9Reps_Increases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 9, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 102.5)
    }

    func testAPRE6RM_10Reps_Increases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 10, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 105.0)
    }

    func testAPRE6RM_15Reps_Increases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 15, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 105.0)
    }

    // MARK: - 10RM Protocol

    func testAPRE10RM_4Reps_Decreases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 4, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 95.0)
    }

    func testAPRE10RM_6Reps_Decreases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 6, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 95.0)
    }

    func testAPRE10RM_7Reps_Decreases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 7, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 97.5)
    }

    func testAPRE10RM_8Reps_Decreases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 8, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 97.5)
    }

    func testAPRE10RM_9Reps_NoChange() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 9, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }

    func testAPRE10RM_10Reps_NoChange() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 10, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }

    func testAPRE10RM_11Reps_NoChange() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 11, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }

    func testAPRE10RM_12Reps_Increases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 12, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 102.5)
    }

    func testAPRE10RM_14Reps_Increases2Point5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 14, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 102.5)
    }

    func testAPRE10RM_15Reps_Increases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 15, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 105.0)
    }

    func testAPRE10RM_20Reps_Increases5Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 10)
        let result = set.apreAdjustedWeight(actualReps: 20, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 105.0)
    }

    // MARK: - Rounding Behavior

    func testAPRERoundingCompoundExerciseRoundsTo2Point5() {
        // Compound, heavy weight (>= 40): rounds to 2.5
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 8, workingWeight: 80.0, isCompound: true, isLowerBody: false)
        // 80 * 1.025 = 82.0 -> round to nearest 2.5 -> 82.5
        XCTAssertEqual(result, 82.5)
    }

    func testAPRERoundingIsolationExerciseRoundsTo1() {
        // Not compound: always rounds to 1.0
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 8, workingWeight: 50.0, isCompound: false, isLowerBody: false)
        // 50 * 1.025 = 51.25 -> round to nearest 1.0 -> 51.0
        XCTAssertEqual(result, 51.0)
    }

    func testAPRERoundingLightCompoundWeightRoundsTo1() {
        // Compound but rawAdjusted < 40: rounds to 1.0
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 6, workingWeight: 30.0, isCompound: true, isLowerBody: false)
        // 30 * 1.0 = 30.0 -> rawAdjusted < 40, rounds to 1.0 -> 30.0
        XCTAssertEqual(result, 30.0)
    }

    // MARK: - Weight Never Goes Below Zero

    func testAPREWeightNeverGoesBelowZero() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 0, workingWeight: 1.0, isCompound: false, isLowerBody: false)
        // 1.0 * 0.95 = 0.95 -> round to nearest 1.0 -> 1.0; max(0, 1.0) = 1.0
        XCTAssertGreaterThanOrEqual(result, 0)
    }

    func testAPREWeightAtZeroStaysZero() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 3)
        let result = set.apreAdjustedWeight(actualReps: 0, workingWeight: 0.0, isCompound: false, isLowerBody: false)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Default Case (non-standard target reps)

    func testAPREDefaultCaseClampedToPlus10Percent() {
        // Target reps = 8 is not 3, 6, or 10, so falls to default case
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 8)
        // actualReps = 20, deviation = (20-8)/8 = 1.5, clamped to 0.10
        let result = set.apreAdjustedWeight(actualReps: 20, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        // 100 * 1.10 = 110.0
        XCTAssertEqual(result, 110.0)
    }

    func testAPREDefaultCaseClampedToMinus10Percent() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 8)
        // actualReps = 0, deviation = (0-8)/8 = -1.0, clamped to -0.10
        let result = set.apreAdjustedWeight(actualReps: 0, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        // 100 * 0.90 = 90.0
        XCTAssertEqual(result, 90.0)
    }

    func testAPREDefaultCaseSmallDeviation() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 8)
        // actualReps = 9, deviation = (9-8)/8 = 0.125, clamped to 0.10
        let result = set.apreAdjustedWeight(actualReps: 9, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        // 100 * 1.10 = 110.0 (clamped at 10%)
        // Wait: 0.125 > 0.10, so clamped to 0.10 => 110.0
        XCTAssertEqual(result, 110.0)
    }

    func testAPREDefaultCaseExactMatch() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 8)
        // actualReps = 8, deviation = 0
        let result = set.apreAdjustedWeight(actualReps: 8, workingWeight: 100.0, isCompound: true, isLowerBody: false)
        XCTAssertEqual(result, 100.0)
    }
}

// MARK: - Double Rounding Extension Tests

final class DoubleRoundingTests: XCTestCase {

    func testRoundedToNearest2Point5_Up() {
        XCTAssertEqual(102.3.rounded(toNearest: 2.5), 102.5)
    }

    func testRoundedToNearest2Point5_Down() {
        XCTAssertEqual(101.1.rounded(toNearest: 2.5), 100.0)
    }

    func testRoundedToNearest1Point0() {
        XCTAssertEqual(50.5.rounded(toNearest: 1.0), 51.0, accuracy: 0.001)
    }

    func testRoundedToNearest2Point5_ExactBoundary() {
        XCTAssertEqual(100.0.rounded(toNearest: 2.5), 100.0)
    }

    func testRoundedToNearest2Point5_Midpoint() {
        // 101.25 / 2.5 = 40.5 -> Swift .rounded() uses .toNearestOrAwayFromZero
        // 40.5 rounds to 41 (away from zero). 41 * 2.5 = 102.5
        XCTAssertEqual(101.25.rounded(toNearest: 2.5), 102.5)
    }

    func testRoundedToZeroIncrementReturnsSelf() {
        XCTAssertEqual(42.7.rounded(toNearest: 0), 42.7)
    }

    func testRoundedToNegativeIncrementReturnsSelf() {
        XCTAssertEqual(42.7.rounded(toNearest: -1.0), 42.7)
    }

    func testRoundedToNearest5() {
        XCTAssertEqual(103.0.rounded(toNearest: 5.0), 105.0)
    }

    func testRoundedToNearest0Point5() {
        XCTAssertEqual(10.3.rounded(toNearest: 0.5), 10.5)
    }
}

// MARK: - PlanAdjustment Tests

final class PlanAdjustmentTests: XCTestCase {

    func testPlanAdjustmentCreation() {
        let id = UUID()
        let exerciseId = UUID()
        let blockId = UUID()
        let now = Date()

        let adjustment = PlanAdjustment(
            id: id,
            adjustmentType: .deload,
            trigger: .scheduledDeload,
            description: "Scheduled deload week",
            affectedExerciseIds: [exerciseId],
            affectedBlockIds: [blockId],
            previousValues: ["volume": "4x8"],
            newValues: ["volume": "2x8"],
            appliedAt: now,
            wasAccepted: true,
            coachingExplanation: "Time for a recovery week."
        )

        XCTAssertEqual(adjustment.id, id)
        XCTAssertEqual(adjustment.adjustmentType, .deload)
        XCTAssertEqual(adjustment.trigger, .scheduledDeload)
        XCTAssertEqual(adjustment.description, "Scheduled deload week")
        XCTAssertEqual(adjustment.affectedExerciseIds, [exerciseId])
        XCTAssertEqual(adjustment.affectedBlockIds, [blockId])
        XCTAssertEqual(adjustment.previousValues["volume"], "4x8")
        XCTAssertEqual(adjustment.newValues["volume"], "2x8")
        XCTAssertEqual(adjustment.appliedAt, now)
        XCTAssertEqual(adjustment.wasAccepted, true)
        XCTAssertEqual(adjustment.coachingExplanation, "Time for a recovery week.")
    }

    func testPlanAdjustmentDefaults() {
        let adjustment = PlanAdjustment(
            adjustmentType: .loadIncrease,
            trigger: .apre,
            description: "APRE load increase"
        )

        XCTAssertTrue(adjustment.affectedExerciseIds.isEmpty)
        XCTAssertTrue(adjustment.affectedBlockIds.isEmpty)
        XCTAssertTrue(adjustment.previousValues.isEmpty)
        XCTAssertTrue(adjustment.newValues.isEmpty)
        XCTAssertNil(adjustment.wasAccepted)
        XCTAssertNil(adjustment.coachingExplanation)
    }
}

// MARK: - PlanProgress / Sub-model Tests

final class PlanProgressTests: XCTestCase {

    func testPlanProgressCreationDefaults() {
        let planId = UUID()
        let progress = PlanProgress(planId: planId)

        XCTAssertEqual(progress.planId, planId)
        XCTAssertEqual(progress.overallAdherence, 0)
        XCTAssertTrue(progress.exerciseProgress.isEmpty)
        XCTAssertTrue(progress.blockProgress.isEmpty)
        XCTAssertNil(progress.estimatedCompletionDate)
        XCTAssertTrue(progress.isOnTrack)
        XCTAssertTrue(progress.weeklyVolumeHistory.isEmpty)
        XCTAssertEqual(progress.deloadCount, 0)
        XCTAssertEqual(progress.adjustmentCount, 0)
    }

    func testExerciseProgressCreation() {
        let ep = ExerciseProgress(
            planExerciseId: UUID(),
            exerciseName: "Squat",
            starting1RM: 100.0,
            current1RM: 110.0,
            target1RM: 120.0,
            progressPercentage: 0.5,
            totalSetsCompleted: 24,
            totalRepsCompleted: 120,
            totalVolumeLifted: 12000.0,
            personalRecordsHit: 2
        )

        XCTAssertEqual(ep.exerciseName, "Squat")
        XCTAssertEqual(ep.starting1RM, 100.0)
        XCTAssertEqual(ep.current1RM, 110.0)
        XCTAssertEqual(ep.target1RM, 120.0)
        XCTAssertEqual(ep.progressPercentage, 0.5)
        XCTAssertEqual(ep.totalSetsCompleted, 24)
        XCTAssertEqual(ep.personalRecordsHit, 2)
    }

    func testBlockProgressCreation() {
        let blockId = UUID()
        let bp = BlockProgress(
            blockId: blockId,
            blockName: "Accumulation",
            weeklyAdherence: [1.0, 0.75, 0.5],
            averageRPE: 7.5,
            volumeTrend: 1.05
        )

        XCTAssertEqual(bp.blockId, blockId)
        XCTAssertEqual(bp.blockName, "Accumulation")
        XCTAssertEqual(bp.weeklyAdherence.count, 3)
        XCTAssertEqual(bp.averageRPE, 7.5)
        XCTAssertEqual(bp.volumeTrend, 1.05)
    }

    func testWeeklyVolumeCreation() {
        let wv = WeeklyVolume(
            weekNumber: 3,
            totalVolume: 15000.0,
            averageIntensity: 0.75,
            sessionCount: 4
        )

        XCTAssertEqual(wv.weekNumber, 3)
        XCTAssertEqual(wv.totalVolume, 15000.0)
        XCTAssertEqual(wv.averageIntensity, 0.75)
        XCTAssertEqual(wv.sessionCount, 4)
    }
}

// MARK: - OneRMSource Tests

final class OneRMSourceTests: XCTestCase {

    func testAllOneRMSourceCasesRawValues() {
        XCTAssertEqual(PlanExercise.OneRMSource.tested.rawValue, "tested")
        XCTAssertEqual(PlanExercise.OneRMSource.estimated.rawValue, "estimated")
        XCTAssertEqual(PlanExercise.OneRMSource.userInput.rawValue, "userInput")
        XCTAssertEqual(PlanExercise.OneRMSource.personalRecord.rawValue, "personalRecord")
        XCTAssertEqual(PlanExercise.OneRMSource.naturalLanguage.rawValue, "naturalLanguage")
    }
}

// MARK: - Enum Raw Values & CaseIterable Tests

final class ProgressionEnumRawValueTests: XCTestCase {

    func testTrainingStatusCaseIterable() {
        let allCases = TrainingStatus.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.beginner))
        XCTAssertTrue(allCases.contains(.intermediate))
        XCTAssertTrue(allCases.contains(.advanced))
    }

    func testProgramTypeCaseIterable() {
        let allCases = ProgramType.allCases
        XCTAssertEqual(allCases.count, 4)
    }

    func testTrainingGoalCaseIterable() {
        let allCases = TrainingGoal.allCases
        XCTAssertEqual(allCases.count, 5)
    }

    func testBlockPhaseCaseIterable() {
        let allCases = BlockPhase.allCases
        XCTAssertEqual(allCases.count, 4)
    }

    func testDUPSessionTypeCaseIterable() {
        let allCases = DUPSessionType.allCases
        XCTAssertEqual(allCases.count, 3)
    }

    func testPlanStatusRawValues() {
        XCTAssertEqual(PlanStatus.draft.rawValue, "draft")
        XCTAssertEqual(PlanStatus.active.rawValue, "active")
        XCTAssertEqual(PlanStatus.paused.rawValue, "paused")
        XCTAssertEqual(PlanStatus.completed.rawValue, "completed")
        XCTAssertEqual(PlanStatus.abandoned.rawValue, "abandoned")
    }

    func testAdjustmentTypeRawValues() {
        XCTAssertEqual(AdjustmentType.deload.rawValue, "deload")
        XCTAssertEqual(AdjustmentType.loadIncrease.rawValue, "loadIncrease")
        XCTAssertEqual(AdjustmentType.loadDecrease.rawValue, "loadDecrease")
        XCTAssertEqual(AdjustmentType.exerciseSwap.rawValue, "exerciseSwap")
        XCTAssertEqual(AdjustmentType.volumeAdjustment.rawValue, "volumeAdjustment")
        XCTAssertEqual(AdjustmentType.frequencyChange.rawValue, "frequencyChange")
        XCTAssertEqual(AdjustmentType.blockExtension.rawValue, "blockExtension")
        XCTAssertEqual(AdjustmentType.reforecast.rawValue, "reforecast")
    }

    func testDeloadTriggerRawValues() {
        XCTAssertEqual(DeloadTrigger.scheduledProgrammatic.rawValue, "scheduledProgrammatic")
        XCTAssertEqual(DeloadTrigger.reactivePerformance.rawValue, "reactivePerformance")
        XCTAssertEqual(DeloadTrigger.reactiveRecovery.rawValue, "reactiveRecovery")
        XCTAssertEqual(DeloadTrigger.reactivePlateau.rawValue, "reactivePlateau")
        XCTAssertEqual(DeloadTrigger.userRequested.rawValue, "userRequested")
        XCTAssertEqual(DeloadTrigger.subjectiveSignal.rawValue, "subjectiveSignal")
    }

    func testAdjustmentTriggerRawValues() {
        XCTAssertEqual(AdjustmentTrigger.apre.rawValue, "apre")
        XCTAssertEqual(AdjustmentTrigger.plateauDetected.rawValue, "plateauDetected")
        XCTAssertEqual(AdjustmentTrigger.performanceDecline.rawValue, "performanceDecline")
        XCTAssertEqual(AdjustmentTrigger.recoverySignal.rawValue, "recoverySignal")
        XCTAssertEqual(AdjustmentTrigger.userManual.rawValue, "userManual")
        XCTAssertEqual(AdjustmentTrigger.scheduledDeload.rawValue, "scheduledDeload")
        XCTAssertEqual(AdjustmentTrigger.oneRMUpdate.rawValue, "oneRMUpdate")
        XCTAssertEqual(AdjustmentTrigger.subjectiveSignal.rawValue, "subjectiveSignal")
    }
}

// MARK: - CoachingTone Tests

final class CoachingToneTests: XCTestCase {
    func testBeginnerCoachingTone() {
        let tone = TrainingStatus.beginner.coachingTone
        XCTAssertTrue(tone.contains("Encouraging"), "Beginner tone should be encouraging. Got: \(tone)")
    }

    func testIntermediateCoachingTone() {
        let tone = TrainingStatus.intermediate.coachingTone
        XCTAssertTrue(tone.contains("data-driven"), "Intermediate tone should be data-driven. Got: \(tone)")
    }

    func testAdvancedCoachingTone() {
        let tone = TrainingStatus.advanced.coachingTone
        XCTAssertTrue(tone.contains("technical"), "Advanced tone should be technical. Got: \(tone)")
    }
}

// MARK: - PlanCreationSource Tests

final class PlanCreationSourceTests: XCTestCase {
    func testStructuredFlowRawValue() {
        XCTAssertEqual(ProgressionPlan.PlanCreationSource.structuredFlow.rawValue, "structuredFlow")
    }

    func testNaturalLanguageRawValue() {
        XCTAssertEqual(ProgressionPlan.PlanCreationSource.naturalLanguage.rawValue, "naturalLanguage")
    }

    func testPlanCreationSourceCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let source = ProgressionPlan.PlanCreationSource.naturalLanguage
        let data = try encoder.encode(source)
        let decoded = try decoder.decode(ProgressionPlan.PlanCreationSource.self, from: data)
        XCTAssertEqual(decoded, source)
    }
}

// MARK: - APRE Lower-Body Rounding Tests

extension APREAdjustedWeightTests {
    func testAPRERoundingLowerBodyCompoundRoundsTo5() {
        // Lower-body compound, heavy weight (>= 40): rounds to 5.0
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 8, workingWeight: 100.0, isCompound: true, isLowerBody: true)
        // 100 * 1.025 = 102.5 -> round to nearest 5.0 -> 105.0
        XCTAssertEqual(result, 105.0)
    }

    func testAPRERoundingLowerBodyCompoundRoundsDown() {
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 6, workingWeight: 102.0, isCompound: true, isLowerBody: true)
        // 102 * 1.0 = 102.0 -> round to nearest 5.0 -> 100.0
        XCTAssertEqual(result, 100.0)
    }

    func testAPRERoundingLowerBodyLightWeightRoundsTo1() {
        // Lower-body compound but rawAdjusted < 40: still rounds to 1.0 (light weight override)
        let set = ProgressionTestHelpers.makeTestPlannedExerciseSet(targetReps: 6)
        let result = set.apreAdjustedWeight(actualReps: 6, workingWeight: 30.0, isCompound: true, isLowerBody: true)
        // 30 * 1.0 = 30.0 -> rawAdjusted < 40, rounds to 1.0 -> 30.0
        XCTAssertEqual(result, 30.0)
    }
}
