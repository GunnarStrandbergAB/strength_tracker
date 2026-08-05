import Testing
@testable import StrengthTrackerShared
import Foundation

/// Mapper tests construct entities standalone — never a second ModelContainer
/// (#Predicate on one crashes hosted tests).
@Suite("ExerciseSetMapper Tests")
struct ExerciseSetMapperTests {

    private func makeEntity(
        setType: String = "normal",
        isFailure: Bool = false,
        dropSetsJSON: String? = nil
    ) -> ExerciseSetEntity {
        ExerciseSetEntity(
            id: UUID(),
            order: 1,
            setType: setType,
            weight: 80,
            reps: 8,
            rpe: 8,
            isCompleted: true,
            isPersonalRecord: false,
            isFailure: isFailure,
            completedAt: Date(),
            dropSetsJSON: dropSetsJSON
        )
    }

    @Test("legacy failure-typed row maps to isFailure on read")
    func testLegacyFailureReadRule() {
        let entity = makeEntity(setType: "failure", isFailure: false)
        let domain = ExerciseSetMapper.toDomain(entity)
        #expect(domain.isFailure == true)
        #expect(domain.setType == .failure)
    }

    @Test("modern isFailure flag maps through independent of type")
    func testModernFailureFlag() {
        let entity = makeEntity(setType: "normal", isFailure: true)
        let domain = ExerciseSetMapper.toDomain(entity)
        #expect(domain.isFailure == true)
        #expect(domain.setType == .normal)
    }

    @Test("empty dropSets encode as nil JSON")
    func testEmptyDropSetsEncodeNil() {
        let domain = ExerciseSet(
            id: UUID(), order: 1, setType: .normal,
            weight: 80, reps: 8,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        let entity = ExerciseSetMapper.toEntity(domain)
        #expect(entity.dropSetsJSON == nil)
    }

    @Test("entity roundtrip preserves rir, isFailure, and drop segments")
    func testEntityRoundtrip() {
        var domain = ExerciseSet(
            id: UUID(), order: 1, setType: .normal,
            weight: nil, reps: nil,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            rir: nil,
            isCompleted: true, isPersonalRecord: false,
            completedAt: Date()
        )
        domain.applyDropSets([
            DropSetEntry(weight: 100, reps: 8, rpe: 9, rir: 1, isFailure: false),
            DropSetEntry(weight: 80, reps: 6, rpe: 10, rir: 0, isFailure: true),
        ])

        let entity = ExerciseSetMapper.toEntity(domain)
        #expect(entity.dropSetsJSON != nil)
        #expect(entity.rir == 1)   // mirrored top segment

        let restored = ExerciseSetMapper.toDomain(entity)
        #expect(restored.dropSets == domain.dropSets)
        #expect(restored.isFailure == domain.isFailure)
        #expect(restored.rir == domain.rir)
        #expect(restored.setVolume == 1280.0)
    }

    @Test("corrupt dropSetsJSON decodes to an empty array without crashing")
    func testCorruptJSONDecodesEmpty() {
        let entity = makeEntity(dropSetsJSON: "not valid json {")
        let domain = ExerciseSetMapper.toDomain(entity)
        #expect(domain.dropSets.isEmpty)
        // Falls back to legacy single-row volume.
        #expect(domain.setVolume == 640.0)
    }

    @Test("updateEntity writes the new fields onto an existing entity")
    func testUpdateEntityWritesNewFields() {
        let entity = makeEntity()
        var domain = ExerciseSetMapper.toDomain(entity)
        // For grouped drop sets the parent mirrors the top segment, so intensity and
        // failure are carried by the segment itself.
        domain.applyDropSets([DropSetEntry(weight: 60, reps: 10, rpe: 10, rir: 0, isFailure: true)])

        ExerciseSetMapper.updateEntity(entity, from: domain)
        #expect(entity.isFailure == true)
        #expect(entity.rir == 0)
        #expect(entity.dropSetsJSON != nil)
        #expect(entity.setType == SetType.dropset.rawValue)
    }
}
