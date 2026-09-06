import Testing
@testable import StrengthTrackerShared
import Foundation

/// Verifies the calculation choke points feed drop-set segments into analytics:
/// IWV training load, best-e1RM maps, vectorizer volume, and calorie estimation.
@Suite("Drop Set Analytics Tests")
struct DropSetAnalyticsTests {

    // MARK: - IWV (Intensity-Weighted Volume)

    @Test("setIWV(for:) sums IWV across drop segments with per-part pct1RM and RPE")
    func testDropAwareSetIWV() {
        let set = AnalyticsTestHelpers.makeDropSet(
            parts: [(100, 8), (80, 6)],
            rpes: [8, 9]
        )
        let iwv = AnalyticsCalculations.setIWV(for: set, bestE1RM: 120, baseLoadPerRep: nil)
        // part 1: 8 × (100/120) × 0.8 = 5.3333; part 2: 6 × (80/120) × 0.9 = 3.6
        #expect(abs(iwv - (8.0 * (100.0 / 120.0) * 0.8 + 6.0 * (80.0 / 120.0) * 0.9)) < 0.0001)
    }

    @Test("setIWV(for:) falls back to pct1RM 0.75 without a best e1RM")
    func testSetIWVFallbackPct() {
        let set = AnalyticsTestHelpers.makeDropSet(parts: [(100, 8)])
        #expect(AnalyticsCalculations.setIWV(for: set, bestE1RM: nil, baseLoadPerRep: nil) == 8.0 * 0.75)
    }

    @Test("setIWV(for:) is 0 for warmup and incomplete sets")
    func testSetIWVGuards() {
        var warmup = AnalyticsTestHelpers.makeDropSet(parts: [(100, 8)])
        warmup.setType = .warmup
        #expect(AnalyticsCalculations.setIWV(for: warmup, bestE1RM: 100, baseLoadPerRep: nil) == 0)

        var incomplete = AnalyticsTestHelpers.makeDropSet(parts: [(100, 8)])
        incomplete.isCompleted = false
        #expect(AnalyticsCalculations.setIWV(for: incomplete, bestE1RM: 100, baseLoadPerRep: nil) == 0)
    }

    // MARK: - Best e1RM Map

    @Test("buildBestE1RMMap considers every drop segment")
    func testBestE1RMMapIncludesSegments() {
        let exercise = AnalyticsTestHelpers.makeExercise(name: "Row", primaryMuscleGroup: .back, secondaryMuscleGroups: [])
        // 80×15 → Epley 120; the 100×1 single is only 100.
        let drop = AnalyticsTestHelpers.makeDropSet(order: 1, parts: [(80, 15)])
        let single = AnalyticsTestHelpers.makeCompletedSet(order: 2, weight: 100, reps: 1)
        let we = AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: [drop, single])
        let workout = AnalyticsTestHelpers.makeWorkout(exercises: [we])

        let map = AnalyticsCalculations.buildBestE1RMMap(from: [workout], bodyWeightKg: 70)
        #expect(abs((map[exercise.id] ?? 0) - 120.0) < 0.01)
    }

    // MARK: - Vectorizer Volume

    @Test("vectorizer total volume includes drop segments")
    @MainActor
    func testVectorizerVolumeIncludesSegments() {
        let exercise = AnalyticsTestHelpers.makeExercise()
        let normal = AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 100, reps: 8)
        let drop = AnalyticsTestHelpers.makeDropSet(order: 2, parts: [(50, 10), (40, 8)])
        let we = AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: [normal, drop])
        let workout = AnalyticsTestHelpers.makeWorkout(exercises: [we])

        let vectorizer = WorkoutVectorizer()
        // 800 + (500 + 320)
        #expect(vectorizer.calculateTotalVolume(workout, bodyWeightKg: 80) == 1620.0)
    }

    // MARK: - Calorie Estimation

    @Test("calorie estimate grows when drop segments add volume")
    func testCalorieVolumeBonusIncludesSegments() {
        let exercise = AnalyticsTestHelpers.makeExercise()
        let start = Date()

        let plain = AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: 100, reps: 8)
        let workoutA = AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: [plain])],
            startedAt: start,
            completedAt: start.addingTimeInterval(3600)
        )

        // Same top segment plus an extra 60×10 drop — strictly more volume.
        let drop = AnalyticsTestHelpers.makeDropSet(order: 1, parts: [(100, 8), (60, 10)])
        let workoutB = AnalyticsTestHelpers.makeWorkout(
            exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: [drop])],
            startedAt: start,
            completedAt: start.addingTimeInterval(3600)
        )

        let service = CalorieEstimationService()
        let a = service.estimateCalories(workout: workoutA, bodyWeightKg: 80)
        let b = service.estimateCalories(workout: workoutB, bodyWeightKg: 80)
        #expect(b.totalCalories > a.totalCalories)
    }

    // MARK: - Plan Analytics Inputs

    @Test("a drop set counts once toward set totals but fully toward reps and volume")
    func testSetCountingContract() {
        let drop = AnalyticsTestHelpers.makeDropSet(parts: [(14, 12), (10, 8), (7, 6)])
        // The contract used by PlanAnalyticsService and every set-count site:
        // one working set, summed reps, summed volume.
        let workingSets = [drop].filter { $0.isCompleted && $0.setType != .warmup }.count
        #expect(workingSets == 1)
        #expect(drop.totalReps == 26)
        #expect(drop.setVolume(baseLoadPerRep: nil) == 290.0)
    }
}
