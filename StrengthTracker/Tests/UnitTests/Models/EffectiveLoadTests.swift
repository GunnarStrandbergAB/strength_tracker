import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("Effective Load Model")
struct EffectiveLoadTests {

    private func makeExercise(
        exerciseType: ExerciseType = .bodyweightReps,
        bodyweightFactor: Double? = nil
    ) -> Exercise {
        Exercise(
            id: UUID(), name: "Test", primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [], category: .bodyweight,
            exerciseType: exerciseType, instructions: nil,
            isCustom: false, isArchived: false,
            bodyweightFactor: bodyweightFactor
        )
    }

    private func makeSet(
        weight: Double? = nil,
        reps: Int? = nil,
        setType: SetType = .normal,
        isCompleted: Bool = true
    ) -> ExerciseSet {
        ExerciseSet(
            id: UUID(), order: 0, setType: setType,
            weight: weight, reps: reps,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: isCompleted, isPersonalRecord: false,
            completedAt: isCompleted ? Date() : nil
        )
    }

    // MARK: - baseLoadPerRep

    @Test("baseLoadPerRep multiplies body weight by the factor")
    func baseLoadWithFactor() {
        let pushUp = makeExercise(bodyweightFactor: 0.64)
        #expect(pushUp.baseLoadPerRep(bodyWeightKg: 80) == 51.2)
    }

    @Test("baseLoadPerRep falls back to factor 1.0 when nil")
    func baseLoadFallback() {
        let pullUp = makeExercise(bodyweightFactor: nil)
        #expect(pullUp.baseLoadPerRep(bodyWeightKg: 80) == 80.0)
    }

    @Test("baseLoadPerRep is nil for non-bodyweight exercise types")
    func baseLoadNonBodyweight() {
        for type in [ExerciseType.weightedReps, .duration, .cardio, .weightedCardio] {
            let exercise = makeExercise(exerciseType: type, bodyweightFactor: 0.64)
            #expect(exercise.baseLoadPerRep(bodyWeightKg: 80) == nil, "\(type) should have no base load")
        }
    }

    // MARK: - DropSetEntry.effectiveLoad

    @Test("effectiveLoad matrix: base and extra kg combine; without base weight passes through")
    func effectiveLoadMatrix() {
        let bare = DropSetEntry(weight: nil)
        let weighted = DropSetEntry(weight: 20)
        let bareWithBase: Double? = bare.effectiveLoad(baseLoadPerRep: 70)
        let weightedWithBase: Double? = weighted.effectiveLoad(baseLoadPerRep: 70)
        let weightedNoBase: Double? = weighted.effectiveLoad(baseLoadPerRep: nil)
        let bareNoBase: Double? = bare.effectiveLoad(baseLoadPerRep: nil)
        #expect(bareWithBase == 70.0)
        #expect(weightedWithBase == 90.0)
        #expect(weightedNoBase == 20.0)
        #expect(bareNoBase == nil)
    }

    // MARK: - effectiveLoadParts

    @Test("effectiveLoadParts includes nil-weight bodyweight sets (the 0-volume bug)")
    func partsIncludeNilWeightSets() {
        let set = makeSet(weight: nil, reps: 10)
        let parts = set.effectiveLoadParts(baseLoadPerRep: 51.2)
        #expect(parts.count == 1)
        #expect(parts[0].load == 51.2)
        #expect(parts[0].reps == 10)
        // Without a base, the same set contributes nothing.
        #expect(set.effectiveLoadParts(baseLoadPerRep: nil).isEmpty)
    }

    @Test("effectiveLoadParts covers every drop segment with base added to each")
    func partsCoverDropSegments() {
        var set = makeSet(weight: nil, reps: nil)
        set.applyDropSets([
            DropSetEntry(weight: 20, reps: 5),
            DropSetEntry(weight: 10, reps: 4),
            DropSetEntry(weight: nil, reps: 6),
        ])
        let parts = set.effectiveLoadParts(baseLoadPerRep: 80)
        let loads: [Double] = parts.map(\.load)
        let reps: [Int] = parts.map(\.reps)
        #expect(loads == [100.0, 90.0, 80.0])
        #expect(reps == [5, 4, 6])
    }

    // MARK: - Volume

    @Test("bodyweight set volume = bw × factor × reps (80 kg × 0.64 × 10 = 512)")
    func bodyweightSetVolume() {
        let set = makeSet(weight: nil, reps: 10)
        #expect(set.setVolume(baseLoadPerRep: 80 * 0.64) == 512.0)
    }

