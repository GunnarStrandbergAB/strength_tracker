#if canImport(UIKit)
import XCTest
import SwiftUI
@testable import StrengthTracker
@testable import StrengthTrackerShared

/// The plan wizard end to end: the draft it builds from the training log, the plan
/// that draft creates, and the four screens rendered with that data.
@MainActor
final class PlanWizardTests: XCTestCase {
    private struct Fixture {
        let viewModel: ProgressionPlanViewModel
        let exerciseList: ExerciseListViewModel
        let templates: TemplateViewModel
        let plans: InMemoryProgressionPlanRepository
        let bench: Exercise
        let squat: Exercise
        let plank: Exercise
        /// In the library, in no template.
        let row: Exercise
        let push: WorkoutTemplate
        let templateRepository: InMemoryTemplateRepository
    }

    private func exercise(_ name: String, muscle: MuscleGroup, type: ExerciseType = .weightedReps) -> Exercise {
        Exercise(id: UUID(), name: name, primaryMuscleGroup: muscle, secondaryMuscleGroups: [], category: type == .weightedReps ? .barbell : .bodyweight,
            exerciseType: type, instructions: nil, isCustom: false, isArchived: false)
    }

    private func workout(_ exercise: Exercise, weight: Double, reps: Int, daysAgo: Int) -> Workout {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let sets = (0..<3).map { order in
            ExerciseSet(id: UUID(), order: order, setType: .normal, weight: weight, reps: reps, durationSeconds: nil, distanceMeters: nil,
                rpe: nil, isCompleted: true, isPersonalRecord: false, completedAt: date)
        }
        return Workout(id: UUID(), name: "Push", startedAt: date.addingTimeInterval(-3600), completedAt: date, notes: nil, templateId: nil,
            exercises: [WorkoutExercise(id: UUID(), exercise: exercise, order: 0, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: sets)])
    }

