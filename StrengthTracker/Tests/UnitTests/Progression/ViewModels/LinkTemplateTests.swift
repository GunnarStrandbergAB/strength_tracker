#if canImport(SwiftData)
import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("linkTemplate plan-wide behavior")
struct LinkTemplateTests {

    // MARK: - Helpers

    private static let squatLibId = UUID()
    private static let benchLibId = UUID()
    private static let rowLibId = UUID()
    private static let curlLibId = UUID()

    private func makeExercise(id: UUID, name: String) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeTemplateExercise(libId: UUID, name: String, order: Int) -> TemplateExercise {
        TemplateExercise(
            id: UUID(),
            exercise: makeExercise(id: libId, name: name),
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 120,
            targetSets: 4,
            targetReps: 8,
            targetWeight: 50,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil,
            setTargets: [],
            isWarmUp: false
        )
    }

    private func makeTemplate(id: UUID, name: String, libIds: [(UUID, String)]) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            name: name,
            notes: nil,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: libIds.enumerated().map { idx, pair in
                makeTemplateExercise(libId: pair.0, name: pair.1, order: idx)
            }
        )
    }

    private func makePlanExercise(libId: UUID, name: String, oneRM: Double = 100) -> PlanExercise {
        PlanExercise(
            exerciseId: libId,
            exerciseName: name,
            primaryMuscleGroup: .quadriceps,
            category: .barbell,
            estimated1RM: oneRM,
            oneRMSource: .userInput,
            current1RM: oneRM,
            isCompound: true,
            order: 0
        )
    }

    /// Build a plan with two weeks × two days (Friday=6, Saturday=7). Friday sessions have a
    /// progression-tracked exercise (bench) so they act as the intensity donor for Saturday.
    /// Saturday sessions start empty (mimicking the user's "Pull with no progression" scenario).
    private func makeTestPlan(squatPE: PlanExercise, benchPE: PlanExercise) -> ProgressionPlan {
        let friSessionWeek1 = PlannedSession(
            dayOfWeek: 6,
            sessionLabel: "Friday W1",
            plannedExercises: [
                PlannedExerciseSet(
                    planExerciseId: benchPE.id,
                    exerciseId: benchPE.exerciseId,
                    exerciseName: benchPE.exerciseName,
                    sets: 4,
                    targetReps: 5,
                    targetWeight: 80,
                    percentageOf1RM: 0.80,
                    restSeconds: 150
                )
            ]
        )
        let satSessionWeek1 = PlannedSession(
            dayOfWeek: 7,
            sessionLabel: "Saturday W1",
            plannedExercises: []
        )
        let friSessionWeek2 = PlannedSession(
            dayOfWeek: 6,
            sessionLabel: "Friday W2",
            plannedExercises: [
                PlannedExerciseSet(
                    planExerciseId: benchPE.id,
                    exerciseId: benchPE.exerciseId,
                    exerciseName: benchPE.exerciseName,
                    sets: 4,
                    targetReps: 5,
                    targetWeight: 82.5,
                    percentageOf1RM: 0.825,
                    restSeconds: 150
                )
            ]
        )
        let satSessionWeek2 = PlannedSession(
            dayOfWeek: 7,
            sessionLabel: "Saturday W2",
            plannedExercises: []
        )

        let week1 = TrainingWeek(
            weekNumber: 1,
            absoluteWeekNumber: 1,
            sessions: [friSessionWeek1, satSessionWeek1]
        )
        let week2 = TrainingWeek(
            weekNumber: 2,
            absoluteWeekNumber: 2,
            sessions: [friSessionWeek2, satSessionWeek2]
        )
        let block = TrainingBlock(
            name: "Block 1",
            order: 0,
            durationWeeks: 2,
            weeks: [week1, week2]
        )

        return ProgressionPlan(
            name: "Test",
            status: .active,
            trainingStatus: .intermediate,
            programType: .linear,
            primaryGoal: .strength,
            weeklyFrequency: 2,
            startDate: Date(),
            exercises: [squatPE, benchPE],
            blocks: [block]
        )
    }

    @MainActor
    private func makeVM(plan: ProgressionPlan, templates: [WorkoutTemplate]) -> (ProgressionPlanViewModel, CapturingProgressionPlanRepository) {
        let repo = CapturingProgressionPlanRepository(initial: plan)
        let templatesRepo = StaticTemplateRepository(templates: templates)
        let workoutRepo = StubWorkoutRepository()
        let vm = ProgressionPlanViewModel(
            progressionPlanRepository: repo,
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: workoutRepo),
            programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: workoutRepo),
            exerciseRepository: StubExerciseRepository(),
            templateRepository: templatesRepo
        )
        vm.activePlan = plan
        return (vm, repo)
    }

    // MARK: - Cases

    @Test("Plan-wide propagation: every Saturday across weeks gets the new templateId + daySchedule updated")
    @MainActor
    func planWidePropagation() async {
        let squatPE = makePlanExercise(libId: Self.squatLibId, name: "Squat")
        let benchPE = makePlanExercise(libId: Self.benchLibId, name: "Bench")
        let plan = makeTestPlan(squatPE: squatPE, benchPE: benchPE)

        // New template: Lower contains squat (matches a tracked plan exercise) + one untracked exercise.
        let lowerTemplate = makeTemplate(
            id: UUID(),
            name: "Lower",
            libIds: [(Self.squatLibId, "Squat"), (Self.curlLibId, "Curl")]
        )

        let (vm, repo) = makeVM(plan: plan, templates: [lowerTemplate])

        let satSessionId = plan.blocks[0].weeks[0].sessions.first { $0.dayOfWeek == 7 }!.id
        await vm.linkTemplate(templateId: lowerTemplate.id, toSession: satSessionId)

        let saved = repo.saved!

        // daySchedule has Saturday with the new template + auto-picked squat (the only match).
        let satEntry = saved.daySchedule.first { $0.dayOfWeek == 7 }
        #expect(satEntry?.templateId == lowerTemplate.id)
        #expect(satEntry?.templateName == "Lower")
        #expect(satEntry?.exerciseIds == [Self.squatLibId])

        // Every Saturday session across both weeks has the new templateId.
        let saturdays = saved.blocks.flatMap(\.weeks).flatMap(\.sessions).filter { $0.dayOfWeek == 7 }
        #expect(saturdays.count == 2)
        for s in saturdays {
            #expect(s.templateId == lowerTemplate.id, "Saturday session should be linked to Lower")
        }

        // Friday sessions untouched.
        let fridays = saved.blocks.flatMap(\.weeks).flatMap(\.sessions).filter { $0.dayOfWeek == 6 }
        for f in fridays {
            #expect(f.templateId == nil || f.templateId != lowerTemplate.id)
            #expect(f.plannedExercises.count == 1) // bench still there
            #expect(f.plannedExercises[0].exerciseId == Self.benchLibId)
        }
    }

    @Test("Auto-pick: squat infused into Saturday with weight derived from Friday sibling's intensity")
    @MainActor
    func autoPickFromSibling() async {
        let squatPE = makePlanExercise(libId: Self.squatLibId, name: "Squat", oneRM: 130)
        let benchPE = makePlanExercise(libId: Self.benchLibId, name: "Bench", oneRM: 100)
        let plan = makeTestPlan(squatPE: squatPE, benchPE: benchPE)

        let lowerTemplate = makeTemplate(
            id: UUID(),
            name: "Lower",
            libIds: [(Self.squatLibId, "Squat"), (Self.curlLibId, "Curl")]
        )

        let (vm, repo) = makeVM(plan: plan, templates: [lowerTemplate])
        let satSessionId = plan.blocks[0].weeks[0].sessions.first { $0.dayOfWeek == 7 }!.id
        await vm.linkTemplate(templateId: lowerTemplate.id, toSession: satSessionId)

        let saved = repo.saved!

        // Week 1 Saturday: donor is Friday W1 (bench at 0.80 of 1RM).
        let satWeek1 = saved.blocks[0].weeks[0].sessions.first { $0.dayOfWeek == 7 }!
        #expect(satWeek1.plannedExercises.count == 2, "Lower template has 2 exercises")

        let squatRow = satWeek1.plannedExercises.first { $0.exerciseId == Self.squatLibId }!
        #expect(squatRow.percentageOf1RM == 0.80, "Saturday squat should inherit Friday's 80% intensity")
        // 130 * 0.80 = 104; rounded to nearest 2.5 = 105 (104 -> 105 since 105 is closer than 102.5).
        #expect(squatRow.targetWeight == 105, "Saturday squat weight should reflect squat's own 1RM at donor's intensity")
        #expect(squatRow.planExerciseId == squatPE.id)

        let curlRow = satWeek1.plannedExercises.first { $0.exerciseId == Self.curlLibId }!
        #expect(curlRow.percentageOf1RM == 0, "Untracked exercise has no progression intensity")
        #expect(curlRow.sets == 4, "Untracked exercise uses template's targetSets")

        // Week 2 Saturday: donor is Friday W2 (bench at 0.825 of 1RM).
        let satWeek2 = saved.blocks[0].weeks[1].sessions.first { $0.dayOfWeek == 7 }!
        let squatRowW2 = satWeek2.plannedExercises.first { $0.exerciseId == Self.squatLibId }!
        #expect(squatRowW2.percentageOf1RM == 0.825)
        // 130 * 0.825 = 107.25 -> rounded to nearest 2.5 = 107.5
        #expect(squatRowW2.targetWeight == 107.5)
    }

    @Test("No matching plan exercise: switching to a template with zero overlap yields only template-default rows")
    @MainActor
    func noMatchFallback() async {
        let squatPE = makePlanExercise(libId: Self.squatLibId, name: "Squat")
        let benchPE = makePlanExercise(libId: Self.benchLibId, name: "Bench")
        let plan = makeTestPlan(squatPE: squatPE, benchPE: benchPE)

        // Pull template: no overlap with plan.exercises.
        let pullTemplate = makeTemplate(
            id: UUID(),
            name: "Pull",
            libIds: [(Self.rowLibId, "Row"), (Self.curlLibId, "Curl")]
        )

        let (vm, repo) = makeVM(plan: plan, templates: [pullTemplate])
        let satSessionId = plan.blocks[0].weeks[0].sessions.first { $0.dayOfWeek == 7 }!.id
        await vm.linkTemplate(templateId: pullTemplate.id, toSession: satSessionId)

        let saved = repo.saved!
        let satEntry = saved.daySchedule.first { $0.dayOfWeek == 7 }!
        #expect(satEntry.exerciseIds.isEmpty, "No plan exercise matches → empty exerciseIds")

        let sat = saved.blocks[0].weeks[0].sessions.first { $0.dayOfWeek == 7 }!
        #expect(sat.plannedExercises.count == 2)
        for row in sat.plannedExercises {
            #expect(row.percentageOf1RM == 0, "All rows should be template-default (no progression)")
            #expect(row.sets == 4)
        }
    }

    @Test("Completion preservation: an already-completed Saturday session is untouched")
    @MainActor
    func completionPreserved() async {
        let squatPE = makePlanExercise(libId: Self.squatLibId, name: "Squat")
        let benchPE = makePlanExercise(libId: Self.benchLibId, name: "Bench")
        var plan = makeTestPlan(squatPE: squatPE, benchPE: benchPE)

        // Mark Saturday Week 1 as completed.
        let completedWorkoutId = UUID()
        let completedAt = Date()
        plan.blocks[0].weeks[0].sessions[1].completedWorkoutId = completedWorkoutId
        plan.blocks[0].weeks[0].sessions[1].completedAt = completedAt
        plan.blocks[0].weeks[0].sessions[1].plannedExercises = [
            PlannedExerciseSet(
                planExerciseId: UUID(),
                exerciseId: Self.rowLibId,
                exerciseName: "Row",
                sets: 3, targetReps: 10, targetWeight: 60,
                percentageOf1RM: 0.60
            )
        ]
        let preservedExercises = plan.blocks[0].weeks[0].sessions[1].plannedExercises

        let lowerTemplate = makeTemplate(
            id: UUID(),
            name: "Lower",
            libIds: [(Self.squatLibId, "Squat")]
        )
        let (vm, repo) = makeVM(plan: plan, templates: [lowerTemplate])

        let satWeek2Id = plan.blocks[0].weeks[1].sessions.first { $0.dayOfWeek == 7 }!.id
        await vm.linkTemplate(templateId: lowerTemplate.id, toSession: satWeek2Id)

        let saved = repo.saved!

        // Week 1 Saturday (completed): untouched
        let satWeek1 = saved.blocks[0].weeks[0].sessions[1]
        #expect(satWeek1.completedWorkoutId == completedWorkoutId)
        #expect(satWeek1.completedAt == completedAt)
        #expect(satWeek1.plannedExercises == preservedExercises)
        #expect(satWeek1.templateId == nil, "Completed session's templateId was nil and stays nil")

        // Week 2 Saturday (uncompleted): updated
        let satWeek2 = saved.blocks[0].weeks[1].sessions.first { $0.dayOfWeek == 7 }!
        #expect(satWeek2.templateId == lowerTemplate.id)
        #expect(satWeek2.plannedExercises.first { $0.exerciseId == Self.squatLibId } != nil)
    }

    @Test("No-op early exit: linking the same template + same auto-pick saves nothing")
    @MainActor
    func noOpEarlyExit() async {
        let squatPE = makePlanExercise(libId: Self.squatLibId, name: "Squat")
        let benchPE = makePlanExercise(libId: Self.benchLibId, name: "Bench")
        var plan = makeTestPlan(squatPE: squatPE, benchPE: benchPE)

        let lowerTemplate = makeTemplate(
            id: UUID(),
            name: "Lower",
            libIds: [(Self.squatLibId, "Squat")]
        )
        // Pre-seed daySchedule so the entry already matches what linkTemplate would compute.
        plan.daySchedule = [
            DayScheduleEntry(
                dayOfWeek: 7,
                templateId: lowerTemplate.id,
                templateName: "Lower",
                exerciseIds: [Self.squatLibId]
            )
        ]

        let (vm, repo) = makeVM(plan: plan, templates: [lowerTemplate])
        let satSessionId = plan.blocks[0].weeks[0].sessions.first { $0.dayOfWeek == 7 }!.id
        await vm.linkTemplate(templateId: lowerTemplate.id, toSession: satSessionId)

        #expect(repo.saveCallCount == 0, "Re-linking the same template + same auto-pick must not save")
    }

    @Test("Change Template clears stale DUP rotation metadata (dupSessionType + sessionLabel)")
    @MainActor
    func clearsRotationMetadata() async {
        let squatPE = makePlanExercise(libId: Self.squatLibId, name: "Squat")
        let benchPE = makePlanExercise(libId: Self.benchLibId, name: "Bench")
        var plan = makeTestPlan(squatPE: squatPE, benchPE: benchPE)

        // Pre-seed Saturday sessions as if they were originally generated by the DUP path
        // (rotation badge + composite label). Friday sessions get a different rotation
        // so we can confirm they stay untouched.
        plan.blocks[0].weeks[0].sessions[1].dupSessionType = .hypertrophy
        plan.blocks[0].weeks[0].sessions[1].sessionLabel = "Saturday - Hypertrophy"
        plan.blocks[0].weeks[1].sessions[1].dupSessionType = .hypertrophy
        plan.blocks[0].weeks[1].sessions[1].sessionLabel = "Saturday - Hypertrophy"
        plan.blocks[0].weeks[0].sessions[0].dupSessionType = .power
        plan.blocks[0].weeks[0].sessions[0].sessionLabel = "Friday - Power"
        plan.blocks[0].weeks[1].sessions[0].dupSessionType = .power
        plan.blocks[0].weeks[1].sessions[0].sessionLabel = "Friday - Power"

        let lowerTemplate = makeTemplate(
            id: UUID(),
            name: "Lower",
            libIds: [(Self.squatLibId, "Squat")]
        )

        let (vm, repo) = makeVM(plan: plan, templates: [lowerTemplate])
        let satSessionId = plan.blocks[0].weeks[0].sessions.first { $0.dayOfWeek == 7 }!.id
        await vm.linkTemplate(templateId: lowerTemplate.id, toSession: satSessionId)

        let saved = repo.saved!

        // Saturday sessions across all weeks: rotation metadata cleared, neutral label.
        let saturdays = saved.blocks.flatMap(\.weeks).flatMap(\.sessions).filter { $0.dayOfWeek == 7 }
        for s in saturdays {
            #expect(s.dupSessionType == nil, "Saturday session should have no rotation type after change")
            #expect(s.sessionLabel == "Saturday", "Saturday session label should be the neutral day name, got '\(s.sessionLabel)'")
        }

        // Friday (untouched day) keeps its original rotation metadata.
        let fridays = saved.blocks.flatMap(\.weeks).flatMap(\.sessions).filter { $0.dayOfWeek == 6 }
        for f in fridays {
            #expect(f.dupSessionType == .power, "Friday's rotation should be unchanged")
            #expect(f.sessionLabel == "Friday - Power")
        }
    }

    @Test("Picker matchCount counts plan.exercises (not session.plannedExercises)")
    func matchCountAgainstPlanExercises() {
        let squatPE = makePlanExercise(libId: Self.squatLibId, name: "Squat")
        let benchPE = makePlanExercise(libId: Self.benchLibId, name: "Bench")

        let lowerTemplate = makeTemplate(
            id: UUID(),
            name: "Lower",
            libIds: [(Self.squatLibId, "Squat"), (Self.curlLibId, "Curl")]
        )
        let pullTemplate = makeTemplate(
            id: UUID(),
            name: "Pull",
            libIds: [(Self.rowLibId, "Row")]
        )

        #expect(PlanExercise.matchCount(template: lowerTemplate, planExercises: [squatPE, benchPE]) == 1)
        #expect(PlanExercise.matchCount(template: pullTemplate, planExercises: [squatPE, benchPE]) == 0)
    }
}

