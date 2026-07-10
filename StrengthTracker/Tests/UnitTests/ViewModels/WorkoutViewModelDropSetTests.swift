import Testing
@testable import StrengthTrackerShared
import Foundation

@Suite("WorkoutViewModel Drop Sets & Failure")
@MainActor
struct WorkoutViewModelDropSetTests {

    private func makeExercise(name: String = "Lateral Raise") -> Exercise {
        Exercise(
            id: UUID(), name: name, primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [], category: .dumbbell,
            exerciseType: .weightedReps, instructions: nil, isCustom: false, isArchived: false
        )
    }

    private func makeViewModel() -> WorkoutViewModel {
        WorkoutViewModel(
            workoutRepository: InMemoryWorkoutRepository(),
            templateRepository: InMemoryTemplateRepository(),
            healthKitService: NoOpHealthKitService()
        )
    }

    /// Starts a workout with one exercise and one set; returns (vm, exerciseId, setId).
    private func makeActiveWorkoutWithSet() async -> (WorkoutViewModel, UUID, UUID) {
        let vm = makeViewModel()
        await vm.startWorkout(name: "Test")
        vm.addExercise(makeExercise())
        let exerciseId = vm.currentWorkout!.exercises[0].id
        await vm.addEmptySet(exerciseId: exerciseId)
        let setId = vm.currentWorkout!.exercises[0].sets[0].id
        return (vm, exerciseId, setId)
    }

    private func set(_ vm: WorkoutViewModel) -> ExerciseSet {
        vm.currentWorkout!.exercises[0].sets[0]
    }

