import Testing
import Foundation
import SwiftUI
@testable import StrengthTracker
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
        let analyticsService: WorkoutAnalyticsService
        let analyticsRepo: MockAnalyticsRepository
        let prRepo: InMemoryPersonalRecordRepository
        let healthKit: MockHealthKitService
        let revision: DataRevision
        let widget: SpyWidgetRefresh
    }

    private func makeStack(reopening previous: Stack? = nil, defaults: UserDefaults? = nil) -> Stack {
        let workoutRepo = previous?.workoutRepo ?? InMemoryWorkoutRepository()
        let analyticsRepo = previous?.analyticsRepo ?? MockAnalyticsRepository()
        let prRepo = previous?.prRepo ?? InMemoryPersonalRecordRepository()
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
            dataRevision: revision,
            repairDefaults: defaults
        )
        return Stack(finalizer: finalizer, workoutRepo: workoutRepo, analyticsService: analyticsService, analyticsRepo: analyticsRepo, prRepo: prRepo, healthKit: healthKit, revision: revision, widget: widget)
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

extension WorkoutFinalizerTests {
    @Test("Version 3 alternating records are rebuilt once without changing logged weights, reps or manual records")
    func alternatingMigration() async throws {
        let stack = makeStack()
        var exercise = AnalyticsTestHelpers.makeExercise(name: "Alternating curl")
        exercise.category = .dumbbell
        exercise.weightRecording = .init(equipment: .single, repetitions: .totalAlternating)
        var workout = completedWorkout(exercise, weight: 24, daysAgo: 1)
        workout.exercises[0].sets[0].reps = 16
        _ = try await stack.workoutRepo.save(workout)
        let stale = PersonalRecord(id: UUID(), exerciseId: exercise.id, recordType: .estimatedOneRepMax, value: 36,
            setId: workout.exercises[0].sets[0].id, achievedAt: workout.trainingDate, weightRecordingKey: exercise.performanceConvention)
        let manual = PersonalRecord(id: UUID(), exerciseId: exercise.id, recordType: .maxWeight, value: 99,
            setId: nil, achievedAt: workout.trainingDate)
        _ = try await stack.prRepo.save(stale)
        _ = try await stack.prRepo.save(manual)
        let suite = "AlternatingMigration.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3, forKey: "analytics_derived_model_version")
        #expect(await stack.finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults))
        let records = try await stack.prRepo.fetchForExercise(exercise.id)
        #expect(records.contains(manual))
        #expect(records.contains { $0.recordType == .estimatedOneRepMax && abs($0.value - 30.4) < 0.000001 })
        let saved = try #require(try await stack.workoutRepo.fetchAll().first)
        #expect(saved.exercises[0].sets[0].weight == 24)
        #expect(saved.exercises[0].sets[0].reps == 16)
        #expect(saved.totalVolume(bodyWeightKg: 80) == 384)
        #expect(!(await stack.finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults)))
        #expect(stack.revision.value == 1)
        #expect(stack.healthKit.savedWorkoutIds.isEmpty)
    }
}

extension WorkoutFinalizerTests {
    private func checkStoredVectors(_ s: Stack) async throws {
        let history = try await s.workoutRepo.fetchAll()
        let vectors = try await s.analyticsRepo.fetchAllVectors()
        #expect(Set(vectors.map(\.workoutId)) == Set(history.filter { $0.completedAt != nil }.map(\.id)))
        for workout in history where workout.completedAt != nil {
            let stored = try #require(vectors.first { $0.workoutId == workout.id })
            let expected = WorkoutVectorizer().vectorize(workout, historicalWorkouts: history)
            #expect(zip(stored.dimensions, expected.dimensions).allSatisfy { abs($0 - $1) < 1e-10 })
            #expect(abs((stored.magnitude ?? 0) - (expected.magnitude ?? 0)) < 1e-10)
        }
    }

