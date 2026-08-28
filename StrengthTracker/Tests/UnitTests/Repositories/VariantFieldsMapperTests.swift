import Testing
@testable import StrengthTrackerShared
import Foundation

/// equipmentBrand/loadingType are snapshotted (flattened) into workout history
/// and templates — these round-trips catch a forgotten mapper line, which would
/// compile fine but silently drop the fields at that hop.
/// Mapper tests construct entities standalone — never a second ModelContainer
/// (#Predicate on one crashes hosted tests).
@Suite("Variant Fields Mapper Tests")
struct VariantFieldsMapperTests {

    private func makeExercise() -> Exercise {
        Exercise(
            id: UUID(),
            name: "Glute Drive",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: true,
            isArchived: false,
            equipmentBrand: "Hammer Strength",
            loadingType: .plateLoaded
        )
    }

    // MARK: - ExerciseMapper

    @Test("ExerciseMapper round-trips brand and loading type")
    func exerciseMapperRoundTrip() {
        let entity = ExerciseMapper.toEntity(makeExercise())
        #expect(entity.equipmentBrand == "Hammer Strength")
        #expect(entity.loadingType == "plateLoaded")

        let domain = ExerciseMapper.toDomain(entity)
        #expect(domain.equipmentBrand == "Hammer Strength")
        #expect(domain.loadingType == .plateLoaded)
    }

    @Test("ExerciseMapper.updateEntity writes brand and loading type")
    func exerciseMapperUpdate() {
        let entity = ExerciseMapper.toEntity(makeExercise())
        var updated = makeExercise()
        updated.equipmentBrand = "Nautilus"
        updated.loadingType = .weightStack

        ExerciseMapper.updateEntity(entity, from: updated)
        #expect(entity.equipmentBrand == "Nautilus")
        #expect(entity.loadingType == "weightStack")
    }

    @Test("Unknown loadingType raw value degrades to nil, not a crash")
    func unknownLoadingTypeIsNil() {
        let entity = ExerciseMapper.toEntity(makeExercise())
        entity.loadingType = "hydraulic"
        let domain = ExerciseMapper.toDomain(entity)
        #expect(domain.loadingType == nil)
        #expect(domain.equipmentBrand == "Hammer Strength")
    }

    // MARK: - WorkoutExerciseMapper (workout-history snapshot)

    @Test("WorkoutExerciseMapper round-trips brand and loading type")
    func workoutExerciseMapperRoundTrip() {
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: []
        )

        let entity = WorkoutExerciseMapper.toEntity(workoutExercise)
        #expect(entity.equipmentBrand == "Hammer Strength")
        #expect(entity.loadingType == "plateLoaded")

        let domain = WorkoutExerciseMapper.toDomain(entity)
        #expect(domain.exercise.equipmentBrand == "Hammer Strength")
        #expect(domain.exercise.loadingType == .plateLoaded)
    }

    @Test("WorkoutExerciseMapper.updateEntity writes brand and loading type")
    func workoutExerciseMapperUpdate() {
        var workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: []
        )
        let entity = WorkoutExerciseMapper.toEntity(workoutExercise)

        workoutExercise.exercise.equipmentBrand = "Cybex"
        workoutExercise.exercise.loadingType = .weightStack
        WorkoutExerciseMapper.updateEntity(entity, from: workoutExercise)

        #expect(entity.equipmentBrand == "Cybex")
        #expect(entity.loadingType == "weightStack")
    }

    // MARK: - TemplateExerciseMapper (template snapshot)

    @Test("TemplateExerciseMapper round-trips brand and loading type")
    func templateExerciseMapperRoundTrip() {
        let templateExercise = TemplateExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            targetSets: 3,
            targetReps: 10,
            targetWeight: 100,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )

        let entity = TemplateExerciseMapper.toEntity(templateExercise)
        #expect(entity.equipmentBrand == "Hammer Strength")
        #expect(entity.loadingType == "plateLoaded")

        let domain = TemplateExerciseMapper.toDomain(entity)
        #expect(domain.exercise.equipmentBrand == "Hammer Strength")
        #expect(domain.exercise.loadingType == .plateLoaded)
    }

    @Test("TemplateExerciseMapper.updateEntity writes brand and loading type")
    func templateExerciseMapperUpdate() {
        var templateExercise = TemplateExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            targetSets: 3,
            targetReps: 10,
            targetWeight: 100,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )
        let entity = TemplateExerciseMapper.toEntity(templateExercise)

        templateExercise.exercise.equipmentBrand = "Technogym"
        templateExercise.exercise.loadingType = .weightStack
        TemplateExerciseMapper.updateEntity(entity, from: templateExercise)

        #expect(entity.equipmentBrand == "Technogym")
        #expect(entity.loadingType == "weightStack")
    }
}