    @Test("addDropEntry converts a set: values move to segment a, empty segment b appended")
    func testConvertToDropSet() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: 8)
        await vm.updateSetIntensity(exerciseId: exerciseId, setId: setId, value: 8, metric: .rpe)

        await vm.addDropEntry(exerciseId: exerciseId, setId: setId)

        let s = set(vm)
        #expect(s.setType == .dropset)
        #expect(s.dropSets.count == 2)
        #expect(s.dropSets[0].weight == 100)
        #expect(s.dropSets[0].reps == 8)
        #expect(s.dropSets[0].rpe == 8)
        #expect(s.dropSets[0].rir == 2)
        #expect(s.dropSets[1].weight == nil)
        #expect(s.dropSets[1].reps == nil)
        // Parent mirrors the top segment.
        #expect(s.weight == 100)
        #expect(s.reps == 8)
    }

    @Test("subsequent addDropEntry appends one more segment")
    func testAppendSegment() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.addDropEntry(exerciseId: exerciseId, setId: setId)
        await vm.addDropEntry(exerciseId: exerciseId, setId: setId)

        #expect(set(vm).dropSets.count == 3)
    }

    @Test("segment edits update the entry and maintain the parent mirror")
    func testSegmentEditsMaintainMirror() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: 8)
        await vm.addDropEntry(exerciseId: exerciseId, setId: setId)

        let topId = set(vm).dropSets[0].id
        let secondId = set(vm).dropSets[1].id
        await vm.updateDropEntryWeight(exerciseId: exerciseId, setId: setId, entryId: secondId, weight: 60)
        await vm.updateDropEntryReps(exerciseId: exerciseId, setId: setId, entryId: secondId, reps: 12)
        await vm.updateDropEntryWeight(exerciseId: exerciseId, setId: setId, entryId: topId, weight: 105)

        let s = set(vm)
        #expect(s.dropSets[1].weight == 60)
        #expect(s.dropSets[1].reps == 12)
        // Editing the top segment re-mirrors the parent.
        #expect(s.weight == 105)
    }

    @Test("removing down to one segment collapses back to a plain set with the survivor's values")
    func testRemoveCollapsesToPlainSet() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: 8)
        await vm.addDropEntry(exerciseId: exerciseId, setId: setId)

        let secondId = set(vm).dropSets[1].id
        await vm.updateDropEntryWeight(exerciseId: exerciseId, setId: setId, entryId: secondId, weight: 60)
        await vm.updateDropEntryReps(exerciseId: exerciseId, setId: setId, entryId: secondId, reps: 12)

        // Remove the ORIGINAL top segment — the survivor is the 60×12 segment.
        let topId = set(vm).dropSets[0].id
        await vm.removeDropEntry(exerciseId: exerciseId, setId: setId, entryId: topId)

        let s = set(vm)
        #expect(s.dropSets.isEmpty)
        #expect(s.setType == .normal)
        #expect(s.weight == 60)
        #expect(s.reps == 12)
    }

    @Test("toggleSetFailure defaults RIR 0 / RPE 10 only when no intensity is recorded")
    func testFailureDefaultsOneWay() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()

        await vm.toggleSetFailure(exerciseId: exerciseId, setId: setId)
        var s = set(vm)
        #expect(s.isFailure == true)
        #expect(s.rir == 0)
        #expect(s.rpe == 10)

        // Toggling off keeps intensity.
        await vm.toggleSetFailure(exerciseId: exerciseId, setId: setId)
        s = set(vm)
        #expect(s.isFailure == false)
        #expect(s.rpe == 10)

        // A preset intensity is never overwritten by the failure default.
        await vm.updateSetIntensity(exerciseId: exerciseId, setId: setId, value: 8, metric: .rpe)
        await vm.toggleSetFailure(exerciseId: exerciseId, setId: setId)
        s = set(vm)
        #expect(s.isFailure == true)
        #expect(s.rpe == 8)
        #expect(s.rir == 2)
    }

    @Test("legacy failure-typed sets normalize to normal + flag on first toggle")
    func testLegacyFailureNormalization() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()
        await vm.updateSetType(exerciseId: exerciseId, setId: setId, setType: .failure)
        #expect(set(vm).setType == .failure)

        // The badge toggle reads as ON for legacy rows; toggling turns failure OFF
        // and normalizes the type.
        await vm.toggleSetFailure(exerciseId: exerciseId, setId: setId)
        let s = set(vm)
        #expect(s.setType == .normal)
        #expect(s.isFailure == false)
    }

    @Test("updateSetIntensity co-stores both metrics; nil clears both")
    func testIntensityCoStorage() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()

        await vm.updateSetIntensity(exerciseId: exerciseId, setId: setId, value: 1, metric: .rir)
        var s = set(vm)
        #expect(s.rir == 1)
        #expect(s.rpe == 9)

        await vm.updateSetIntensity(exerciseId: exerciseId, setId: setId, value: nil, metric: .rir)
        s = set(vm)
        #expect(s.rir == nil)
        #expect(s.rpe == nil)
    }

    @Test("updateSetType and parent weight edits are no-ops for grouped drop sets")
    func testGroupedDropSetGuards() async {
        let (vm, exerciseId, setId) = await makeActiveWorkoutWithSet()
        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 100)
        await vm.addDropEntry(exerciseId: exerciseId, setId: setId)

        await vm.updateSetType(exerciseId: exerciseId, setId: setId, setType: .warmup)
        #expect(set(vm).setType == .dropset)

        await vm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: 55)
        #expect(set(vm).weight == 100)  // mirror untouched; segments own the values
    }
}

@Suite("HistoryViewModel Drop Set Progression")
@MainActor
struct HistoryViewModelDropSetTests {

    @Test("exerciseProgression emits one chart point per performed segment")
    func testProgressionPerSegment() {
        let vm = HistoryViewModel(workoutRepository: InMemoryWorkoutRepository())
        let exercise = AnalyticsTestHelpers.makeExercise(name: "Cable Fly")

        let normal = AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 100, reps: 8)
        let drop = AnalyticsTestHelpers.makeDropSet(order: 2, parts: [(50, 10), (40, 8)])
        let we = AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: [normal, drop])
        vm.workouts = [AnalyticsTestHelpers.makeWorkout(exercises: [we])]

        let points = vm.exerciseProgression(for: exercise.id)
        #expect(points.count == 3)
        #expect(Set(points.map(\.weight)) == [100, 50, 40])
        #expect(points.map(\.reps).reduce(0, +) == 26)
    }
}