    @Test("An edit transfers an old record and replaces dependent vectors after backdating and deletion")
    func dependentVectors() async throws {
        let s = makeStack()
        let bench = AnalyticsTestHelpers.makeExercise()
        // The original record holder is outside both volume windows.
        var sessions: [Workout] = []
        for (day, weight) in [(90, 100.0), (29, 80), (10, 60), (2, 75)] {
            let saved = try await s.workoutRepo.save(completedWorkout(bench, weight: weight, daysAgo: day))
            sessions.append(await s.finalizer.workoutCompleted(saved, source: .watch))
        }
        let editor = HistoryViewModel(workoutRepository: s.workoutRepo)
        editor.finalizer = s.finalizer
        await editor.loadHistory()
        let target = try #require(editor.workout(for: sessions[1].id))
        editor.selectWorkout(target)
        editor.isEditing = true
        await editor.updateSetWeight(exerciseId: target.exercises[0].id, setId: target.exercises[0].sets[0].id, weight: 120)
        await editor.endEditing()
        try await checkStoredVectors(s)
        let holder = try #require(try await s.prRepo.fetchForExercise(bench.id).first { $0.recordType == .maxWeight })
        #expect(holder.setId == target.exercises[0].sets[0].id)
        let retro = try await s.workoutRepo.save(completedWorkout(bench, weight: 93, daysAgo: 5))
        _ = await s.finalizer.workoutEdited(retro, touchedExerciseIds: [bench.id], retro: .init(saveToHealthKit: false))
        try await checkStoredVectors(s)
        // Deleting from an open editor must also release the draft and re-elect
        // the exercise that was swapped out before Done.
        editor.isEditing = true
        await editor.replaceExercise(exerciseId: target.exercises[0].id, with: AnalyticsTestHelpers.makeExercise(name: "Press"))
        let draft = try #require(editor.selectedWorkout)
        await editor.deleteWorkout(draft)
        #expect(!editor.isEditing && editor.selectedWorkout == nil)
        let remainingRecord = try #require(try await s.prRepo.fetchForExercise(bench.id).first { $0.recordType == .maxWeight })
        #expect(remainingRecord.value == 100)
        try await checkStoredVectors(s)
    }

    @Test("Restart repairs autosaved edits and failed vector writes without repeating exports")
    func interruptedRepair() async throws {
        let suite = "HistoryEditRepair.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = makeStack(defaults: defaults)
        let exercise = AnalyticsTestHelpers.makeExercise()
        let workout = try await first.workoutRepo.save(completedWorkout(exercise, weight: 80, daysAgo: 3))
        let complete = await first.finalizer.workoutCompleted(workout, source: .phone)
        // Simulate an already migrated installation, then quit between field save and Done.
        #expect(await first.finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults))
        let editor = HistoryViewModel(workoutRepository: first.workoutRepo)
        editor.finalizer = first.finalizer
        editor.selectWorkout(complete)
        editor.isEditing = true
        await editor.updateSetWeight(exerciseId: complete.exercises[0].id, setId: complete.exercises[0].sets[0].id, weight: 100)
        let reopened = makeStack(reopening: first, defaults: defaults)
        reopened.analyticsRepo.shouldThrowOnStore = true
        #expect(!(await reopened.finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults)))
        #expect(reopened.revision.value == 0)
        reopened.analyticsRepo.shouldThrowOnStore = false
        #expect(await reopened.finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults))
        try await checkStoredVectors(reopened)
        #expect(!(await reopened.finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults)))
        #expect(reopened.healthKit.savedWorkoutIds.isEmpty && reopened.healthKit.deletedWorkoutIds.isEmpty)

        let edited = try #require(try await reopened.workoutRepo.fetchAll().first)
        reopened.analyticsRepo.shouldThrowOnStore = true
        _ = await reopened.finalizer.workoutEdited(edited, touchedExerciseIds: [exercise.id], retro: nil)
        #expect(reopened.revision.value == 1)
        #expect(reopened.finalizer.localRepairError != nil)
        reopened.analyticsRepo.shouldThrowOnStore = false
        let retry = makeStack(reopening: reopened, defaults: defaults)
        #expect(await retry.finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults))
        #expect(retry.healthKit.savedWorkoutIds.isEmpty && retry.healthKit.deletedWorkoutIds.isEmpty)
        try await checkStoredVectors(retry)
    }

