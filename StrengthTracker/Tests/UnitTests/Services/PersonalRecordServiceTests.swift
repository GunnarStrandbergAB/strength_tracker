import Testing
@testable import StrengthTrackerShared
import Foundation

@Suite("PersonalRecordService Drop Set Tests")
@MainActor
struct PersonalRecordServiceTests {

    private func makeService() -> (PersonalRecordService, InMemoryPersonalRecordRepository, InMemoryWorkoutRepository) {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        let service = PersonalRecordService(personalRecordRepository: prRepo, workoutRepository: workoutRepo)
        return (service, prRepo, workoutRepo)
    }

    private func makeExercise() -> Exercise {
        AnalyticsTestHelpers.makeExercise(name: "Lateral Raise", primaryMuscleGroup: .shoulders, secondaryMuscleGroups: [])
    }

    private func seedRecord(_ repo: InMemoryPersonalRecordRepository, exerciseId: UUID, type: RecordType, value: Double) async throws {
        _ = try await repo.save(PersonalRecord(
            id: UUID(), exerciseId: exerciseId, recordType: type,
            value: value, setId: nil, achievedAt: Date().addingTimeInterval(-86_400)
        ))
    }

    private func records(_ repo: InMemoryPersonalRecordRepository, _ exerciseId: UUID, _ type: RecordType) async throws -> [Double] {
        try await repo.fetchForExercise(exerciseId).filter { $0.recordType == type }.map(\.value)
    }

    @Test("top drop segment sets a max-weight PR")
    func testDropSegmentMaxWeightPR() async throws {
        let (service, prRepo, _) = makeService()
        let exercise = makeExercise()
        try await seedRecord(prRepo, exerciseId: exercise.id, type: .maxWeight, value: 90)

        let set = AnalyticsTestHelpers.makeDropSet(parts: [(100, 8), (80, 6)])
        _ = try await service.checkForPR(exercise: exercise, set: set)

        let weights = try await records(prRepo, exercise.id, .maxWeight)
        #expect(weights.contains(100))
    }

    @Test("max-reps PR uses the best single segment, never the summed total")
    func testMaxRepsUsesBestSegmentNotSum() async throws {
        let (service, prRepo, _) = makeService()
        let exercise = makeExercise()
        try await seedRecord(prRepo, exerciseId: exercise.id, type: .maxReps, value: 22)

        // Segments of 5 and 20 reps: total 25 would beat 22, best segment 20 does not.
        let set = AnalyticsTestHelpers.makeDropSet(parts: [(100, 5), (40, 20)])
        _ = try await service.checkForPR(exercise: exercise, set: set)

        let reps = try await records(prRepo, exercise.id, .maxReps)
        #expect(reps == [22])
    }

    @Test("e1RM PR can come from a lighter, higher-rep segment")
    func testE1RMFromLighterSegment() async throws {
        let (service, prRepo, _) = makeService()
        let exercise = makeExercise()
        // 100×5 → e1RM 116.7 (Epley); 80×13 → e1RM 120 (Brzycki).
        let set = AnalyticsTestHelpers.makeDropSet(parts: [(100, 5), (80, 13)])
        _ = try await service.checkForPR(exercise: exercise, set: set)

        let e1rms = try await records(prRepo, exercise.id, .estimatedOneRepMax)
        #expect(e1rms.count == 1)
        #expect(abs(e1rms[0] - 120.0) < 0.01)
    }

    @Test("max-volume PR uses the whole-set total across segments")
    func testMaxVolumePRUsesSetTotal() async throws {
        let (service, prRepo, _) = makeService()
        let exercise = makeExercise()
        try await seedRecord(prRepo, exerciseId: exercise.id, type: .maxVolume, value: 250)

        let set = AnalyticsTestHelpers.makeDropSet(parts: [(14, 12), (10, 8), (7, 6)])
        _ = try await service.checkForPR(exercise: exercise, set: set)

        let volumes = try await records(prRepo, exercise.id, .maxVolume)
        #expect(volumes.contains(290))
    }

    @Test("warmup and incomplete sets never produce PRs")
    func testWarmupAndIncompleteExcluded() async throws {
        let (service, prRepo, _) = makeService()
        let exercise = makeExercise()

        var warmup = AnalyticsTestHelpers.makeDropSet(parts: [(200, 8)])
        warmup.setType = .warmup
        #expect(try await service.checkForPR(exercise: exercise, set: warmup) == nil)

        var incomplete = AnalyticsTestHelpers.makeDropSet(parts: [(200, 8)])
        incomplete.isCompleted = false
        #expect(try await service.checkForPR(exercise: exercise, set: incomplete) == nil)

        let all = try await prRepo.fetchForExercise(exercise.id)
        #expect(all.isEmpty)
    }

    @Test("recalculateAllPRs handles legacy single-row and grouped drop sets together")
    func testRecalculateAllPRsMixedHistory() async throws {
        let (service, prRepo, workoutRepo) = makeService()
        let exercise = makeExercise()

        let legacyDrop = AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 80, reps: 12, setType: .dropset)
        let grouped = AnalyticsTestHelpers.makeDropSet(order: 2, parts: [(100, 8), (80, 6), (60, 5)])
        let normal = AnalyticsTestHelpers.makeCompletedSet(order: 3, weight: 90, reps: 10)

        let we = AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: [legacyDrop, grouped, normal])
        _ = try await workoutRepo.save(AnalyticsTestHelpers.makeWorkout(exercises: [we]))

        try await service.recalculateAllPRs()

        #expect(try await records(prRepo, exercise.id, .maxWeight) == [100])
        #expect(try await records(prRepo, exercise.id, .maxReps) == [12])
        #expect(try await records(prRepo, exercise.id, .maxVolume) == [1580])

        let e1rms = try await records(prRepo, exercise.id, .estimatedOneRepMax)
        #expect(e1rms.count == 1)
        // Best candidate: 100×8 → 100 × 36/29 ≈ 124.14
        #expect(abs(e1rms[0] - 100.0 * 36.0 / 29.0) < 0.01)
    }
}
