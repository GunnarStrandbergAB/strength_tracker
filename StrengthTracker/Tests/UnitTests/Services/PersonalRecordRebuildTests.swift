import Testing
import Foundation
@testable import StrengthTrackerShared

/// The per-exercise rebuild, the one-row-per-type invariant, deload exclusion,
/// the persisted `isPersonalRecord` flag, and live-check dedupe.
@Suite("PersonalRecordService rebuild")
@MainActor
struct PersonalRecordRebuildTests {

    private func makeService() -> (PersonalRecordService, InMemoryPersonalRecordRepository, InMemoryWorkoutRepository) {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        return (PersonalRecordService(personalRecordRepository: prRepo, workoutRepository: workoutRepo), prRepo, workoutRepo)
    }

    private func set(_ weight: Double, _ reps: Int, daysAgo: Int) -> ExerciseSet {
        AnalyticsTestHelpers.makeCompletedSet(weight: weight, reps: reps, completedAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    private func workout(_ exercise: Exercise, sets: [ExerciseSet], daysAgo: Int, isDeload: Bool = false) -> Workout {
        var w = AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: sets)],
            startedAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            completedAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400 + 3600)
        )
        w.isDeload = isDeload
        return w
    }

    @Test("recalculatePRs elects one row per type, ignores deloads, keeps manual rows, flags the winning sets")
    func rebuild() async throws {
        let (service, prRepo, workoutRepo) = makeService()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        let heavyDeload = set(200, 1, daysAgo: 1)
        let best = set(100, 5, daysAgo: 3)
        let lighter = set(90, 5, daysAgo: 5)
        let older = workout(bench, sets: [lighter], daysAgo: 5)
        let newer = workout(bench, sets: [best], daysAgo: 3)
        let deload = workout(bench, sets: [heavyDeload], daysAgo: 1, isDeload: true)
        _ = try await workoutRepo.save(older)
        _ = try await workoutRepo.save(newer)
        _ = try await workoutRepo.save(deload)

        // Accumulated duplicates + a manual row that must survive.
        for value in [80.0, 85.0, 90.0] {
            _ = try await prRepo.save(PersonalRecord(id: UUID(), exerciseId: bench.id, recordType: .maxWeight, value: value, setId: UUID(), achievedAt: Date()))
        }
        _ = try await prRepo.save(PersonalRecord(id: UUID(), exerciseId: bench.id, recordType: .maxWeight, value: 140, setId: nil, achievedAt: Date()))

        let changed = try await service.recalculatePRs(for: [bench.id])

        let rows = try await prRepo.fetchForExercise(bench.id)
        let automatic = rows.filter { $0.setId != nil }
        #expect(Set(automatic.map(\.recordType)).count == automatic.count, "one automatic row per type")
        #expect(automatic.first { $0.recordType == .maxWeight }?.value == 100, "deload's 200 kg is ignored")
        #expect(automatic.first { $0.recordType == .maxWeight }?.setId == best.id)
        #expect(rows.contains { $0.setId == nil && $0.value == 140 }, "manual row preserved")

        #expect(changed.keys.contains(newer.id), "the winner's workout was re-persisted with the flag")
        let saved = try await workoutRepo.fetchAll()
        let flagged = saved.flatMap { $0.exercises.flatMap(\.sets) }.filter(\.isPersonalRecord).map(\.id)
        #expect(flagged == [best.id], "only the winning set carries the badge")
    }

    @Test("recalculateAllPRs sweeps automatic rows for exercises with no history")
    func sweepOrphans() async throws {
        let (service, prRepo, _) = makeService()
        let ghost = UUID()
        _ = try await prRepo.save(PersonalRecord(id: UUID(), exerciseId: ghost, recordType: .maxWeight, value: 50, setId: UUID(), achievedAt: Date()))
        _ = try await prRepo.save(PersonalRecord(id: UUID(), exerciseId: ghost, recordType: .maxReps, value: 12, setId: nil, achievedAt: Date()))
        try await service.recalculateAllPRs()
        let rows = try await prRepo.fetchForExercise(ghost)
        #expect(rows.count == 1 && rows[0].setId == nil, "orphan automatic row removed, manual kept")
    }

    @Test("checkForPR replaces the beaten row instead of accumulating, and skips deload workouts")
    func liveCheckDedupe() async throws {
        let (service, prRepo, _) = makeService()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        _ = try await service.checkForPR(exercise: bench, set: set(90, 5, daysAgo: 2))
        let pr = try await service.checkForPR(exercise: bench, set: set(100, 5, daysAgo: 1))
        #expect(pr?.recordType == .estimatedOneRepMax)
        let weights = try await prRepo.fetchForExercise(bench.id).filter { $0.recordType == .maxWeight }
        #expect(weights.map(\.value) == [100], "beaten 90 kg row was replaced")

        let none = try await service.checkForPR(exercise: bench, set: set(150, 5, daysAgo: 0), isDeloadWorkout: true)
        #expect(none == nil)
        #expect(try await prRepo.fetchForExercise(bench.id).filter { $0.recordType == .maxWeight }.map(\.value) == [100])
    }

    @Test("revokePR re-elects the previous best from history")
    func revoke() async throws {
        let (service, prRepo, workoutRepo) = makeService()
        let bench = AnalyticsTestHelpers.makeExercise(name: "Bench Press")
        let previous = set(90, 5, daysAgo: 4)
        _ = try await workoutRepo.save(workout(bench, sets: [previous], daysAgo: 4))
        _ = try await service.checkForPR(exercise: bench, set: previous)
        _ = try await service.checkForPR(exercise: bench, set: set(100, 5, daysAgo: 1))
        #expect(try await prRepo.fetchForExercise(bench.id).first { $0.recordType == .maxWeight }?.value == 100)

        // The 100 kg set was never persisted in a workout (un-completed) → revoke.
        try await service.revokePR(exerciseId: bench.id)
        #expect(try await prRepo.fetchForExercise(bench.id).first { $0.recordType == .maxWeight }?.value == 90)
        let saved = try await workoutRepo.fetchAll()
        #expect(saved[0].exercises[0].sets[0].isPersonalRecord)
    }
}
