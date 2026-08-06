import Testing
@testable import StrengthTrackerShared
import Foundation

@Suite("HistoryViewModel Retro Logging")
@MainActor
struct HistoryViewModelRetroTests {

    private let twoWeeksAgo = Date().addingTimeInterval(-14 * 86_400)

    private func makeExercise(name: String = "Ring Dip") -> Exercise {
        AnalyticsTestHelpers.makeExercise(name: name, primaryMuscleGroup: .chest, secondaryMuscleGroups: [])
    }

    /// Full stack sharing one workout repository so finalization services see the
    /// same data the view model writes.
    private func makeStack() -> (
        vm: HistoryViewModel,
        workoutRepo: InMemoryWorkoutRepository,
        prRepo: InMemoryPersonalRecordRepository,
        analyticsRepo: MockAnalyticsRepository,
        healthKit: MockHealthKitService
    ) {
        let workoutRepo = InMemoryWorkoutRepository()
        let prRepo = InMemoryPersonalRecordRepository()
        let analyticsRepo = MockAnalyticsRepository()
        let healthKit = MockHealthKitService()
        let analyticsService = WorkoutAnalyticsService(
            analyticsRepository: analyticsRepo,
            workoutRepository: workoutRepo,
            exerciseRepository: InMemoryExerciseRepository(),
            vectorizer: WorkoutVectorizer(),
            searchService: VectorSearchService(),
            plateauService: PlateauDetectionService(),
            muscleBalanceService: MuscleBalanceService(),
            recommendationService: ExerciseRecommendationService()
        )
        let prService = PersonalRecordService(
            personalRecordRepository: prRepo,
            workoutRepository: workoutRepo
        )
        let vm = HistoryViewModel(
            workoutRepository: workoutRepo,
            analyticsService: analyticsService,
            personalRecordService: prService,
            healthKitService: healthKit,
            calorieEstimationService: CalorieEstimationService()
        )
        return (vm, workoutRepo, prRepo, analyticsRepo, healthKit)
    }

    // MARK: - Creation

    @Test("retro workout is born complete with duration-derived completedAt")
    func testBornComplete() async throws {
        let (vm, repo, _, _, _) = makeStack()
        let workout = await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        )
        let created = try #require(workout)
        #expect(created.completedAt == twoWeeksAgo.addingTimeInterval(3600))
        #expect(created.isInProgress == false)
        #expect(vm.isEditing == true)
        #expect(vm.selectedWorkout?.id == created.id)

