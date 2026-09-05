import Testing
import Foundation
@testable import StrengthTrackerShared

/// Live PR detection on the iOS inline path (set completion toggles and edits).
@Suite("WorkoutViewModel live PRs")
@MainActor
struct WorkoutViewModelPRTests {

    private func makeStack() -> (WorkoutViewModel, InMemoryPersonalRecordRepository) {
        let workoutRepo = InMemoryWorkoutRepository()
        let prRepo = InMemoryPersonalRecordRepository()
        let prService = PersonalRecordService(personalRecordRepository: prRepo, workoutRepository: workoutRepo)
        let vm = WorkoutViewModel(
            workoutRepository: workoutRepo,
            templateRepository: InMemoryTemplateRepository(),
            personalRecordService: prService,
            healthKitService: NoOpHealthKitService()
        )
        return (vm, prRepo)
    }

    private func makeExercise() -> Exercise {
        AnalyticsTestHelpers.makeExercise(name: "Bench Press")
    }

    @Test("completing a set flags a PR and sets lastPR; un-completing clears it and revokes the row")
    func toggleFlagsAndRevokes() async throws {
        let (vm, prRepo) = makeStack()
        let exercise = makeExercise()
        await vm.startWorkout(name: "Push")
        let added = try #require(await vm.addExercise(exercise, sets: [SetPrefill(weightKg: 100, reps: 5).makeSet(order: 1)]))
        let setId = added.sets[0].id

        await vm.toggleSetCompletion(exerciseId: added.id, setId: setId)
        #expect(vm.currentWorkout?.exercises[0].sets[0].isPersonalRecord == true)
        #expect(vm.lastPR?.exerciseId == exercise.id)
        #expect(try await prRepo.fetchForExercise(exercise.id).contains { $0.recordType == .maxWeight && $0.value == 100 })

        await vm.toggleSetCompletion(exerciseId: added.id, setId: setId)
        #expect(vm.currentWorkout?.exercises[0].sets[0].isPersonalRecord == false)
        #expect(try await prRepo.fetchForExercise(exercise.id).isEmpty, "no completed history left → no rows")
    }

    @Test("deload workouts never flag PRs")
    func deloadNeverFlags() async throws {
        let (vm, prRepo) = makeStack()
        let exercise = makeExercise()
        await vm.startWorkout(name: "Deload", isDeload: true)
        let added = try #require(await vm.addExercise(exercise, sets: [SetPrefill(weightKg: 100, reps: 5).makeSet(order: 1)]))
        await vm.toggleSetCompletion(exerciseId: added.id, setId: added.sets[0].id)
        #expect(vm.currentWorkout?.exercises[0].sets[0].isPersonalRecord == false)
        #expect(try await prRepo.fetchForExercise(exercise.id).isEmpty)
    }

    @Test("editing a completed set's weight re-elects the record")
    func editReelects() async throws {
        let (vm, prRepo) = makeStack()
        let exercise = makeExercise()
        await vm.startWorkout(name: "Push")
        let added = try #require(await vm.addExercise(exercise, sets: [
            SetPrefill(weightKg: 100, reps: 5).makeSet(order: 1),
            SetPrefill(weightKg: 90, reps: 5).makeSet(order: 2)
        ]))
        await vm.toggleSetCompletion(exerciseId: added.id, setId: added.sets[0].id)
        await vm.toggleSetCompletion(exerciseId: added.id, setId: added.sets[1].id)
        #expect(vm.currentWorkout?.exercises[0].sets[0].isPersonalRecord == true)
        #expect(vm.currentWorkout?.exercises[0].sets[1].isPersonalRecord == false)

        // Set 1 was a typo: it was really 80 kg. Set 2 now holds the record.
        await vm.updateSetWeight(exerciseId: added.id, setId: added.sets[0].id, weight: 80)
        #expect(vm.currentWorkout?.exercises[0].sets[0].isPersonalRecord == false)
        #expect(vm.currentWorkout?.exercises[0].sets[1].isPersonalRecord == true)
        #expect(try await prRepo.fetchForExercise(exercise.id).first { $0.recordType == .maxWeight }?.value == 90)
    }
}
