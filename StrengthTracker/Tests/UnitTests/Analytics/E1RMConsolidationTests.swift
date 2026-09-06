import Testing
import Foundation
@testable import StrengthTrackerShared

/// Every e1RM consumer must agree on one formula, one rep clamp, and one set filter.
@Suite("e1RM consolidation")
@MainActor
struct E1RMConsolidationTests {

    private func exercise() -> Exercise {
        AnalyticsTestHelpers.makeExercise(name: "Bench Press")
    }

    @Test("bestE1RM clamps reps to 15 instead of dropping high-rep sets")
    func clampNotDrop() {
        let twenty = AnalyticsTestHelpers.makeCompletedSet(weight: 60, reps: 20)
        let expected = AnalyticsCalculations.calculateOneRM(weight: 60, reps: 15)
        #expect(AnalyticsCalculations.bestE1RM(for: twenty, baseLoadPerRep: nil) == expected)
    }

    @Test("bestE1RM ignores warm-ups and incomplete sets, considers every drop segment")
    func filtersAndSegments() {
        let warmup = AnalyticsTestHelpers.makeCompletedSet(weight: 200, reps: 1, setType: .warmup)
        var incomplete = AnalyticsTestHelpers.makeCompletedSet(weight: 200, reps: 1)
        incomplete.isCompleted = false
        // Top segment 100×5 (116.7) but the second segment 80×15 → Epley 120.
        let drop = AnalyticsTestHelpers.makeDropSet(parts: [(100, 5), (80, 15)])
        #expect(AnalyticsCalculations.bestE1RM(for: warmup, baseLoadPerRep: nil) == nil)
        #expect(AnalyticsCalculations.bestE1RM(for: incomplete, baseLoadPerRep: nil) == nil)
        let best = try! #require(AnalyticsCalculations.bestE1RM(for: drop, baseLoadPerRep: nil))
        #expect(abs(best - 120) < 0.01)
    }

    @Test("SessionExecutionService, PR service and the best-e1RM map agree on the same set")
    func consumersAgree() async throws {
        let ex = exercise()
        let set = AnalyticsTestHelpers.makeDropSet(parts: [(100, 5), (80, 15)])
        let canonical = AnalyticsCalculations.bestE1RM(for: set, baseLoadPerRep: nil)!

        let session = SessionExecutionService().estimateCurrent1RM(from: [set])
        #expect(session == canonical.rounded(toNearest: 2.5))

        let workout = AnalyticsTestHelpers.makeWorkout(exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: ex, sets: [set])])
        let map = AnalyticsCalculations.buildBestE1RMMap(from: [workout], bodyWeightKg: 70)
        #expect(abs((map[ex.id] ?? 0) - canonical) < 0.01)

        let prRepo = InMemoryPersonalRecordRepository()
        let prService = PersonalRecordService(personalRecordRepository: prRepo, workoutRepository: InMemoryWorkoutRepository())
        _ = try await prService.checkForPR(exercise: ex, set: set)
        let prE1RM = try await prRepo.fetchForExercise(ex.id).first { $0.recordType == .estimatedOneRepMax }?.value
        #expect(abs((prE1RM ?? 0) - canonical) < 0.01)
    }
}