        // Persisted as completed — invisible to the active-workout machinery.
        let active = try await repo.fetchActive()
        #expect(active == nil)
    }

    @Test("completedAt is clamped so it never lands in the future")
    func testFutureClamp() async throws {
        let (vm, _, _, _, _) = makeStack()
        let thirtyMinAgo = Date().addingTimeInterval(-1800)
        let workout = await vm.createRetroWorkout(
            name: "Now-ish", startedAt: thirtyMinAgo, duration: 3600, saveToHealthKit: false
        )
        let created = try #require(workout)
        #expect(created.completedAt! <= Date())
    }

    @Test("future startedAt is rejected")
    func testFutureStartRejected() async {
        let (vm, _, _, _, _) = makeStack()
        let workout = await vm.createRetroWorkout(
            name: "Tomorrow", startedAt: Date().addingTimeInterval(3600), duration: 3600, saveToHealthKit: false
        )
        #expect(workout == nil)
    }

    @Test("retro workout inserts at its sorted position in the history list")
    func testSortedInsert() async throws {
        let (vm, repo, _, _, _) = makeStack()
        let newer = AnalyticsTestHelpers.makeWorkout(
            name: "Yesterday", startedAt: Date().addingTimeInterval(-86_400)
        )
        let older = AnalyticsTestHelpers.makeWorkout(
            name: "Last month", startedAt: Date().addingTimeInterval(-30 * 86_400)
        )
        _ = try await repo.save(newer)
        _ = try await repo.save(older)
        await vm.loadHistory()

        _ = await vm.createRetroWorkout(
            name: "Two weeks ago", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        )
        #expect(vm.workouts.map(\.name) == ["Yesterday", "Two weeks ago", "Last month"])
    }

    // MARK: - Composition

    @Test("addExercise persists to the repository, removeExercise renumbers")
    func testAddRemoveExercise() async throws {
        let (vm, repo, _, _, _) = makeStack()
        let created = try #require(await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        ))
        await vm.addExercise(makeExercise(name: "Ring Dip"))
        await vm.addExercise(makeExercise(name: "Ring Row"))

        let persisted = try #require(try await repo.fetchAll().first { $0.id == created.id })
        #expect(persisted.exercises.map(\.exercise.name) == ["Ring Dip", "Ring Row"])
        #expect(persisted.exercises.map(\.order) == [1, 2])

        let firstId = persisted.exercises[0].id
        await vm.removeExercise(exerciseId: firstId)
        let after = try #require(try await repo.fetchAll().first { $0.id == created.id })
        #expect(after.exercises.map(\.exercise.name) == ["Ring Row"])
        #expect(after.exercises.map(\.order) == [1])
    }

    @Test("set completion stamps the workout's own window, not now")
    func testSetCompletionStampsWorkoutWindow() async throws {
        let (vm, _, _, _, _) = makeStack()
        let created = try #require(await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        ))
        await vm.addExercise(makeExercise())
        let exerciseId = vm.selectedWorkout!.exercises[0].id
        await vm.addEmptySet(exerciseId: exerciseId)
        let setId = vm.selectedWorkout!.exercises[0].sets[0].id

        await vm.toggleSetCompletion(exerciseId: exerciseId, setId: setId)
        let stamped = vm.selectedWorkout!.exercises[0].sets[0]
        #expect(stamped.isCompleted)
        #expect(stamped.completedAt == created.completedAt)
    }

    @Test("markAllSetsComplete completes only incomplete sets inside the window")
    func testMarkAllSetsComplete() async throws {
        let (vm, _, _, _, _) = makeStack()
        let created = try #require(await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        ))
        await vm.addExercise(makeExercise())
        let exerciseId = vm.selectedWorkout!.exercises[0].id
        await vm.addEmptySet(exerciseId: exerciseId)
        await vm.addEmptySet(exerciseId: exerciseId)
        let firstSetId = vm.selectedWorkout!.exercises[0].sets[0].id
        await vm.toggleSetCompletion(exerciseId: exerciseId, setId: firstSetId)

        await vm.markAllSetsComplete()
        let sets = vm.selectedWorkout!.exercises[0].sets
        #expect(sets.allSatisfy { $0.isCompleted })
        #expect(sets.allSatisfy { $0.completedAt == created.completedAt })
    }

    // MARK: - Finalization

    @Test("endEditing vectorizes with the training date and rebuilds PRs with past achievedAt")
    func testFinalizationVectorAndPRs() async throws {
        let (vm, _, prRepo, analyticsRepo, _) = makeStack()
        let exercise = makeExercise()
        let created = try #require(await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        ))
        await vm.addExercise(exercise)
        let exerciseId = vm.selectedWorkout!.exercises[0].id
        await vm.addEmptySet(exerciseId: exerciseId)
        let setId = vm.selectedWorkout!.exercises[0].sets[0].id
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: 8)
        await vm.toggleSetCompletion(exerciseId: exerciseId, setId: setId)

        await vm.endEditing()

        #expect(vm.isEditing == false)
        let vector = try #require(analyticsRepo.storedVectors[created.id])
        #expect(vector.createdAt == created.startedAt)

        let records = try await prRepo.fetchForExercise(exercise.id)
        let maxWeight = try #require(records.first { $0.recordType == .maxWeight })
        #expect(maxWeight.value == 100)
        #expect(maxWeight.achievedAt == created.completedAt)
    }

    @Test("HealthKit save fires only when opted in, and only once")
    func testHealthKitOptInOneShot() async throws {
        let (vm, _, _, _, healthKit) = makeStack()
        _ = try #require(await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: true
        ))
        await vm.addExercise(makeExercise())
        await vm.endEditing()
        #expect(healthKit.saveWorkoutCalled == true)
        #expect(healthKit.savedWorkout?.startedAt == twoWeeksAgo)

        // Second session: edit again, finalize again — HealthKit must NOT re-fire.
        healthKit.saveWorkoutCalled = false
        vm.isEditing = true
        await vm.addExercise(makeExercise(name: "Ring Row"))
        await vm.endEditing()
        #expect(healthKit.saveWorkoutCalled == false)
    }

    @Test("HealthKit save does not fire when opted out")
    func testHealthKitOptOut() async throws {
        let (vm, _, _, _, healthKit) = makeStack()
        _ = try #require(await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        ))
        await vm.addExercise(makeExercise())
        await vm.endEditing()
        #expect(healthKit.saveWorkoutCalled == false)
    }

    @Test("a retro set worse than the current best does not displace the newer record")
    func testRetroSetDoesNotDisplaceBetterRecord() async throws {
        let (vm, repo, prRepo, _, _) = makeStack()
        let exercise = makeExercise()

        // Existing recent workout with the better set (110 kg).
        let best = AnalyticsTestHelpers.makeWorkout(
            name: "Recent",
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise(
                exercise: exercise,
                sets: [AnalyticsTestHelpers.makeCompletedSet(weight: 110, reps: 5, completedAt: Date().addingTimeInterval(-86_400))]
            )],
            startedAt: Date().addingTimeInterval(-86_400)
        )
        _ = try await repo.save(best)
        await vm.loadHistory()

        // Backdated workout with a worse set (100 kg).
        let created = try #require(await vm.createRetroWorkout(
            name: "Old", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        ))
        _ = created
        await vm.addExercise(exercise)
        let exerciseId = vm.selectedWorkout!.exercises[0].id
        await vm.addEmptySet(exerciseId: exerciseId)
        let setId = vm.selectedWorkout!.exercises[0].sets[0].id
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: 5)
        await vm.toggleSetCompletion(exerciseId: exerciseId, setId: setId)
        await vm.endEditing()

        let records = try await prRepo.fetchForExercise(exercise.id)
        let maxWeights = records.filter { $0.recordType == .maxWeight }.map(\.value)
        #expect(maxWeights == [110])
    }

    @Test("manually entered PRs survive recalculateAllPRs")
    func testManualPRSurvivesRecalc() async throws {
        let (vm, _, prRepo, _, _) = makeStack()
        let exercise = makeExercise()
        let manual = PersonalRecord(
            id: UUID(), exerciseId: exercise.id, recordType: .maxWeight,
            value: 200, setId: nil, achievedAt: Date().addingTimeInterval(-90 * 86_400)
        )
        _ = try await prRepo.save(manual)

        _ = try #require(await vm.createRetroWorkout(
            name: "Rings", startedAt: twoWeeksAgo, duration: 3600, saveToHealthKit: false
        ))
        await vm.addExercise(exercise)
        let exerciseId = vm.selectedWorkout!.exercises[0].id
        await vm.addEmptySet(exerciseId: exerciseId)
        let setId = vm.selectedWorkout!.exercises[0].sets[0].id
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: 5)
        await vm.toggleSetCompletion(exerciseId: exerciseId, setId: setId)
        await vm.endEditing()

        let records = try await prRepo.fetchForExercise(exercise.id)
        #expect(records.contains { $0.id == manual.id && $0.value == 200 })
    }
}

