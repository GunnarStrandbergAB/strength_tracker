import XCTest
@testable import StrengthTrackerShared

@MainActor
final class ProgressionPersistenceTests: XCTestCase {

    private func makeRepository() -> InMemoryProgressionPlanRepository {
        InMemoryProgressionPlanRepository()
    }

    // MARK: - Save & Fetch All

    func testSave_andFetchAll_returnsPlan() async throws {
        let repository = makeRepository()
        let plan = ProgressionTestHelpers.makeTestPlan(name: "My Strength Plan")

        try await repository.save(plan)
        let all = try await repository.fetchAll()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "My Strength Plan")
        XCTAssertEqual(all.first?.id, plan.id)
    }

    func testSave_updatesExistingPlan() async throws {
        let repository = makeRepository()
        var plan = ProgressionTestHelpers.makeTestPlan(name: "Original")
        try await repository.save(plan)

        plan.name = "Updated"
        try await repository.save(plan)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 1, "Should upsert, not duplicate")
        XCTAssertEqual(all.first?.name, "Updated")
    }

    // MARK: - Fetch Active

    func testFetchActive_returnsOnlyActivePlan() async throws {
        let repository = makeRepository()
        let activePlan = ProgressionTestHelpers.makeTestPlan(
            name: "Active",
            status: .active
        )
        let draftPlan = ProgressionTestHelpers.makeTestPlan(
            name: "Draft",
            status: .draft
        )
        let completedPlan = ProgressionTestHelpers.makeTestPlan(
            name: "Completed",
            status: .completed
        )

        try await repository.save(activePlan)
        try await repository.save(draftPlan)
        try await repository.save(completedPlan)

        let active = try await repository.fetchActive()
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.name, "Active")
        XCTAssertEqual(active?.status, .active)
    }

    func testFetchActive_noActivePlan_returnsNil() async throws {
        let repository = makeRepository()
        let draftPlan = ProgressionTestHelpers.makeTestPlan(
            name: "Draft",
            status: .draft
        )
        try await repository.save(draftPlan)

        let active = try await repository.fetchActive()
        XCTAssertNil(active)
    }

    // MARK: - Fetch By ID

    func testFetchById_found() async throws {
        let repository = makeRepository()
        let plan = ProgressionTestHelpers.makeTestPlan(name: "Target Plan")
        try await repository.save(plan)

        let fetched = try await repository.fetch(id: plan.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, plan.id)
        XCTAssertEqual(fetched?.name, "Target Plan")
    }

    func testFetchById_notFound_returnsNil() async throws {
        let repository = makeRepository()
        let fetched = try await repository.fetch(id: UUID())
        XCTAssertNil(fetched)
    }

    // MARK: - Delete

    func testDelete_removesPlan() async throws {
        let repository = makeRepository()
        let plan = ProgressionTestHelpers.makeTestPlan()
        try await repository.save(plan)

        let beforeDelete = try await repository.fetchAll()
        XCTAssertEqual(beforeDelete.count, 1)

        try await repository.delete(plan)
        let afterDelete = try await repository.fetchAll()
        XCTAssertEqual(afterDelete.count, 0)
    }

    // MARK: - Update Status

    func testUpdateStatus_changesStatus() async throws {
        let repository = makeRepository()
        let plan = ProgressionTestHelpers.makeTestPlan(status: .draft)
        try await repository.save(plan)

        try await repository.updateStatus(plan.id, status: .active)

        let fetched = try await repository.fetch(id: plan.id)
        XCTAssertEqual(fetched?.status, .active)
    }

    // MARK: - Add Adjustment

    func testAddAdjustment_appendsToExistingPlan() async throws {
        let repository = makeRepository()
        let plan = ProgressionTestHelpers.makeTestPlan()
        try await repository.save(plan)

        let adjustment = PlanAdjustment(
            adjustmentType: .loadIncrease,
            trigger: .apre,
            description: "Increased bench press load by 2.5kg"
        )

        try await repository.addAdjustment(adjustment, toPlan: plan.id)

        let fetched = try await repository.fetch(id: plan.id)
        XCTAssertEqual(fetched?.adjustments.count, 1)
        XCTAssertEqual(fetched?.adjustments.first?.adjustmentType, .loadIncrease)
        XCTAssertEqual(fetched?.adjustments.first?.description, "Increased bench press load by 2.5kg")
    }

    // MARK: - Update Exercise

    func testUpdateExercise_modifiesExerciseInPlan() async throws {
        let repository = makeRepository()
        let exerciseId = UUID()
        var exercise = ProgressionTestHelpers.makeTestPlanExercise(
            id: exerciseId,
            name: "Bench Press",
            current1RM: 100.0
        )
        let plan = ProgressionTestHelpers.makeTestPlan(exercises: [exercise])
        try await repository.save(plan)

        exercise.current1RM = 105.0
        exercise.exerciseName = "Bench Press (Updated)"
        try await repository.updateExercise(exercise, inPlan: plan.id)

        let fetched = try await repository.fetch(id: plan.id)
        XCTAssertEqual(fetched?.exercises.count, 1)
        XCTAssertEqual(fetched?.exercises.first?.current1RM, 105.0)
        XCTAssertEqual(fetched?.exercises.first?.exerciseName, "Bench Press (Updated)")
    }

    // MARK: - Update Block

    func testUpdateBlock_modifiesBlockInPlan() async throws {
        let repository = makeRepository()
        let blockId = UUID()
        var block = ProgressionTestHelpers.makeTestTrainingBlock(
            id: blockId,
            name: "Block 1",
            durationWeeks: 4
        )
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])
        try await repository.save(plan)

        block.name = "Block 1 (Extended)"
        block.durationWeeks = 5
        try await repository.updateBlock(block, inPlan: plan.id)

        let fetched = try await repository.fetch(id: plan.id)
        XCTAssertEqual(fetched?.blocks.count, 1)
        XCTAssertEqual(fetched?.blocks.first?.name, "Block 1 (Extended)")
        XCTAssertEqual(fetched?.blocks.first?.durationWeeks, 5)
    }

    // MARK: - Mark Session Completed

    func testMarkSessionCompleted_setsWorkoutIdAndDate() async throws {
        let repository = makeRepository()
        let sessionId = UUID()
        let session = ProgressionTestHelpers.makeIncompleteSession(id: sessionId)
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [week])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block])
        try await repository.save(plan)

        let workoutId = UUID()
        try await repository.markSessionCompleted(sessionId, workoutId: workoutId, inPlan: plan.id)

        let fetched = try await repository.fetch(id: plan.id)
        let fetchedSession = fetched?.blocks.first?.weeks.first?.sessions.first
        XCTAssertNotNil(fetchedSession)
        XCTAssertEqual(fetchedSession?.completedWorkoutId, workoutId)
        XCTAssertNotNil(fetchedSession?.completedAt)
    }
}

