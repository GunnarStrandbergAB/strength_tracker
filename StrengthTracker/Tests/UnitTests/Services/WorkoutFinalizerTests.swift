import Testing
import Foundation
@testable import StrengthTrackerShared

@MainActor
final class SpyWidgetRefresh: WidgetRefreshing {
    var refreshCount = 0
    var revisionAtRefresh: [Int] = []
    let revision: DataRevision
    init(revision: DataRevision) { self.revision = revision }
    func refresh() async {
        refreshCount += 1
        revisionAtRefresh.append(revision.value)
    }
}

@Suite("WorkoutFinalizer")
@MainActor
struct WorkoutFinalizerTests {

    private struct Stack {
        let finalizer: WorkoutFinalizer
        let workoutRepo: InMemoryWorkoutRepository
        let analyticsRepo: InMemoryAnalyticsRepository
        let prRepo: InMemoryPersonalRecordRepository
        let healthKit: MockHealthKitService
        let revision: DataRevision
        let widget: SpyWidgetRefresh
    }

    private func makeStack() -> Stack {
        let workoutRepo = InMemoryWorkoutRepository()
        let analyticsRepo = InMemoryAnalyticsRepository()
        let prRepo = InMemoryPersonalRecordRepository()
        let healthKit = MockHealthKitService()
        let revision = DataRevision()
        let widget = SpyWidgetRefresh(revision: revision)
        let analyticsService = WorkoutAnalyticsService(
            analyticsRepository: analyticsRepo,
            workoutRepository: workoutRepo,
            exerciseRepository: InMemoryExerciseRepository(),
            vectorizer: WorkoutVectorizer(),
            searchService: VectorSearchService(),
            plateauService: PlateauDetectionService(),
            muscleBalanceService: MuscleBalanceService(),
            recommendationService: ExerciseRecommendationService(),
            dataRevision: revision
        )
        let prService = PersonalRecordService(personalRecordRepository: prRepo, workoutRepository: workoutRepo)
        let finalizer = WorkoutFinalizer(
            workoutRepository: workoutRepo,
            analyticsRepository: analyticsRepo,
            analyticsService: analyticsService,
            personalRecordService: prService,
            qualityScoreService: nil,
            healthKitService: healthKit,
            webhookService: nil,
            widgetRefresh: widget,
            bodyWeightProvider: nil,
            dataRevision: revision
        )
        return Stack(finalizer: finalizer, workoutRepo: workoutRepo, analyticsRepo: analyticsRepo, prRepo: prRepo, healthKit: healthKit, revision: revision, widget: widget)
    }