    @Test("weighted pull-up regression lock: +20 kg at 80 kg bw is 500 volume for 5 reps, not 100")
    func weightedPullUpVolume() {
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: 20, reps: 5)
        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        #expect(we.exerciseVolume(bodyWeightKg: 80) == 500.0)
    }

    @Test("duration-type exercises keep 0 volume")
    func durationKeepsZeroVolume() {
        let plank = makeExercise(exerciseType: .duration)
        var set = makeSet(weight: nil, reps: nil)
        set.durationSeconds = 60
        let we = WorkoutExercise(
            id: UUID(), exercise: plank, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        #expect(we.exerciseVolume(bodyWeightKg: 80) == 0.0)
    }

    // MARK: - e1RM

    @Test("effective e1RM feeds the shared formula (100 kg × 5 reps)")
    func effectiveE1RM() {
        let set = makeSet(weight: 20, reps: 5)
        let parts = set.effectiveLoadParts(baseLoadPerRep: 80)
        let e1rm = AnalyticsCalculations.calculateOneRM(weight: parts[0].load, reps: parts[0].reps)
        let expected = 100.0 * (1.0 + 5.0 / 30.0)
        #expect(abs(e1rm - expected) < 0.0001)
    }

    // MARK: - Analytics inputs

    @Test("buildBestE1RMMap includes nil-weight bodyweight sets")
    @MainActor
    func bestE1RMMapIncludesBodyweightSets() {
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: nil, reps: 5)
        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        let workout = Workout(
            id: UUID(), name: "Pull", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        )
        let map = AnalyticsCalculations.buildBestE1RMMap(from: [workout], bodyWeightKg: 80)
        let best: Double = map[pullUp.id] ?? 0
        let expected = 80.0 * (1.0 + 5.0 / 30.0)
        #expect(abs(best - expected) < 0.0001)
    }

    @Test("setIWV counts nil-weight bodyweight sets via the base load")
    func setIWVIncludesBodyweightSets() {
        let set = makeSet(weight: nil, reps: 10)
        // pct1RM = 80/100 → IWV = 10 × 0.8
        let iwv = AnalyticsCalculations.setIWV(for: set, bestE1RM: 100, baseLoadPerRep: 80)
        #expect(abs(iwv - 8.0) < 0.0001)
        // No base → part has no load → 0
        #expect(AnalyticsCalculations.setIWV(for: set, bestE1RM: 100, baseLoadPerRep: nil) == 0)
    }

    // MARK: - PR checks

    @Test("checkForPR records effective-load PRs for a nil-weight bodyweight set")
    @MainActor
    func checkForPREffective() async throws {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        let service = PersonalRecordService(
            personalRecordRepository: prRepo,
            workoutRepository: workoutRepo
        )
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: nil, reps: 5)

        let record = try await service.checkForPR(exercise: pullUp, set: set)
        // Default body weight 70 → maxWeight 70, e1RM 70×(1+5/30); e1RM is most significant.
        #expect(record?.recordType == .estimatedOneRepMax)
        let saved = try await prRepo.fetchForExercise(pullUp.id)
        let maxWeight = saved.first { $0.recordType == .maxWeight }
        #expect(maxWeight?.value == 70.0)
        let maxVolume = saved.first { $0.recordType == .maxVolume }
        #expect(maxVolume?.value == 350.0)
    }

    @Test("recalculateAllPRs replaces extra-kg-era records with effective-load values")
    @MainActor
    func recalculateReplacesExtraKgRecords() async throws {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        let service = PersonalRecordService(
            personalRecordRepository: prRepo,
            workoutRepository: workoutRepo
        )
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: 20, reps: 5)

        // Extra-kg-era record: maxWeight 20 from the same set.
        _ = try await prRepo.save(PersonalRecord(
            id: UUID(), exerciseId: pullUp.id, recordType: .maxWeight,
            value: 20.0, setId: set.id, achievedAt: Date()
        ))

        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        _ = try await workoutRepo.save(Workout(
            id: UUID(), name: "Pull", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        ))

        try await service.recalculateAllPRs()

        let records = try await prRepo.fetchForExercise(pullUp.id)
        let maxWeight = records.first { $0.recordType == .maxWeight }
        // Default body weight 70 + 20 extra = 90 effective.
        #expect(maxWeight?.value == 90.0)
        let staleRecords = records.filter { $0.recordType == .maxWeight && $0.value == 20.0 }
        #expect(staleRecords.isEmpty)
    }

    // MARK: - Progression points

    @Test("history progression points include nil-weight bodyweight sets at effective load")
    @MainActor
    func progressionPointsIncludeBodyweightSets() async {
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: nil, reps: 8)
        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        let workout = Workout(
            id: UUID(), name: "Pull", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        )
        let workoutRepo = InMemoryWorkoutRepository()
        _ = try? await workoutRepo.save(workout)

        let vm = HistoryViewModel(workoutRepository: workoutRepo)
        await vm.loadHistory()
        let points = vm.exerciseProgression(for: pullUp.id)
        #expect(points.count == 1)
        #expect(points.first?.weight == 70.0)
        #expect(points.first?.reps == 8)
    }
}