// MARK: - Mapper Tests (SwiftData-only, won't run on Linux)

#if canImport(SwiftData)
import SwiftData

@MainActor
final class ProgressionPlanMapperTests: XCTestCase {

    func testRoundTrip_domainToEntityToDomain() throws {
        let exercise = ProgressionTestHelpers.makeTestPlanExercise(
            name: "Squat",
            current1RM: 140.0
        )
        let session = ProgressionTestHelpers.makeTestPlannedSession()
        let week = ProgressionTestHelpers.makeTestTrainingWeek(sessions: [session])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(
            name: "Accumulation",
            weeks: [week],
            blockPhase: .accumulation
        )
        let adjustment = PlanAdjustment(
            adjustmentType: .loadIncrease,
            trigger: .apre,
            description: "Bumped squat 2.5kg"
        )
        let original = ProgressionTestHelpers.makeTestPlan(
            name: "Round Trip Plan",
            blocks: [block],
            exercises: [exercise],
            status: .active,
            trainingStatus: .intermediate,
            programType: .dailyUndulating,
            primaryGoal: .hypertrophy,
            weeklyFrequency: 4,
            adjustments: [adjustment]
        )

        let entity = ProgressionPlanMapper.toEntity(original)
        let roundTripped = ProgressionPlanMapper.toDomain(entity)

        XCTAssertNotNil(roundTripped)
        XCTAssertEqual(roundTripped?.id, original.id)
        XCTAssertEqual(roundTripped?.name, original.name)
        XCTAssertEqual(roundTripped?.status, original.status)
        XCTAssertEqual(roundTripped?.trainingStatus, original.trainingStatus)
        XCTAssertEqual(roundTripped?.programType, original.programType)
        XCTAssertEqual(roundTripped?.primaryGoal, original.primaryGoal)
        XCTAssertEqual(roundTripped?.weeklyFrequency, original.weeklyFrequency)
        XCTAssertEqual(roundTripped?.exercises.count, 1)
        XCTAssertEqual(roundTripped?.exercises.first?.exerciseName, "Squat")
        XCTAssertEqual(roundTripped?.blocks.count, 1)
        XCTAssertEqual(roundTripped?.blocks.first?.name, "Accumulation")
        XCTAssertEqual(roundTripped?.adjustments.count, 1)
        XCTAssertEqual(roundTripped?.adjustments.first?.description, "Bumped squat 2.5kg")
    }

    func testTolerantDecoding_missingOptionalFields() throws {
        let plan = ProgressionTestHelpers.makeTestPlan(name: "Tolerant Test")
        let entity = ProgressionPlanMapper.toEntity(plan)

        // Simulate stored data with nil optional fields
        entity.adjustmentsJSON = Data("[]".utf8)
        entity.secondaryGoal = nil
        entity.creationSource = nil
        entity.notes = nil
        entity.targetEndDate = nil
        entity.actualEndDate = nil

        let decoded = ProgressionPlanMapper.toDomain(entity)
        XCTAssertNotNil(decoded, "Should decode successfully even with nil optional fields")
        XCTAssertEqual(decoded?.adjustments.count, 0)
        XCTAssertNil(decoded?.secondaryGoal)
        XCTAssertNil(decoded?.creationSource)
        XCTAssertNil(decoded?.notes)
    }
}
#endif