    /// A log with ten weeks of bench rising half a kilo a week, a "Push" template
    /// (bench and a timed plank), and a squat that has never been logged.
    private func makeFixture() async throws -> Fixture {
        let bench = exercise("Bench Press", muscle: .chest)
        let squat = exercise("Back Squat", muscle: .quadriceps)
        let plank = exercise("Plank", muscle: .core, type: .duration)
        let row = exercise("Barbell Row", muscle: .back)
        let exercises = InMemoryExerciseRepository()
        for item in [bench, squat, plank, row] { _ = try await exercises.save(item) }

        let push = WorkoutTemplate(id: UUID(), name: "Push", notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0, exercises: [
            TemplateExercise(id: UUID(), exercise: bench, order: 0, supersetGroup: nil, notes: nil, restTimerSeconds: 120, targetSets: 3,
                targetReps: 8, targetWeight: 80, targetDurationSeconds: nil, targetDistanceMeters: nil),
            TemplateExercise(id: UUID(), exercise: plank, order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: 60, targetSets: 3,
                targetReps: nil, targetWeight: nil, targetDurationSeconds: 60, targetDistanceMeters: nil)
        ])
        let templateRepository = InMemoryTemplateRepository()
        _ = try await templateRepository.save(push)

        let workouts = MockWorkoutRepositoryProgression()
        workouts.workouts = (0..<10).map { week in workout(bench, weight: 80 - Double(week) * 0.5, reps: 8, daysAgo: 2 + week * 7) }
        let plans = InMemoryProgressionPlanRepository()
        let viewModel = ProgressionPlanViewModel(
            progressionPlanRepository: plans,
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: workouts),
            programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: workouts),
            exerciseRepository: exercises,
            templateRepository: templateRepository,
            workoutRepository: workouts)
        // Not loaded here: like in the app, nothing has opened the Templates tab yet.
        let templates = TemplateViewModel(templateRepository: templateRepository, exerciseRepository: exercises)
        return Fixture(viewModel: viewModel, exerciseList: ExerciseListViewModel(exerciseRepository: exercises), templates: templates,
            plans: plans, bench: bench, squat: squat, plank: plank, row: row, push: push, templateRepository: templateRepository)
    }

    /// Monday "Push" from the template, Thursday squat added by hand.
    private func fillWorkouts(_ fixture: Fixture) {
        let viewModel = fixture.viewModel
        viewModel.draftTrainingDays = [2, 5]
        viewModel.draftDurationWeeks = 8
        viewModel.setDraftWorkout(fixture.push, forDay: 2)
        viewModel.toggleDraftLift(fixture.squat, forDay: 5)
    }

    func testTemplateLiftsAreTickedAndUnusedLiftsLeaveThePlan() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        viewModel.draftTrainingDays = [2, 5]
        XCTAssertEqual(viewModel.draftEmptyDays, [2, 5])
        viewModel.setDraftWorkout(fixture.push, forDay: 2)
        // The timed plank is not a lift the plan can progress.
        XCTAssertEqual(viewModel.draftSelectedExercises.map(\.exercise.name), ["Bench Press"])
        XCTAssertEqual(viewModel.draftEmptyDays, [5])
        viewModel.toggleDraftLift(fixture.squat, forDay: 5)
        XCTAssertTrue(viewModel.draftEmptyDays.isEmpty)
        viewModel.toggleDraftLift(fixture.squat, forDay: 5)
        XCTAssertEqual(viewModel.draftSelectedExercises.map(\.exercise.name), ["Bench Press"])
        viewModel.setDraftWorkout(nil, forDay: 2)
        XCTAssertTrue(viewModel.draftSelectedExercises.isEmpty)
    }

    func testProgressionDraftStartsFromTheLogAndFollowsThePace() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        fillWorkouts(fixture)
        await viewModel.prepareProgressionDraft()

        // Half a kilo a week on an 80 kg bench is about 0.6% a week: the standard pace.
        let recommendation = try XCTUnwrap(viewModel.draftPaceRecommendation)
        XCTAssertEqual(recommendation.pace, .standard)
        XCTAssertEqual(recommendation.liftCount, 1)
        XCTAssertEqual(viewModel.draftPace, .standard)

        let bench = try XCTUnwrap(viewModel.draftSelectedExercises.first { $0.id == fixture.bench.id }?.rule)
        XCTAssertEqual(bench.kind, .repsThenWeight)
        XCTAssertEqual(bench.startWeightKg, 80)
        XCTAssertEqual(bench.startReps, 8)
        // The squat has no history, so the wizard cannot continue until it has a start.
        XCTAssertFalse(viewModel.draftProgressionIsComplete)
        viewModel.setDraftStart(weightKg: 100, for: fixture.squat.id)
        XCTAssertTrue(viewModel.draftProgressionIsComplete)

        // A hand-made rule survives a pace change; the others follow it and keep their start.
        var custom = bench
        custom.maxReps = 12
        viewModel.setDraftRule(custom, for: fixture.bench.id)
        viewModel.applyDraftPace(.aggressive)
        XCTAssertEqual(viewModel.draftSelectedExercises.first { $0.id == fixture.bench.id }?.rule?.maxReps, 12)
        let squat = try XCTUnwrap(viewModel.draftSelectedExercises.first { $0.id == fixture.squat.id }?.rule)
        XCTAssertEqual(squat.kind, .fixedSteps)
        XCTAssertEqual(squat.startWeightKg, 100)
    }

    func testPreviewMatchesTheSavedPlan() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        fillWorkouts(fixture)
        await viewModel.prepareProgressionDraft()
        viewModel.setDraftStart(weightKg: 100, for: fixture.squat.id)
        viewModel.draftDeloadEveryWeeks = 4
        viewModel.draftPlanName = "Winter"

        let previewed = await viewModel.draftPreviewPlan()
        let preview = try XCTUnwrap(previewed)
        XCTAssertTrue(fixture.plans.plans.isEmpty, "A preview saves nothing")
        await viewModel.generateAndSavePlan()
        XCTAssertNil(viewModel.errorMessage)
        let saved = try XCTUnwrap(fixture.plans.plans.first)

        func targets(_ plan: ProgressionPlan) -> [[String]] {
            plan.blocks.flatMap(\.weeks).flatMap(\.sessions).sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
                .map { $0.plannedExercises.map { "\($0.exerciseName) \($0.sets)x\($0.targetReps)@\($0.targetWeight)" } }
        }
        XCTAssertEqual(targets(preview), targets(saved))
        XCTAssertEqual(saved.name, "Winter")
        XCTAssertEqual(saved.configuration?.pace, .standard)
        XCTAssertEqual(saved.configuration?.deloadEveryWeeks, 4)
        XCTAssertEqual(targets(saved).count, 16)
        // Monday is bench from the template, Thursday the squat; each on its own ladder.
        XCTAssertEqual(targets(saved).prefix(4).map(\.first), ["Bench Press 3x8@80.0", "Back Squat 3x6@100.0", "Bench Press 3x9@80.0", "Back Squat 3x7@100.0"])
        XCTAssertEqual(saved.blocks.flatMap(\.weeks).flatMap(\.sessions).filter(\.isDeload).count, 4)
    }

    func testDeloadWeeksFollowTheChosenCadenceAndDays() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        fillWorkouts(fixture)
        viewModel.draftDurationWeeks = 10
        await viewModel.prepareProgressionDraft()
        viewModel.setDraftStart(weightKg: 100, for: fixture.squat.id)
        XCTAssertEqual(viewModel.draftDeloadEveryWeeks, 5, "A new plan starts with a deload every fifth week")
        viewModel.draftUseCustomDeloadDays = true
        viewModel.applyDefaultDeloadDays()
        XCTAssertEqual(viewModel.draftDeloadDays, [2, 5], "Both training days until one is left out")
        viewModel.toggleDeloadDay(5)
        viewModel.toggleDeloadDay(2)
        XCTAssertEqual(viewModel.draftDeloadDays, [2], "A deload week keeps at least one session")

        await viewModel.generateAndSavePlan()
        XCTAssertNil(viewModel.errorMessage)
        let plan = try XCTUnwrap(fixture.plans.plans.first)
        let weeks = plan.blocks.flatMap(\.weeks).sorted { $0.absoluteWeekNumber < $1.absoluteWeekNumber }
        XCTAssertEqual(weeks.count, 10)
        XCTAssertEqual(weeks.filter(\.isDeload).map(\.absoluteWeekNumber), [5, 10])
        for week in weeks {
            let days = week.sessions.compactMap(\.dayOfWeek).sorted()
            XCTAssertEqual(days, week.isDeload ? [2] : [2, 5], "Week \(week.absoluteWeekNumber)")
        }
        // The Thursday squat has no session in a deload week and carries on from where it was.
        let squats = ordered(plan).compactMap { $0.plannedExercises.first { $0.exerciseId == fixture.squat.id }?.targetReps }
        XCTAssertEqual(squats.count, 8)
        XCTAssertEqual(Array(squats.prefix(6)), [6, 7, 8, 9, 10, 6], "Week 4 asks for 9 reps, week 6 for 10")
    }

    // MARK: - The plan owns its exercises

    private func names(_ session: PlannedSession) -> [String] { session.plannedExercises.map(\.exerciseName) }

    func testADayIsBuiltFromExercisesAndATemplateOnlyFillsItIn() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        viewModel.draftTrainingDays = [2, 5]
        viewModel.setDraftWorkout(fixture.push, forDay: 2)
        func monday() -> [TemplateExercise] { viewModel.draftDaySchedule[2]?.exercises ?? [] }
        XCTAssertEqual(monday().map(\.exercise.name), ["Bench Press", "Plank"], "The whole template, not only its lifts")
        XCTAssertTrue(Set(monday().map(\.id)).isDisjoint(with: fixture.push.exercises.map(\.id)), "The day holds copies")

        // Any exercise can be added: a lift starts ticked, a timed one keeps its own target.
        viewModel.addDraftExercise(fixture.row, forDay: 2)
        viewModel.addDraftExercise(fixture.row, forDay: 2)
        XCTAssertEqual(monday().map(\.exercise.name), ["Bench Press", "Plank", "Barbell Row"])
        XCTAssertEqual(viewModel.draftDaySchedule[2]?.exerciseIds, [fixture.bench.id, fixture.row.id])
        viewModel.addDraftExercise(fixture.plank, forDay: 5)
        XCTAssertTrue(viewModel.draftEmptyDays.isEmpty)
        XCTAssertEqual(viewModel.draftSelectedExercises.map(\.exercise.name), ["Bench Press", "Barbell Row"])

        // Reorder, retarget and remove.
        viewModel.moveDraftExercise(monday()[2].id, by: -2, forDay: 2)
        XCTAssertEqual(monday().map(\.exercise.name), ["Barbell Row", "Bench Press", "Plank"])
        XCTAssertEqual(monday().map(\.order), [0, 1, 2])
        viewModel.updateDraftExercise(monday()[2].id, forDay: 2) { $0.targetSets = 2; $0.targetDurationSeconds = 90 }
        XCTAssertEqual(monday()[2].targetDurationSeconds, 90)
        viewModel.removeDraftExercise(monday()[0].id, forDay: 2)
        XCTAssertEqual(monday().map(\.exercise.name), ["Bench Press", "Plank"])
        XCTAssertEqual(viewModel.draftSelectedExercises.map(\.exercise.name), ["Bench Press"], "A removed lift leaves the plan")

        // An unticked lift stays in the workout with the template's own target.
        viewModel.toggleDraftLift(fixture.bench, forDay: 2)
        XCTAssertEqual(monday().map(\.exercise.name), ["Bench Press", "Plank"])
        XCTAssertTrue(viewModel.draftSelectedExercises.isEmpty)
        viewModel.toggleDraftLift(fixture.squat, forDay: 5)
        await viewModel.prepareProgressionDraft()
        viewModel.setDraftStart(weightKg: 100, for: fixture.squat.id)
        await viewModel.generateAndSavePlan()
        XCTAssertNil(viewModel.errorMessage)
        let first = try XCTUnwrap(ordered(viewModel.activePlan).first { $0.dayOfWeek == 2 })
        let started = await viewModel.prepareSessionTemplate(for: first)
        let workout = try XCTUnwrap(started)
        XCTAssertEqual(workout.exercises.map { "\($0.exercise.name) \($0.targetSets)x\($0.targetReps ?? 0) \($0.targetWeight ?? 0) \($0.targetDurationSeconds ?? 0)s" },
            ["Bench Press 3x8 80.0 0s", "Plank 2x0 0.0 90s"])
    }

    func testAStartedPlanNoLongerFollowsItsTemplate() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        fillWorkouts(fixture)
        viewModel.draftDeloadEveryWeeks = 4
        await viewModel.prepareProgressionDraft()
        viewModel.setDraftStart(weightKg: 100, for: fixture.squat.id)
        await viewModel.generateAndSavePlan()
        XCTAssertNil(viewModel.errorMessage)
        let sessions = ordered(viewModel.activePlan)
        XCTAssertTrue(sessions.allSatisfy { $0.templateId == nil && $0.exerciseSnapshot != nil }, "Every session has its own copy and no link")
        XCTAssertEqual(viewModel.activePlan?.daySchedule.compactMap(\.templateId), [])
        let mondays = sessions.filter { $0.dayOfWeek == 2 }
        XCTAssertEqual(Set(mondays.map(\.displayLabel)), ["Push"], "The workout keeps the template's name")
        XCTAssertTrue(mondays.allSatisfy { names($0) == ["Bench Press", "Plank"] })
        XCTAssertEqual(sessions.first { $0.dayOfWeek == 5 }.map(names), ["Back Squat"])

        // The template changes and is then deleted; the plan's workouts stay as they were.
        var changed = fixture.push
        changed.exercises = [TemplateExercise(id: UUID(), exercise: fixture.row, order: 0, supersetGroup: nil, notes: nil, restTimerSeconds: 90,
            targetSets: 4, targetReps: 10, targetWeight: 50, targetDurationSeconds: nil, targetDistanceMeters: nil)]
        _ = try await fixture.templateRepository.save(changed)
        let afterChange = await viewModel.prepareSessionTemplate(for: mondays[0])
        XCTAssertEqual(afterChange?.exercises.map(\.exercise.name), ["Bench Press", "Plank"])
        try await fixture.templateRepository.delete(fixture.push)
        let afterDelete = await viewModel.prepareSessionTemplate(for: mondays[1])
        XCTAssertEqual(afterDelete?.exercises.map(\.exercise.name), ["Bench Press", "Plank"])
        XCTAssertEqual(afterDelete?.exercises.last?.targetDurationSeconds, 60)

        // A deload Monday is the same workout at half the weight.
        let deload = try XCTUnwrap(mondays.first(where: \.isDeload))
        let normal = try XCTUnwrap(deload.deloadPrescription?.normalExercises.first { $0.exerciseId == fixture.bench.id })
        let light = await viewModel.prepareSessionTemplate(for: deload)
        XCTAssertEqual(light?.exercises.map(\.exercise.name), ["Bench Press", "Plank"])
        XCTAssertEqual(light?.exercises.first?.targetWeight, normal.targetWeight / 2)
    }

    func testAPlanTheAssistantProposesCopiesTheTemplateItNames() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        let bench = PlanExercise(exerciseId: fixture.bench.id, exerciseName: fixture.bench.name, primaryMuscleGroup: .chest, category: .barbell,
            estimated1RM: 100, oneRMSource: .naturalLanguage, current1RM: 100, isCompound: true, order: 0)
        try await viewModel.createPlan(from: .init(name: "From chat", trainingStatus: .intermediate, programType: .linear,
            primaryGoal: .hypertrophy, weeklyFrequency: 1, trainingDays: [2], exercises: [bench],
            daySchedule: [DayScheduleEntry(dayOfWeek: 2, templateId: fixture.push.id, templateName: "Push", exerciseIds: [fixture.bench.id])],
            creationSource: .naturalLanguage, durationWeeks: 4, deloadEveryWeeks: 0))
        let sessions = ordered(viewModel.activePlan)
        XCTAssertEqual(sessions.count, 4)
        XCTAssertTrue(sessions.allSatisfy { $0.templateId == nil && names($0) == ["Bench Press", "Plank"] && $0.displayLabel == "Push" })
    }

    // MARK: - Editing a running plan

    /// The wizard's plan, saved and active: Monday "Push" with bench, Thursday squat, eight weeks
    /// without deload weeks, so every week is a step on the ladder.
    private func startPlan(_ fixture: Fixture) async throws -> ProgressionPlan {
        fillWorkouts(fixture)
        fixture.viewModel.draftDeloadEveryWeeks = 0
        await fixture.viewModel.prepareProgressionDraft()
        fixture.viewModel.setDraftStart(weightKg: 100, for: fixture.squat.id)
        await fixture.viewModel.generateAndSavePlan()
        return try XCTUnwrap(fixture.viewModel.activePlan)
    }

    private func ordered(_ plan: ProgressionPlan?) -> [PlannedSession] {
        (plan?.blocks.flatMap(\.weeks).flatMap(\.sessions) ?? []).sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
    }

    private func bench(_ session: PlannedSession, _ fixture: Fixture) -> String? {
        session.plannedExercises.first { $0.exerciseId == fixture.bench.id }.map { "\($0.targetWeight)x\($0.targetReps)" }
    }

    func testSessionEditAppliesInOneStepContinuesTheLadderAndCanBeUndone() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        let plan = try await startPlan(fixture)
        let first = ordered(plan)[0]
        let catalog = try await viewModel.planEditCatalog()
        var rows = try PlanEditingService.editableContents(for: first, plan: plan, templates: catalog.templates, exercises: catalog.exercises)
        XCTAssertEqual(rows.count, 2, "The template's plank is part of the session")
        let index = try XCTUnwrap(rows.firstIndex { $0.exerciseID == fixture.bench.id })
        rows[index].weightKg = 85
        rows[index].reps = 6

        try await viewModel.applyPlanEditNow(.init(operation: .batch, operations: [
            .init(operation: .setSessionExercises, sessionID: first.id, scope: .session, contents: rows),
            .init(operation: .updateSession, sessionID: first.id, scope: .session, label: "Heavy push")
        ]))

        let edited = ordered(viewModel.activePlan)
        XCTAssertEqual(edited[0].displayLabel, "Heavy push")
        XCTAssertEqual(bench(edited[0], fixture), "85.0x6")
        // The next bench session (Monday of week 2) continues from the manual target.
        XCTAssertEqual(bench(edited[2], fixture), "85.0x7")

        let last = try XCTUnwrap(viewModel.lastUndoableEdit)
        try await viewModel.applyPlanEditNow(.init(operation: .undoEdit, editID: last.id))
        let undone = ordered(viewModel.activePlan)
        XCTAssertEqual(bench(undone[0], fixture), "80.0x8")
        XCTAssertEqual(bench(undone[2], fixture), "80.0x9")
    }

    func testAddingAndRemovingAnExerciseCanReachTheSameWorkoutLater() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        let plan = try await startPlan(fixture)
        let before = ordered(plan)
        let sameDay = before.filter { $0.dayOfWeek == 2 }
        let otherDay = before.filter { $0.dayOfWeek != 2 }
        let first = sameDay[0]
        let laterCount = await viewModel.laterSessionCount(sameWorkoutAs: first)
        XCTAssertEqual(laterCount, sameDay.count - 1, "The Monday workout, later in the plan")

        // Monday is bench and plank. Drop the plank, and add the row and the squat.
        let catalog = try await viewModel.planEditCatalog()
        var rows = try PlanEditingService.editableContents(for: first, plan: plan, templates: catalog.templates, exercises: catalog.exercises)
        XCTAssertEqual(rows.map(\.exerciseID), [fixture.bench.id, fixture.plank.id])
        let kept = fixture.bench.id
        let dropped = fixture.plank.id
        let onARule = fixture.squat
        rows.removeLast()
        rows.append(.init(exerciseID: fixture.row.id, sets: 3, reps: 10, weightKg: 40))
        rows.append(.init(exerciseID: onARule.id, sets: 3, reps: 6, weightKg: 60))
        try await viewModel.applyPlanEditNow(.init(operation: .setSessionExercises, sessionID: first.id, scope: .remaining, contents: rows))

        let after = ordered(viewModel.activePlan)
        func session(_ id: UUID) -> PlannedSession? { after.first { $0.id == id } }
        for old in sameDay {
            let new = try XCTUnwrap(session(old.id))
            XCTAssertEqual(new.plannedExercises.map(\.exerciseId), [kept, fixture.row.id, onARule.id])
            XCTAssertFalse(new.plannedExercises.contains { $0.exerciseId == dropped })
            // The exercise that stayed keeps each session's own step on its ladder.
            XCTAssertEqual(new.plannedExercises[0].targetReps, old.plannedExercises[0].targetReps)
            XCTAssertEqual(new.plannedExercises[0].targetWeight, old.plannedExercises[0].targetWeight)
            // The new exercise without a rule asks for the same everywhere.
            XCTAssertEqual("\(new.plannedExercises[1].sets)x\(new.plannedExercises[1].targetReps)@\(new.plannedExercises[1].targetWeight)", "3x10@40.0")
        }
        // The one on a rule is pinned in the edited session only; later it follows its rule.
        let pinned = sameDay.compactMap { session($0.id)?.plannedExercises[2] }
        XCTAssertEqual(pinned.first?.isUserOverride, true)
        XCTAssertTrue(pinned.dropFirst().allSatisfy { $0.isUserOverride != true })
        XCTAssertGreaterThan(Set(pinned.map { "\($0.targetWeight)x\($0.targetReps)" }).count, 1, "It climbs instead of repeating the typed target")
        // The other day's workout is a different workout and is left alone.
        for old in otherDay { XCTAssertEqual(session(old.id)?.plannedExercises.map(\.exerciseId), old.plannedExercises.map(\.exerciseId)) }

        // The same edit for this session only touches one session.
        var again = try PlanEditingService.editableContents(for: try XCTUnwrap(session(sameDay[1].id)), plan: try XCTUnwrap(viewModel.activePlan),
            templates: catalog.templates, exercises: catalog.exercises)
        again.removeLast()
        try await viewModel.applyPlanEditNow(.init(operation: .setSessionExercises, sessionID: sameDay[1].id, scope: .session, contents: again))
        let single = ordered(viewModel.activePlan).filter { $0.dayOfWeek == 2 }
        XCTAssertEqual(single.map(\.plannedExercises.count), [3, 2] + Array(repeating: 3, count: sameDay.count - 2))
    }

    func testSettingsRenameChangeARuleAndExtendThePlan() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        _ = try await startPlan(fixture)

        try await viewModel.applyPlanEditNow(.init(operation: .renamePlan, label: "Spring"))
        XCTAssertEqual(fixture.plans.plans.first?.name, "Spring")

        let steps = ProgressionRule(kind: .fixedSteps, sets: 5, minReps: 5, maxReps: 5, incrementKg: 2.5,
            missesBeforeBackoff: 3, startWeightKg: 90)
        try await viewModel.applyPlanEditNow(.init(operation: .setProgression, exerciseID: fixture.bench.id, progression: steps))
        let ruled = ordered(viewModel.activePlan)
        XCTAssertEqual([ruled[0], ruled[2], ruled[4]].map { bench($0, fixture) }, ["90.0x5", "92.5x5", "95.0x5"])
        XCTAssertEqual(ruled[0].plannedExercises.first { $0.exerciseId == fixture.bench.id }?.sets, 5)

        try await viewModel.applyPlanEditNow(.init(operation: .extendPlan, weeks: 2, scope: .remaining))
        let extended = ordered(viewModel.activePlan)
        XCTAssertEqual(extended.count, 20)
        // The added weeks carry on up the ladder instead of repeating the last week.
        XCTAssertEqual(bench(extended[18], fixture), "112.5x5")
        XCTAssertEqual(viewModel.activePlan?.name, "Spring")
    }

    func testEditingScreensRender() async throws {
        let fixture = try await makeFixture()
        let plan = try await startPlan(fixture)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func show<V: View>(_ view: V, name: String) async throws {
            let host = UIHostingController(rootView: view)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            capture(window, name: name)
        }
        try await show(PlanSessionEditor(viewModel: fixture.viewModel, session: ordered(plan)[0]), name: "plan-edit-session")
        try await show(PlanSettingsView(viewModel: fixture.viewModel), name: "plan-settings")
        XCTAssertNil(fixture.viewModel.errorMessage)
    }

    // MARK: - Screens

    private func capture(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEveryWizardStepRendersTheDraft() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        let host = UIHostingController(rootView: PlanCreationView(viewModel: viewModel, exerciseListViewModel: fixture.exerciseList,
            templateViewModel: fixture.templates).preferredColorScheme(.dark))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func settle() async throws {
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
        }

        try await settle()
        XCTAssertEqual(viewModel.draftTrainingDays, [2, 4, 6], "The first step starts with three days a week")
        capture(window, name: "plan-wizard-1-basics")

        fillWorkouts(fixture)
        XCTAssertTrue(fixture.templates.userTemplates.isEmpty)
        viewModel.draftStep = 2
        try await settle()
        XCTAssertEqual(fixture.templates.userTemplates.map(\.name), ["Push"], "The step loads the templates its menu offers")
        capture(window, name: "plan-wizard-2-workouts")

        viewModel.draftStep = 3
        try await settle()
        XCTAssertNotNil(viewModel.draftPaceRecommendation, "Opening the step reads the log")
        viewModel.setDraftStart(weightKg: 100, for: fixture.squat.id)
        try await settle()
        capture(window, name: "plan-wizard-3-progression")

        // The deload settings sit below the fold: a taller window shows the whole step.
        viewModel.draftDeloadEveryWeeks = 4
        viewModel.draftUseCustomDeloadDays = true
        viewModel.applyDefaultDeloadDays()
        viewModel.toggleDeloadDay(5)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 1500)
        try await settle()
        capture(window, name: "plan-wizard-3-deloads")
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)

        viewModel.draftStep = 4
        try await settle()
        capture(window, name: "plan-wizard-4-preview")
        XCTAssertNil(viewModel.errorMessage)
    }
}
#endif