@Suite("PersonalRecord bestPerType")
struct PersonalRecordBestPerTypeTests {

    private func record(type: RecordType, value: Double, daysAgo: Double) -> PersonalRecord {
        PersonalRecord(
            id: UUID(), exerciseId: UUID(), recordType: type,
            value: value, setId: nil,
            achievedAt: Date().addingTimeInterval(-daysAgo * 86_400)
        )
    }

    @Test("highest value wins even with an older achievedAt")
    func testValueBeatsRecency() {
        let older = record(type: .maxWeight, value: 110, daysAgo: 14)
        let newer = record(type: .maxWeight, value: 100, daysAgo: 1)
        let best = [newer, older].bestPerType()
        #expect(best.count == 1)
        #expect(best[0].value == 110)
    }

    @Test("value ties break to the newest achievedAt")
    func testTieBreaksToNewest() {
        let older = record(type: .maxReps, value: 12, daysAgo: 14)
        let newer = record(type: .maxReps, value: 12, daysAgo: 1)
        let best = [older, newer].bestPerType()
        #expect(best.count == 1)
        #expect(best[0].id == newer.id)
    }

    @Test("one winner per record type")
    func testOnePerType() {
        let records = [
            record(type: .maxWeight, value: 100, daysAgo: 5),
            record(type: .maxWeight, value: 90, daysAgo: 1),
            record(type: .maxReps, value: 12, daysAgo: 2),
        ]
        let best = records.bestPerType()
        #expect(best.count == 2)
    }
}

@Suite("WorkoutVectorizer training date")
struct WorkoutVectorizerDateTests {

    @Test("vector createdAt carries the workout's training date, not now")
    @MainActor
    func testVectorDateIsTrainingDate() {
        let startedAt = Date().addingTimeInterval(-14 * 86_400)
        let workout = AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(3600)
        )
        let vector = WorkoutVectorizer().vectorize(workout)
        #expect(vector.createdAt == startedAt)
    }
}
