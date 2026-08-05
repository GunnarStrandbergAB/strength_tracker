import Testing
@testable import StrengthTrackerShared
import Foundation

@Suite("Drop Set Model Tests")
struct DropSetModelTests {

    /// A completed set converted into a grouped drop set via the canonical mutation path.
    private func makeDropSet(
        parts: [(weight: Double?, reps: Int?)],
        isCompleted: Bool = true
    ) -> ExerciseSet {
        var set = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: nil, reps: nil,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: isCompleted, isPersonalRecord: false,
            completedAt: isCompleted ? Date() : nil
        )
        set.applyDropSets(parts.map { DropSetEntry(weight: $0.weight, reps: $0.reps) })
        return set
    }

    private func makeExercise(exerciseType: ExerciseType = .weightedReps) -> Exercise {
        Exercise(
            id: UUID(), name: "Test", primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [], category: .barbell,
            exerciseType: exerciseType, instructions: nil, isCustom: false, isArchived: false
        )
    }

    // MARK: - Volume

    @Test("grouped drop set volume sums every segment (spec example: 290 kg)")
    func testDropSetVolumeSpecExample() {
        let set = makeDropSet(parts: [(14, 12), (10, 8), (7, 6)])
        #expect(set.setVolume == 290.0)
    }

    @Test("drop set volume never double-counts the mirrored parent fields")
    func testNoDoubleCountOfParentMirror() {
        let set = makeDropSet(parts: [(100, 8), (80, 6), (60, 5)])
        // Parent mirrors the top segment...
        #expect(set.weight == 100.0)
        #expect(set.reps == 8)
        // ...but volume is the segment sum only: 800 + 480 + 300.
        #expect(set.setVolume == 1580.0)
    }

    @Test("drop set volume ignores stale parent fields when constructed directly")
    func testVolumeIgnoresStaleParentFields() {
        // Bypass applyDropSets to simulate inconsistent parent values.
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .dropset,
            weight: 999, reps: 99,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date(),
            dropSets: [DropSetEntry(weight: 50, reps: 10), DropSetEntry(weight: 40, reps: 8)]
        )
        #expect(set.setVolume == 820.0)
    }

    @Test("incomplete drop set volume is 0")
    func testIncompleteDropSetVolume() {
        let set = makeDropSet(parts: [(100, 8), (80, 6)], isCompleted: false)
        #expect(set.setVolume == 0.0)
    }

    @Test("warmup-typed set with drop entries has 0 volume (defense-in-depth)")
    func testWarmupDropSetVolume() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .warmup,
            weight: 100, reps: 8,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date(),
            dropSets: [DropSetEntry(weight: 100, reps: 8)]
        )
        #expect(set.setVolume == 0.0)
    }

    @Test("legacy single-row dropset keeps weight × reps")
    func testLegacySingleRowDropset() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .dropset,
            weight: 80, reps: 12,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.dropSets.isEmpty)
        #expect(set.isDropSet)
        #expect(set.setVolume == 960.0)
    }

    @Test("weightSubstitute fills nil-weight segments only")
    func testWeightSubstitutePerSegment() {
        let set = makeDropSet(parts: [(nil, 12), (20, 10)])
        // 70×12 + 20×10
        #expect(set.setVolume(weightSubstitute: 70) == 1040.0)
        // Without a substitute, the nil-weight segment contributes 0.
        #expect(set.setVolume == 200.0)
    }

    // MARK: - Parts & Reps

    @Test("effectiveParts for a plain set is one part mirroring the set (same id)")
    func testEffectivePartsPlainSet() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 80, reps: 10,
            durationSeconds: nil, distanceMeters: nil, rpe: 8,
            rir: 2,
            isCompleted: true, isPersonalRecord: false,
            isFailure: true,
            completedAt: Date()
        )
        let parts = set.effectiveParts
        #expect(parts.count == 1)
        #expect(parts[0].id == set.id)
        #expect(parts[0].weight == 80)
        #expect(parts[0].reps == 10)
        #expect(parts[0].rpe == 8)
        #expect(parts[0].rir == 2)
        #expect(parts[0].isFailure == true)
    }

    @Test("effectiveParts for a grouped drop set returns segments in order")
    func testEffectivePartsGrouped() {
        let set = makeDropSet(parts: [(100, 8), (80, 6), (60, 5)])
        let parts = set.effectiveParts
        #expect(parts.count == 3)
        #expect(parts.map(\.weight) == [100, 80, 60])
        #expect(parts.map(\.reps) == [8, 6, 5])
    }

    @Test("totalReps sums segments; nil reps contribute 0")
    func testTotalReps() {
        #expect(makeDropSet(parts: [(100, 8), (80, 6), (60, 5)]).totalReps == 19)
        #expect(makeDropSet(parts: [(100, 8), (80, nil)]).totalReps == 8)

        let plain = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 80, reps: 10,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(plain.totalReps == 10)
    }

    // MARK: - applyDropSets Invariants

    @Test("applyDropSets sets type, mirrors first entry, and reverts on empty")
    func testApplyDropSetsInvariants() {
        var set = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 100, reps: 8,
            durationSeconds: nil, distanceMeters: nil, rpe: 8,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        set.applyDropSets([
            DropSetEntry(weight: 60, reps: 12, rpe: 10, rir: 0, isFailure: true),
            DropSetEntry(weight: 40, reps: 9),
        ])
        #expect(set.setType == .dropset)
        #expect(set.weight == 60)
        #expect(set.reps == 12)
        #expect(set.rpe == 10)
        #expect(set.rir == 0)
        #expect(set.isFailure == true)

        set.applyDropSets([])
        #expect(set.dropSets.isEmpty)
        #expect(set.setType == .normal)
    }

    @Test("applyDropSets converts a warmup into a dropset (drops make it a working set)")
    func testApplyDropSetsOnWarmup() {
        var set = ExerciseSet(
            id: UUID(), order: 0, setType: .warmup,
            weight: 40, reps: 12,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        set.applyDropSets([DropSetEntry(weight: 40, reps: 12)])
        #expect(set.setType == .dropset)
        #expect(set.setVolume == 480.0)
    }

    // MARK: - Exercise / Workout Aggregation

    @Test("exerciseVolume and totalVolume include drop segments across mixed sets")
    func testMixedExerciseAndWorkoutVolume() {
        let normal = ExerciseSet(
            id: UUID(), order: 1, setType: .normal,
            weight: 100, reps: 8,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        let drop = makeDropSet(parts: [(14, 12), (10, 8), (7, 6)])
        let warmup = ExerciseSet(
            id: UUID(), order: 3, setType: .warmup,
            weight: 40, reps: 10,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        let we = WorkoutExercise(
            id: UUID(), exercise: makeExercise(), order: 1,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [normal, drop, warmup]
        )
        // 800 + 290 + 0 (warmup)
        #expect(we.exerciseVolume == 1090.0)

        let workout = Workout(
            id: UUID(), name: "Mixed", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        )
        #expect(workout.totalVolume == 1090.0)
    }

    @Test("totalVolume(bodyWeightKg:) substitutes body weight for nil-weight drop segments of bodyweight exercises")
    func testBodyweightSubstitutionForDropSegments() {
        let drop = makeDropSet(parts: [(nil, 12), (20, 8)])
        let we = WorkoutExercise(
            id: UUID(), exercise: makeExercise(exerciseType: .bodyweightReps), order: 1,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [drop]
        )
        let workout = Workout(
            id: UUID(), name: "BW", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        )
        // 70×12 + 20×8 = 840 + 160
        #expect(workout.totalVolume(bodyWeightKg: 70) == 1000.0)
        // Non-bodyweight exercise gets no substitution for the same sets.
        #expect(we.exerciseVolume == 160.0)
    }
}

@Suite("ExerciseSet Codable Back-Compat Tests")
struct ExerciseSetCodableTests {

    @Test("legacy JSON without new keys decodes with safe defaults")
    func testLegacyJSONDecodes() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "order": 1,
            "setType": "normal",
            "weight": 80,
            "reps": 8,
            "rpe": 8,
            "isCompleted": true,
            "isPersonalRecord": false
        }
        """
        let set = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(set.rir == nil)
        #expect(set.isFailure == false)
        #expect(set.dropSets.isEmpty)
        #expect(set.setVolume == 640.0)
    }

    @Test("legacy failure-typed JSON carries the per-set flag")
    func testLegacyFailureTypeMapsToFlag() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "order": 1,
            "setType": "failure",
            "weight": 80,
            "reps": 8,
            "isCompleted": true,
            "isPersonalRecord": false
        }
        """
        let set = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(set.isFailure == true)
    }

    @Test("explicit isFailure false wins over a failure set type")
    func testExplicitFlagWinsOverType() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "order": 1,
            "setType": "failure",
            "isFailure": false,
            "isCompleted": true,
            "isPersonalRecord": false
        }
        """
        let set = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(set.isFailure == false)
    }

    @Test("full roundtrip preserves rir, isFailure, and drop segments")
    func testFullRoundtrip() throws {
        var original = ExerciseSet(
            id: UUID(), order: 2, setType: .normal,
            weight: nil, reps: nil,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            rir: nil,
            isCompleted: true, isPersonalRecord: false,
            completedAt: nil
        )
        original.applyDropSets([
            DropSetEntry(weight: 14, reps: 12, rpe: 10, rir: 0, isFailure: true),
            DropSetEntry(weight: 10, reps: 8, rpe: 10, rir: 0, isFailure: true),
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: data)

        #expect(decoded == original)
        #expect(decoded.dropSets.count == 2)
        #expect(decoded.dropSets[0].isFailure == true)
        #expect(decoded.dropSets[0].rir == 0)
        #expect(decoded.setVolume == 248.0)
    }
}
