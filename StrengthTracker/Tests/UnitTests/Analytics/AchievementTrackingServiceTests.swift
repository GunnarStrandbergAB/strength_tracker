import Testing
import Foundation
@testable import StrengthTrackerShared

@MainActor
@Suite("AchievementTrackingService.computeVolumeResponse")
struct AchievementTrackingServiceTests {

    // MARK: - Helpers

    /// Build N completed workouts that each contain one exercise with `setCount` working sets.
    private func makeWorkouts(
        exerciseId: UUID,
        exerciseName: String,
        primaryMuscle: MuscleGroup,
        setCount: Int,
        count: Int,
        startDaysAgo: Int = 0
    ) -> [Workout] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<count).map { i in
            let date = calendar.date(byAdding: .day, value: -(startDaysAgo + i * 3), to: now)!
            let exercise = AnalyticsTestHelpers.makeExercise(
                id: exerciseId,
                name: exerciseName,
                primaryMuscleGroup: primaryMuscle,
                secondaryMuscleGroups: []
            )
            let sets = (1...setCount).map { order in
                AnalyticsTestHelpers.makeCompletedSet(order: order, weight: 80.0, reps: 10)
            }
            let wExercise = AnalyticsTestHelpers.makeWorkoutExercise(
                exercise: exercise,
                order: 1,
                sets: sets
            )
            return AnalyticsTestHelpers.makeWorkout(
                name: "\(exerciseName) #\(i+1)",
                exercises: [wExercise],
                startedAt: date,
                completedAt: date.addingTimeInterval(3600)
            )
        }
    }

    private func makeTrend(
        exerciseId: UUID,
        exerciseName: String,
        slope: Double
    ) -> OverloadTrend {
        OverloadTrend(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            weeklyE1RMs: [],
            slopePerWeek: slope,
            trendStatus: slope > 0.5 ? .progressing : (slope < -0.5 ? .regressing : .plateau),
            overloadIndex: 0
        )
    }

    // MARK: - Tests

    @Test("Under 50 completed workouts returns empty array")
    func under50ReturnsEmpty() {
        let service = AchievementTrackingService()
        let exerciseId = UUID()
        let workouts = makeWorkouts(
            exerciseId: exerciseId,
            exerciseName: "Bench Press",
            primaryMuscle: .chest,
            setCount: 8,
            count: 49
        )
        let trend = makeTrend(exerciseId: exerciseId, exerciseName: "Bench Press", slope: 1.0)

        let curves = service.computeVolumeResponse(workouts: workouts, overloadTrends: [trend])

        #expect(curves.isEmpty)
    }

    @Test("Inverted-parabola signal produces a fitted curve with vertex near peak")
    func invertedParabolaFitProducesCurve() {
        let service = AchievementTrackingService()
        // Three chest exercises clustered at 8, 12, 16 sets/session.
        // Slopes follow y = -0.03125·(sets - 12)² + 1.0  →  peak at sets = 12.
        let a = UUID(), b = UUID(), c = UUID()
        var workouts = makeWorkouts(exerciseId: a, exerciseName: "Bench Press", primaryMuscle: .chest, setCount: 8, count: 20, startDaysAgo: 0)
        workouts += makeWorkouts(exerciseId: b, exerciseName: "Incline Press", primaryMuscle: .chest, setCount: 12, count: 20, startDaysAgo: 60)
        workouts += makeWorkouts(exerciseId: c, exerciseName: "Dips", primaryMuscle: .chest, setCount: 16, count: 20, startDaysAgo: 120)

        let trends = [
            makeTrend(exerciseId: a, exerciseName: "Bench Press", slope: 0.5),
            makeTrend(exerciseId: b, exerciseName: "Incline Press", slope: 1.0),
            makeTrend(exerciseId: c, exerciseName: "Dips", slope: 0.5)
        ]

        let curves = service.computeVolumeResponse(workouts: workouts, overloadTrends: trends)

        #expect(curves.count == 1)
        guard let curve = curves.first else { return }
        #expect(curve.muscleGroup == "chest")
        #expect(curve.rSquared > 0.3)
        if let mav = curve.personalMAV {
            #expect(abs(mav - 12.0) < 1.5, "MAV should be near peak (12 sets)")
        } else {
            Issue.record("Expected personalMAV to be populated")
        }
    }

    @Test("Random / non-concave signal is filtered out (empty result)")
    func noisySignalReturnsEmpty() {
        let service = AchievementTrackingService()
        // Three exercises all at chest, but slopes do NOT form an inverted parabola.
        // 8 sets → high, 12 sets → low, 16 sets → high : creates a convex (positive a) fit,
        // which the service rejects via `guard a < 0`.
        let a = UUID(), b = UUID(), c = UUID()
        var workouts = makeWorkouts(exerciseId: a, exerciseName: "Bench Press", primaryMuscle: .chest, setCount: 8, count: 20, startDaysAgo: 0)
        workouts += makeWorkouts(exerciseId: b, exerciseName: "Incline Press", primaryMuscle: .chest, setCount: 12, count: 20, startDaysAgo: 60)
        workouts += makeWorkouts(exerciseId: c, exerciseName: "Dips", primaryMuscle: .chest, setCount: 16, count: 20, startDaysAgo: 120)

        let trends = [
            makeTrend(exerciseId: a, exerciseName: "Bench Press", slope: 1.0),
            makeTrend(exerciseId: b, exerciseName: "Incline Press", slope: 0.1),
            makeTrend(exerciseId: c, exerciseName: "Dips", slope: 1.0)
        ]

        let curves = service.computeVolumeResponse(workouts: workouts, overloadTrends: trends)

        #expect(curves.isEmpty, "Convex (non-inverted) fits must be rejected")
    }
}
