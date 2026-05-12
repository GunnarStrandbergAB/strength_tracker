import Testing
import Foundation
@testable import StrengthTrackerShared

@MainActor
@Suite("AggregateQualityScore Tests")
struct AggregateQualityScoreTests {

    // MARK: - Helpers

    private func makeService() -> WorkoutQualityScoreService {
        let repo = MockWorkoutRepository()
        let muscleBalance = MuscleBalanceService()
        let healthKit = MockHealthKitService()
        let prefs = UserPreferencesService()
        return WorkoutQualityScoreService(
            workoutRepository: repo,
            muscleBalanceService: muscleBalance,
            healthKitService: healthKit,
            userPreferencesService: prefs
        )
    }

    /// Create N workouts spread across weeks with consistent sets
    private func makeWorkoutHistory(count: Int) -> [Workout] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<count).map { i in
            let date = calendar.date(byAdding: .day, value: -i * 3, to: now)!
            return AnalyticsTestHelpers.makePushDayWorkout(
                startedAt: date,
                completedAt: date.addingTimeInterval(3600)
            )
        }
    }

    // MARK: - Empty / Zero Workouts

    @Test("Empty workout list returns zero aggregate")
    func emptyWorkouts() {
        let service = makeService()
        let result = service.computeAggregateScore(workouts: [])

        #expect(result.ewmaOverall == 0)
        #expect(result.workoutsIncluded == 0)
        #expect(result.trendVsPrior == 0)
        #expect(result.percentileRank == 0)
    }

    // MARK: - Cold Start (< 3 workouts)

    @Test("Single workout uses simple average, trend = 0")
    func singleWorkout() {
        let service = makeService()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        let result = service.computeAggregateScore(workouts: [workout])

        #expect(result.workoutsIncluded == 1)
        #expect(result.ewmaOverall > 0)
        #expect(result.trendVsPrior == 0) // cold start → no trend
        #expect(result.percentileRank == 0.5) // cold start → 0.5
    }

    @Test("Two workouts uses simple average (cold start)")
    func twoWorkouts() {
        let service = makeService()
        let workouts = makeWorkoutHistory(count: 2)
        let result = service.computeAggregateScore(workouts: workouts)

        #expect(result.workoutsIncluded == 2)
        #expect(result.ewmaOverall > 0)
        #expect(result.trendVsPrior == 0)
    }

    // MARK: - EWMA Active (3+ workouts)

    @Test("Three or more workouts activates EWMA")
    func ewmaActivates() {
        let service = makeService()
        let workouts = makeWorkoutHistory(count: 5)
        let result = service.computeAggregateScore(workouts: workouts)

        #expect(result.workoutsIncluded == 5)
        #expect(result.ewmaOverall > 0)
        #expect(result.ewmaOverall <= 100)
        // Percentile should be valid (0-1)
        #expect(result.percentileRank >= 0)
        #expect(result.percentileRank <= 1)
    }

    @Test("EWMA matches manual calculation for known inputs")
    func ewmaManualVerification() {
        // Verify the EWMA utility itself with known values
        let values = [60.0, 70.0, 80.0, 90.0, 100.0]
        let lambda = 0.3
        let ewma = AnalyticsCalculations.ewma(values: values, lambda: lambda)

        // Manual: ewma[0] = 60
        // ewma[1] = 0.3*70 + 0.7*60 = 21 + 42 = 63
        // ewma[2] = 0.3*80 + 0.7*63 = 24 + 44.1 = 68.1
        // ewma[3] = 0.3*90 + 0.7*68.1 = 27 + 47.67 = 74.67
        // ewma[4] = 0.3*100 + 0.7*74.67 = 30 + 52.269 = 82.269
        #expect(ewma.count == 5)
        #expect(abs(ewma[0] - 60.0) < 0.01)
        #expect(abs(ewma[1] - 63.0) < 0.01)
        #expect(abs(ewma[2] - 68.1) < 0.01)
        #expect(abs(ewma[3] - 74.67) < 0.01)
        #expect(abs(ewma[4] - 82.269) < 0.01)
    }

    // MARK: - Trend Tests

    @Test("Stable scores produce near-zero trend")
    func stableTrend() {
        let service = makeService()
        // Create many workouts with same exercises/weights spread across 6+ weeks
        let calendar = Calendar.current
        let now = Date()
        let workouts = (0..<12).map { i in
            let date = calendar.date(byAdding: .day, value: -i * 4, to: now)!
            return AnalyticsTestHelpers.makePushDayWorkout(
                startedAt: date,
                completedAt: date.addingTimeInterval(3600)
            )
        }
        let result = service.computeAggregateScore(workouts: workouts)

        // With identical workouts, EWMA should converge → trend ~0
        #expect(abs(result.trendVsPrior) < 15, "Trend should be small for identical workouts, got \(result.trendVsPrior)")
    }

    // MARK: - Percentile Tests

    @Test("Percentile rank is within 0-1")
    func percentileRange() {
        let service = makeService()
        let workouts = makeWorkoutHistory(count: 10)
        let result = service.computeAggregateScore(workouts: workouts)

        #expect(result.percentileRank >= 0)
        #expect(result.percentileRank <= 1)
    }

    // MARK: - Cache Tests

    @Test("Cache returns same score for same workout")
    func cacheHit() {
        let service = makeService()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        let allWorkouts = [workout]

        let score1 = service.computeScore(for: workout, history: allWorkouts)
        let score2 = service.computeScore(for: workout, history: allWorkouts)

        #expect(score1.overallScore == score2.overallScore)
        #expect(score1.id == score2.id) // same cached instance
    }

    @Test("History overload avoids internal fetchAll")
    func historyOverloadNoFetch() async throws {
        let repo = MockWorkoutRepository()
        let service = WorkoutQualityScoreService(
            workoutRepository: repo,
            muscleBalanceService: MuscleBalanceService(),
            healthKitService: MockHealthKitService(),
            userPreferencesService: UserPreferencesService()
        )

        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        repo.seed([workout])

        // Using history overload should NOT call fetchAll
        _ = service.computeScore(for: workout, history: [workout])
        #expect(repo.fetchAllCallCount == 0)

        // Using original method should call fetchAll
        _ = try await service.computeScore(for: AnalyticsTestHelpers.makePullDayWorkout())
        #expect(repo.fetchAllCallCount == 1)
    }

    // MARK: - Dimension Scores

    @Test("Aggregate dimensions are all populated")
    func dimensionsPopulated() {
        let service = makeService()
        // Use mixed push+pull workouts to ensure balance is non-zero
        let calendar = Calendar.current
        let now = Date()
        let workouts = (0..<6).map { i -> Workout in
            let date = calendar.date(byAdding: .day, value: -i * 3, to: now)!
            if i.isMultiple(of: 2) {
                return AnalyticsTestHelpers.makePushDayWorkout(startedAt: date, completedAt: date.addingTimeInterval(3600))
            } else {
                return AnalyticsTestHelpers.makePullDayWorkout(startedAt: date, completedAt: date.addingTimeInterval(3600))
            }
        }
        let result = service.computeAggregateScore(workouts: workouts)

        #expect(result.ewmaVolume > 0)
        #expect(result.ewmaIntensity > 0)
        #expect(result.ewmaBalance >= 0) // may still be low with only push/pull
        #expect(result.ewmaConsistency > 0)
        #expect(result.ewmaVolume <= 100)
        #expect(result.ewmaIntensity <= 100)
        #expect(result.ewmaBalance <= 100)
        #expect(result.ewmaConsistency <= 100)
    }

    // MARK: - Volume Sub-Score Regression Tests
    //
    // These guard against two flaws fixed together:
    //   1. Progressive overload was capped at a "60 floor" once a muscle group's
    //      volume exceeded 1.4× its rolling per-session average. A workout that
    //      doubled volume scored lower than one that matched the average.
    //   2. The non-deload baseline included deload workouts, dragging the
    //      per-muscle-group average down so regular workouts looked like they
    //      overshot more than they really did.

    @Test("Volume: progressive overload no longer penalized — 2× per-session volume still scores 100")
    func volumeScore_progressiveOverloadNotPenalized() {
        let service = makeService()
        let cal = Calendar.current
        let now = Date()

        // 5 history workouts at chest = 4 × 10 × 80 kg (primary-only attribution).
        let history = (1...5).map { i -> Workout in
            let date = cal.date(byAdding: .day, value: -i * 3, to: now)!
            return AnalyticsTestHelpers.makeWorkoutWithVolume(
                primaryMuscleGroup: .chest,
                sets: 4, reps: 10, weight: 80,
                startedAt: date,
                completedAt: date.addingTimeInterval(3600)
            )
        }

        // Current: 2× volume (8 × 10 × 80 kg) → ratio 2.0 vs baseline.
        let current = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest,
            sets: 8, reps: 10, weight: 80,
            startedAt: now,
            completedAt: now.addingTimeInterval(3600)
        )

        let score = service.computeScore(for: current, history: history + [current])
        #expect(score.volumeScore == 100,
            "ratio 2.0 should score 100 (no upper-taper); got \(score.volumeScore)")
    }

    @Test("Volume: deload workouts are excluded from the non-deload baseline")
    func volumeScore_deloadExcludedFromBaseline() {
        let service = makeService()
        let cal = Calendar.current
        let now = Date()

        // 5 non-deload regular workouts at chest = 4 × 10 × 80.
        let regular = (1...5).map { i -> Workout in
            let date = cal.date(byAdding: .day, value: -i * 7, to: now)!
            return AnalyticsTestHelpers.makeWorkoutWithVolume(
                primaryMuscleGroup: .chest,
                sets: 4, reps: 10, weight: 80,
                startedAt: date,
                completedAt: date.addingTimeInterval(3600)
            )
        }
        // 5 deload workouts at half volume. If included in the baseline they'd
        // pull perSessionAvg from 2240 down to ~1680 and the under-volume penalty
        // below would resolve to ~83 instead of 62.5.
        var deloads = (1...5).map { i -> Workout in
            let date = cal.date(byAdding: .day, value: -(i * 7 + 3), to: now)!
            return AnalyticsTestHelpers.makeWorkoutWithVolume(
                primaryMuscleGroup: .chest,
                sets: 2, reps: 10, weight: 80,
                startedAt: date,
                completedAt: date.addingTimeInterval(3600)
            )
        }
        for i in deloads.indices { deloads[i].isDeload = true }

        // Current: half the regular volume, non-deload. Filter active → ratio 0.5 → 62.5.
        let current = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest,
            sets: 2, reps: 10, weight: 80,
            startedAt: now,
            completedAt: now.addingTimeInterval(3600)
        )

        let score = service.computeScore(for: current, history: regular + deloads + [current])
        #expect(abs(score.volumeScore - 62.5) < 0.5,
            "Deload-filtered baseline should yield score 62.5; got \(score.volumeScore)")
    }

    @Test("Volume: under-volume still penalized linearly below the 0.8 sweet spot")
    func volumeScore_underVolumeStillPenalized() {
        let service = makeService()
        let cal = Calendar.current
        let now = Date()

        // 5 history workouts at chest = 4 × 10 × 80 (perSessionAvg of 2240 to chest).
        let history = (1...5).map { i -> Workout in
            let date = cal.date(byAdding: .day, value: -i * 3, to: now)!
            return AnalyticsTestHelpers.makeWorkoutWithVolume(
                primaryMuscleGroup: .chest,
                sets: 4, reps: 10, weight: 80,
                startedAt: date,
                completedAt: date.addingTimeInterval(3600)
            )
        }

        // Current at 0.4× volume (weight 32 vs 80 → ratio 0.4): linear penalty → 50.
        let current = AnalyticsTestHelpers.makeWorkoutWithVolume(
            primaryMuscleGroup: .chest,
            sets: 4, reps: 10, weight: 32,
            startedAt: now,
            completedAt: now.addingTimeInterval(3600)
        )

        let score = service.computeScore(for: current, history: history + [current])
        #expect(abs(score.volumeScore - 50.0) < 0.5,
            "ratio 0.4 should linearly penalize to 50; got \(score.volumeScore)")
    }

    // MARK: - Incomplete Workouts Filtered

    @Test("Incomplete workouts are excluded from aggregate")
    func incompleteFiltered() {
        let service = makeService()
        let completed = AnalyticsTestHelpers.makePushDayWorkout()
        let incomplete = AnalyticsTestHelpers.makeWorkout(
            name: "Incomplete",
            exercises: [],
            completedAt: nil
        )
        let result = service.computeAggregateScore(workouts: [completed, incomplete])

        #expect(result.workoutsIncluded == 1)
    }
}