    @Test("Mounted Dashboard and History resolve a correction by ID, including the same-day mean")
    func dashboardEditPropagation() async throws {
        let s = makeStack()
        let bench = AnalyticsTestHelpers.makeExercise()
        let today = Calendar.current.startOfDay(for: Date())
        let elapsed = Date().timeIntervalSince(today)
        var sameDay: [Workout] = []
        for (day, weight) in [(9, 80.0), (7, 80), (5, 80), (3, 80), (0, 40), (0, 70)] {
            var workout = completedWorkout(bench, weight: weight, daysAgo: day)
            if day == 0 {
                workout.startedAt = today.addingTimeInterval(elapsed * (sameDay.isEmpty ? 0.2 : 0.6))
                workout.completedAt = workout.startedAt.addingTimeInterval(elapsed * 0.1)
                workout.exercises[0].sets[0].completedAt = workout.completedAt
                workout.name = sameDay.isEmpty ? "Corrected morning workout" : "Later workout"
                sameDay.append(workout)
            }
            let saved = try await s.workoutRepo.save(workout)
            _ = await s.finalizer.workoutCompleted(saved, source: .watch)
        }
        let prefs = UserPreferencesService()
        let quality = WorkoutQualityScoreService(workoutRepository: s.workoutRepo, muscleBalanceService: MuscleBalanceService(),
                                                healthKitService: s.healthKit, userPreferencesService: prefs)
        let analytics = WorkoutAnalyticsViewModel(analyticsService: s.analyticsService, qualityScoreService: quality,
            featureGate: AnalyticsFeatureGate(workoutRepository: s.workoutRepo), workoutRepository: s.workoutRepo, dataRevision: s.revision)
        let dashboard = DashboardViewModel(workoutRepository: s.workoutRepo, personalRecordRepository: s.prRepo,
            qualityScoreService: quality, healthKitService: s.healthKit, userPreferencesService: prefs)
        let history = HistoryViewModel(workoutRepository: s.workoutRepo)
        history.finalizer = s.finalizer
        let exercises = InMemoryExerciseRepository()
        let templates = InMemoryTemplateRepository()
        let plan = ProgressionPlanViewModel(progressionPlanRepository: InMemoryProgressionPlanRepository(),
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: s.workoutRepo), programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: s.workoutRepo), exerciseRepository: exercises, templateRepository: templates)
        let navigation = AppNavigationState()
        let start = DashboardView(navigation: navigation, viewModel: dashboard, analyticsViewModel: analytics, historyViewModel: history,
            progressionPlanViewModel: plan, exerciseListViewModel: ExerciseListViewModel(exerciseRepository: exercises),
            templateViewModel: TemplateViewModel(templateRepository: templates, exerciseRepository: exercises), userPreferencesService: prefs,
            onOpenAIChat: {}, onStartWorkout: {}, onStartSession: { _, _, _, _ in }, onHistoryTapped: {})
        let target = sameDay[0]
        let tabs = TabView(selection: Bindable(navigation).selectedTab) {
            start.tabItem { Text("Start") }.tag(0)
            NavigationStack {
                HistoryWorkoutDestination(workoutId: target.id, historyViewModel: history, analyticsViewModel: analytics)
            }.tabItem { Text("History") }.tag(1)
        }.environment(s.revision)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }
        window.rootViewController = UIHostingController(rootView: tabs)
        window.makeKeyAndVisible()
        func waitFor(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(6))
            while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            try #require(predicate())
        }
        try await waitFor { dashboard.recentWorkoutScores[target.id] != nil }
        let before = try #require(dashboard.recentWorkoutScores[target.id])
        navigation.selectedTab = 1
        try await waitFor { history.workout(for: target.id) != nil }
        history.selectWorkout(try #require(history.workout(for: target.id)))
        history.isEditing = true
        await history.updateSetWeight(exerciseId: target.exercises[0].id, setId: target.exercises[0].sets[0].id, weight: 100)
        await history.endEditing()
        navigation.selectedTab = 0
        try await waitFor { (dashboard.recentWorkoutScores[target.id]?.overallScore ?? 0) > before.overallScore }
        let rows = try await s.workoutRepo.fetchAll()
        let saved = try #require(rows.first { $0.id == target.id })
        let expected = quality.computeScore(for: saved, history: rows)
        let later = quality.computeScore(for: sameDay[1], history: rows)
        let dayIndex = (Calendar.current.component(.weekday, from: today) + 5) % 7
        #expect(dashboard.weeklyQualityScores[dayIndex] == (expected.overallScore + later.overallScore) / 2)
        #expect(dashboard.recentWorkoutScores[target.id]?.overallScore == expected.overallScore)
        navigation.dashboardPath.append(target.id)
        func showingDetail(_ controller: UIViewController?) -> Bool {
            guard let controller else { return false }
            if let stack = controller as? UINavigationController, stack.view.window != nil {
                return stack.topViewController?.navigationItem.title == target.name
            }
            return controller.children.contains { showingDetail($0) }
        }
        try await waitFor { showingDetail(window.rootViewController) }
        try await waitFor { analytics.latestSessionScore?.overallScore == later.overallScore }
        #expect(try await analytics.score(for: target).volumeScore == expected.volumeScore)
        #expect(analytics.latestSessionScore?.workoutId == sameDay[1].id)
        #expect(analytics.aggregateQuality?.ewmaOverall == quality.computeAggregateScore(workouts: rows).ewmaOverall)
        #expect(history.workout(for: target.id)?.exercises[0].sets[0].weight == 100)
        try await checkStoredVectors(s)
    }
}