    private func completedWorkout(_ exercise: Exercise, weight: Double, daysAgo: Int) -> Workout {
        let start = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        let set = AnalyticsTestHelpers.makeCompletedSet(weight: weight, reps: 5, completedAt: start.addingTimeInterval(1800))
        return AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: [set])],
            startedAt: start, completedAt: start.addingTimeInterval(3600)
        )
    }

    @Test("completed: vector stored, PR row + flag, HealthKit saved with id, revision bumped once before the widget refresh")
    func completedPipeline() async throws {
        let s = makeStack()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        let workout = try await s.workoutRepo.save(completedWorkout(bench, weight: 100, daysAgo: 0))
        var sessionHook: (UUID, UUID, UUID)?
        s.finalizer.onSessionCompleted = { a, b, c in sessionHook = (a, b, c) }

        let finalized = await s.finalizer.workoutCompleted(workout, source: .phone)

        #expect(try await s.analyticsRepo.fetchVector(for: workout.id) != nil)
        #expect(try await s.prRepo.fetchForExercise(bench.id).contains { $0.recordType == .maxWeight && $0.value == 100 })
        #expect(finalized.exercises[0].sets[0].isPersonalRecord)
        #expect(finalized.healthKitWorkoutId != nil)
        #expect(s.healthKit.savedWorkoutIds == [workout.id])
        #expect(s.revision.value == 1)
        #expect(s.widget.refreshCount == 1)
        #expect(s.widget.revisionAtRefresh == [1], "widgets read post-bump state")
        #expect(sessionHook == nil, "no plan link → no hook")
    }

    @Test("completed from the Watch: no HealthKit save, plan hook fires when linked")
    func watchPipeline() async throws {
        let s = makeStack()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        var workout = completedWorkout(bench, weight: 90, daysAgo: 0)
        workout.plannedSessionId = UUID(); workout.plannedPlanId = UUID()
        var hook: (UUID, UUID, UUID)?
        s.finalizer.onSessionCompleted = { a, b, c in hook = (a, b, c) }

        await s.finalizer.workoutReceivedFromWatch(workout, metadata: nil)

        #expect(s.healthKit.savedWorkoutIds.isEmpty)
        #expect(hook?.0 == workout.plannedSessionId && hook?.2 == workout.id)
        #expect(try await s.workoutRepo.fetchAll().count == 1)
        #expect(s.revision.value == 1)
    }

    @Test("edited: records re-elected for the touched exercise, HealthKit replaced, plan edit hook fires")
    func editedPipeline() async throws {
        let s = makeStack()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        let saved = try await s.workoutRepo.save(completedWorkout(bench, weight: 100, daysAgo: 1))
        let completed = await s.finalizer.workoutCompleted(saved, source: .phone)
        #expect(completed.healthKitWorkoutId != nil)

        var edited = completed
        edited.exercises[0].sets[0].weight = 80
        edited.plannedSessionId = UUID(); edited.plannedPlanId = UUID()
        edited = try await s.workoutRepo.save(edited)
        var editHook: UUID?
        s.finalizer.onSessionEdited = { _, _, workoutId in editHook = workoutId }

        _ = await s.finalizer.workoutEdited(edited, touchedExerciseIds: [bench.id], retro: nil)

        #expect(try await s.prRepo.fetchForExercise(bench.id).first { $0.recordType == .maxWeight }?.value == 80)
        #expect(s.healthKit.deletedWorkoutIds == [saved.id])
        #expect(s.healthKit.savedWorkoutIds == [saved.id, saved.id], "delete then resave")
        #expect(editHook == saved.id)
        #expect(s.revision.value == 2)
    }

    @Test("deleted: vector and records gone, unlink hook fires, HealthKit deleted")
    func deletedPipeline() async throws {
        let s = makeStack()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        let saved = try await s.workoutRepo.save(completedWorkout(bench, weight: 100, daysAgo: 1))
        _ = await s.finalizer.workoutCompleted(saved, source: .phone)
        try await s.workoutRepo.delete(saved)
        var unlinked: UUID?
        s.finalizer.onWorkoutUnlinked = { unlinked = $0 }

        await s.finalizer.workoutDeleted(saved)

        #expect(try await s.analyticsRepo.fetchVector(for: saved.id) == nil)
        #expect(try await s.prRepo.fetchForExercise(bench.id).isEmpty, "no history left → no rows")
        #expect(unlinked == saved.id)
        #expect(s.healthKit.deletedWorkoutIds == [saved.id])
        #expect(s.revision.value == 2)
    }

    @Test("pipelines run in order and bump exactly once each")
    func serialization() async throws {
        let s = makeStack()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        let a = try await s.workoutRepo.save(completedWorkout(bench, weight: 100, daysAgo: 2))
        let b = try await s.workoutRepo.save(completedWorkout(bench, weight: 110, daysAgo: 1))
        async let first = s.finalizer.workoutCompleted(a, source: .phone)
        async let second = s.finalizer.workoutCompleted(b, source: .phone)
        _ = await (first, second)
        #expect(s.revision.value == 2)
        #expect(s.widget.revisionAtRefresh == [1, 2])
        #expect(try await s.prRepo.fetchForExercise(bench.id).first { $0.recordType == .maxWeight }?.value == 110)
    }
}
