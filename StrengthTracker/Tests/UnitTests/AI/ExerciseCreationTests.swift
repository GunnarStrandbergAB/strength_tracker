import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("ExerciseFactory")
struct ExerciseFactoryTests {

    @Test("Empty names throw")
    func emptyName() {
        #expect(throws: ExerciseValidationError.emptyName) {
            _ = try ExerciseFactory.makeCustom(
                name: "   ", primaryMuscleGroup: .chest,
                category: .barbell, exerciseType: .weightedReps
            )
        }
    }

    @Test("Brand only applies to machine, cable, and smith machine")
    func brandGating() throws {
        let machine = try ExerciseFactory.makeCustom(
            name: "Chest Press", primaryMuscleGroup: .chest,
            category: .machine, exerciseType: .weightedReps,
            equipmentBrand: "  Hammer Strength  "
        )
        #expect(machine.equipmentBrand == "Hammer Strength")

        let barbell = try ExerciseFactory.makeCustom(
            name: "Bench Press", primaryMuscleGroup: .chest,
            category: .barbell, exerciseType: .weightedReps,
            equipmentBrand: "Hammer Strength"
        )
        #expect(barbell.equipmentBrand == nil)

        let emptyBrand = try ExerciseFactory.makeCustom(
            name: "Cable Row", primaryMuscleGroup: .back,
            category: .cable, exerciseType: .weightedReps,
            equipmentBrand: "   "
        )
        #expect(emptyBrand.equipmentBrand == nil)
    }

    @Test("Loading type only applies to machines")
    func loadingTypeGating() throws {
        let machine = try ExerciseFactory.makeCustom(
            name: "Leg Press", primaryMuscleGroup: .quadriceps,
            category: .machine, exerciseType: .weightedReps,
            loadingType: .plateLoaded
        )
        #expect(machine.loadingType == .plateLoaded)

        let cable = try ExerciseFactory.makeCustom(
            name: "Lat Pulldown", primaryMuscleGroup: .lats,
            category: .cable, exerciseType: .weightedReps,
            loadingType: .plateLoaded
        )
        #expect(cable.loadingType == nil)
    }

    @Test("Bodyweight factor only applies to bodyweight reps and clamps to 0.1…1.5")
    func bodyweightFactor() throws {
        let pullUp = try ExerciseFactory.makeCustom(
            name: "Pull-Up X", primaryMuscleGroup: .back,
            category: .bodyweight, exerciseType: .bodyweightReps,
            bodyweightPercent: 95
        )
        #expect(pullUp.bodyweightFactor == 0.95)

        let clampedHigh = try ExerciseFactory.makeCustom(
            name: "Weighted Dip X", primaryMuscleGroup: .triceps,
            category: .bodyweight, exerciseType: .bodyweightReps,
            bodyweightPercent: 400
        )
        #expect(clampedHigh.bodyweightFactor == 1.5)

        let clampedLow = try ExerciseFactory.makeCustom(
            name: "Assisted X", primaryMuscleGroup: .back,
            category: .bodyweight, exerciseType: .bodyweightReps,
            bodyweightPercent: 1
        )
        #expect(clampedLow.bodyweightFactor == 0.1)

        let weighted = try ExerciseFactory.makeCustom(
            name: "Bench X", primaryMuscleGroup: .chest,
            category: .barbell, exerciseType: .weightedReps,
            bodyweightPercent: 95
        )
        #expect(weighted.bodyweightFactor == nil)
    }

    @Test("Primary muscle group is removed from secondaries; isCustom is set")
    func secondaryDeduplication() throws {
        let exercise = try ExerciseFactory.makeCustom(
            name: "Incline Press", primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.chest, .shoulders, .triceps],
            category: .dumbbell, exerciseType: .weightedReps
        )
        #expect(exercise.secondaryMuscleGroups == [.shoulders, .triceps])
        #expect(exercise.isCustom)
    }
}

@Suite("TemplateExerciseFactory")
struct TemplateExerciseFactoryTests {

    private func makeExercise(type: ExerciseType) -> Exercise {
        Exercise(
            id: UUID(), name: "X", primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [], category: .barbell,
            exerciseType: type, instructions: nil, isCustom: false, isArchived: false
        )
    }

    @Test("Defaults match the template editor: 3 sets, default reps, 0 kg for weighted reps")
    func weightedRepsDefaults() {
        let templateExercise = TemplateExerciseFactory.make(
            exercise: makeExercise(type: .weightedReps), order: 0, defaultReps: 10
        )
        #expect(templateExercise.targetSets == 3)
        #expect(templateExercise.targetReps == 10)
        #expect(templateExercise.targetWeight == 0)
        #expect(templateExercise.targetDurationSeconds == nil)
        #expect(templateExercise.targetDistanceMeters == nil)
        #expect(templateExercise.setTargets.isEmpty)
    }

    @Test("Duration gets 60 s; cardio gets 1000 m; neither gets reps or weight")
    func typeDefaults() {
        let duration = TemplateExerciseFactory.make(
            exercise: makeExercise(type: .duration), order: 0, defaultReps: 10
        )
        #expect(duration.targetDurationSeconds == 60)
        #expect(duration.targetReps == nil)
        #expect(duration.targetWeight == nil)

        let cardio = TemplateExerciseFactory.make(
            exercise: makeExercise(type: .cardio), order: 0, defaultReps: 10
        )
        #expect(cardio.targetDistanceMeters == 1000)
        #expect(cardio.targetReps == nil)
    }

    @Test("Overrides win over defaults")
    func overrides() {
        let templateExercise = TemplateExerciseFactory.make(
            exercise: makeExercise(type: .weightedReps), order: 2, defaultReps: 10,
            targetSets: 5, targetReps: 8, targetWeightKg: 80,
            restSeconds: 120, supersetGroup: 1, isWarmUp: true
        )
        #expect(templateExercise.targetSets == 5)
        #expect(templateExercise.targetReps == 8)
        #expect(templateExercise.targetWeight == 80)
        #expect(templateExercise.restTimerSeconds == 120)
        #expect(templateExercise.supersetGroup == 1)
        #expect(templateExercise.isWarmUp)
        #expect(templateExercise.order == 2)
    }
}