// MARK: - Capturing/static stubs

private final class CapturingProgressionPlanRepository: ProgressionPlanRepository, @unchecked Sendable {
    private var current: ProgressionPlan
    var saved: ProgressionPlan?
    var saveCallCount = 0

    init(initial: ProgressionPlan) { self.current = initial }

    func fetchAll() async throws -> [ProgressionPlan] { [current] }
    func fetchActive() async throws -> ProgressionPlan? { current }
    func fetch(id: UUID) async throws -> ProgressionPlan? { id == current.id ? current : nil }
    func save(_ plan: ProgressionPlan) async throws {
        saveCallCount += 1
        saved = plan
        current = plan
    }
    func delete(_ plan: ProgressionPlan) async throws {}
    func updateStatus(_ planId: UUID, status: PlanStatus) async throws {}
    func addAdjustment(_ adjustment: PlanAdjustment, toPlan planId: UUID) async throws {}
    func updateExercise(_ exercise: PlanExercise, inPlan planId: UUID) async throws {}
    func updateBlock(_ block: TrainingBlock, inPlan planId: UUID) async throws {}
    func markSessionCompleted(_ sessionId: UUID, workoutId: UUID, inPlan planId: UUID) async throws {}
}

private final class StaticTemplateRepository: TemplateRepository, @unchecked Sendable {
    let templates: [WorkoutTemplate]
    init(templates: [WorkoutTemplate]) { self.templates = templates }
    func fetchAll() async throws -> [WorkoutTemplate] { templates }
    func save(_ template: WorkoutTemplate) async throws -> WorkoutTemplate { template }
    func delete(_ template: WorkoutTemplate) async throws {}
    func incrementUsage(_ templateId: UUID) async throws {}
}

private final class StubExerciseRepository: ExerciseRepository, @unchecked Sendable {
    func fetchAll() async throws -> [Exercise] { [] }
    func fetchByCategory(_ category: ExerciseCategory) async throws -> [Exercise] { [] }
    func fetchByMuscleGroup(_ muscleGroup: MuscleGroup) async throws -> [Exercise] { [] }
    func search(name: String) async throws -> [Exercise] { [] }
    func save(_ exercise: Exercise) async throws -> Exercise { exercise }
    func delete(_ exercise: Exercise) async throws {}
}

private final class StubWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    func fetchAll() async throws -> [Workout] { [] }
    func fetchActive() async throws -> Workout? { nil }
    func fetchByDateRange(_ start: Date, _ end: Date) async throws -> [Workout] { [] }
    func save(_ workout: Workout) async throws -> Workout { workout }
    func complete(_ workoutId: UUID) async throws {}
    func delete(_ workout: Workout) async throws {}
    func deleteAllIncomplete() async throws {}
}
#endif
