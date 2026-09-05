import XCTest
@testable import StrengthTrackerShared

@MainActor
final class TrainingStatusDetectorTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        workouts: [Workout] = []
    ) -> TrainingStatusDetector {
        let repo = MockWorkoutRepositoryProgression()
        repo.workouts = workouts
        return TrainingStatusDetector(workoutRepository: repo)
    }

    private func makeExercise(
        id: UUID = UUID(),
        name: String = "Bench Press"
    ) -> Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeSet(
        weight: Double? = nil,
        reps: Int? = nil,
        isCompleted: Bool = true,
        setType: SetType = .normal
    ) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: 1,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: isCompleted,
            isPersonalRecord: false,
            completedAt: nil
        )
    }

    private func makeWorkoutExercise(
        exercise: Exercise,
        sets: [ExerciseSet]
    ) -> WorkoutExercise {
        WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: sets
        )
    }

    private func makeCompletedWorkout(
        startedAt: Date,
        completedAt: Date? = nil,
        exercises: [WorkoutExercise] = []
    ) -> Workout {
        let completed = completedAt ?? startedAt.addingTimeInterval(3600)
        return Workout(
            id: UUID(),
            name: "Workout",
            startedAt: startedAt,
            completedAt: completed,
            notes: nil,
            templateId: nil,
            exercises: exercises
        )
    }

    /// Generate N completed workouts spread evenly across a date range.
    private func generateWorkouts(
        count: Int,
        startingMonthsAgo: Int,
        endingMonthsAgo: Int = 0,
        exercises: [WorkoutExercise] = []
    ) -> [Workout] {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(
            byAdding: .month, value: -startingMonthsAgo, to: now
        )!
        let endDate = calendar.date(
            byAdding: .month, value: -endingMonthsAgo, to: now
        )!

        let totalInterval = endDate.timeIntervalSince(startDate)
        guard count > 0 else { return [] }
        let step = count > 1 ? totalInterval / Double(count - 1) : 0

        return (0..<count).map { i in
            let date = startDate.addingTimeInterval(step * Double(i))
            return makeCompletedWorkout(
                startedAt: date,
                completedAt: date.addingTimeInterval(3600),
                exercises: exercises
            )
        }
    }

    // MARK: - detect() Tests

    func testDetect_noWorkouts_returnsBeginner() async throws {
        let sut = makeSUT(workouts: [])
        let status = try await sut.detect()
        XCTAssertEqual(status, .beginner)
    }

    func testDetect_fewRecentWorkouts_returnsBeginner() async throws {
        // 10 workouts in 1 month: count < 50, months < 3, frequency ~2.3 but
        // neither threshold met for intermediate
        let workouts = generateWorkouts(count: 10, startingMonthsAgo: 1)
        let sut = makeSUT(workouts: workouts)
        let status = try await sut.detect()
        XCTAssertEqual(status, .beginner)
    }

    func testDetect_moderateHistory_returnsIntermediate() async throws {
        // 80 workouts over 6 months, ~3x/week frequency
        // monthsTraining >= 3, count >= 50, weeklyFrequency ~6.15 (80/13 weeks)
        let workouts = generateWorkouts(count: 80, startingMonthsAgo: 6)
        let sut = makeSUT(workouts: workouts)
        let status = try await sut.detect()
        XCTAssertEqual(status, .intermediate)
    }

    func testDetect_extensiveHistory_returnsAdvanced() async throws {
        // 250 workouts over 24 months, > 200, > 18 months
        // Recent 3 months: need to ensure enough workouts in last 3 months
        // 250 over 24 months = ~10.4/month. In last 3 months = ~31 workouts
        // weeklyFrequency = 31/13 = ~2.38... need >= 3.0
        // So we need more concentrated recent workouts.
        // Generate 200 over first 21 months + 60 in last 3 months = 260 total
        let earlyWorkouts = generateWorkouts(
            count: 200, startingMonthsAgo: 24, endingMonthsAgo: 3
        )
        let recentWorkouts = generateWorkouts(
            count: 60, startingMonthsAgo: 3
        )
        let allWorkouts = earlyWorkouts + recentWorkouts
        let sut = makeSUT(workouts: allWorkouts)
        let status = try await sut.detect()
        XCTAssertEqual(status, .advanced)
    }

    func testDetect_oldHistoryButInactive_returnsBeginner() async throws {
        // 100 workouts but all more than 3 months ago. Weekly frequency = 0
        let workouts = generateWorkouts(
            count: 100, startingMonthsAgo: 12, endingMonthsAgo: 4
        )
        let sut = makeSUT(workouts: workouts)
        let status = try await sut.detect()
        XCTAssertEqual(status, .beginner)
    }

    func testDetect_incompleteWorkoutsIgnored() async throws {
        // Workouts without completedAt should not count
        let incompleteWorkout = Workout(
            id: UUID(),
            name: "In Progress",
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            exercises: []
        )
        let sut = makeSUT(workouts: [incompleteWorkout])
        let status = try await sut.detect()
        XCTAssertEqual(status, .beginner)
    }

    // MARK: - estimateOneRM() Tests

    // MARK: - Boundary Value Tests (C5, M19)

    func testDetect_exactly3Months50Workouts_frequencyGated_intermediate() async throws {
        // Exactly 3 months, 50 workouts, frequency >= 2.0 -> intermediate
        let workouts = generateWorkouts(count: 50, startingMonthsAgo: 3)
        let sut = makeSUT(workouts: workouts)
        let status = try await sut.detect()
        XCTAssertEqual(status, .intermediate)
    }

    func testDetect_exactly50Workouts_lowFrequency_staysBeginner() async throws {
        // 60 workouts over 13 months, only ~5 in last 3 months => freq < 2.0 -> beginner (M19)
        // Spread 55 workouts over months 13..3 ago, 5 workouts in last 3 months
        let earlyWorkouts = generateWorkouts(count: 55, startingMonthsAgo: 13, endingMonthsAgo: 3)
        let recentWorkouts = generateWorkouts(count: 5, startingMonthsAgo: 3)
        let allWorkouts = earlyWorkouts + recentWorkouts
        let sut = makeSUT(workouts: allWorkouts)
        let status = try await sut.detect()
        // freq = 5/13 = 0.38 < 2.0 -> beginner despite 60 total workouts
        XCTAssertEqual(status, .beginner)
    }

    func testDetect_50Workouts_adequateFrequency_intermediate() async throws {
        // 50 workouts, all in last 3 months => freq = 50/13 ~3.8 -> intermediate (M19)
        let workouts = generateWorkouts(count: 50, startingMonthsAgo: 3)
        let sut = makeSUT(workouts: workouts)
        let status = try await sut.detect()
        XCTAssertEqual(status, .intermediate)
    }

    func testDetect_18MonthsExactly200Workouts_notAdvanced() async throws {
        // Advanced requires > 18 months AND > 200 workouts
        // Exactly 18 months and exactly 200 -> should NOT be advanced
        let earlyWorkouts = generateWorkouts(count: 160, startingMonthsAgo: 18, endingMonthsAgo: 3)
        let recentWorkouts = generateWorkouts(count: 40, startingMonthsAgo: 3)
        let allWorkouts = earlyWorkouts + recentWorkouts
        let sut = makeSUT(workouts: allWorkouts)
        let status = try await sut.detect()
        // 200 workouts, 18 months: > 18 fails (not strictly greater), > 200 fails
        // Should be intermediate (3+ months, 200+ workouts, freq ~3.1)
        XCTAssertNotEqual(status, .advanced)
    }

    func testDetect_19Months201Workouts_highFrequency_advanced() async throws {
        // > 18 months, > 200 workouts, freq >= 3.0 -> advanced
        // Note: completedAt is startedAt + 1h, so a history starting exactly
        // 19 months ago truncates to 18 full calendar months and fails the
        // strict "> 18 months" check. Start 20 months ago to be clearly past
        // the boundary (monthsTraining = 19 > 18).
        let earlyWorkouts = generateWorkouts(count: 161, startingMonthsAgo: 20, endingMonthsAgo: 3)
        let recentWorkouts = generateWorkouts(count: 40, startingMonthsAgo: 3)
        let allWorkouts = earlyWorkouts + recentWorkouts
        let sut = makeSUT(workouts: allWorkouts)
        let status = try await sut.detect()
        // 201 workouts, >18 months, freq = 40/13 ~3.1 -> advanced
        XCTAssertEqual(status, .advanced)
    }

    func testDetect_advancedThresholds_lowFrequency_notAdvanced() async throws {
        // > 18 months, > 200 workouts, but freq < 3.0 -> intermediate (not advanced)
        let earlyWorkouts = generateWorkouts(count: 195, startingMonthsAgo: 24, endingMonthsAgo: 3)
        let recentWorkouts = generateWorkouts(count: 30, startingMonthsAgo: 3)
        let allWorkouts = earlyWorkouts + recentWorkouts
        let sut = makeSUT(workouts: allWorkouts)
        let status = try await sut.detect()
        // freq = 30/13 ~2.31 < 3.0 -> not advanced; but intermediate thresholds met
        XCTAssertEqual(status, .intermediate)
    }

    // MARK: - estimateOneRM() Tests

    func testEstimateOneRM_recentData_returnsEstimate() async throws {
        // Workout 2 months ago with bench press 100kg x 5
        // Expected: 100 * (1 + 5/30) = 100 * 1.1667 = 116.67 -> rounded to 117.5
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [makeSet(weight: 100, reps: 5)]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let twoMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -2, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: twoMonthsAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)

        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate!.source, .recent)
        XCTAssertFalse(estimate!.isStale)
        // 100 * (1 + 5/30) = 116.667 -> rounded to nearest 2.5 = 117.5
        XCTAssertEqual(estimate!.value, 117.5, accuracy: 0.01)
    }

    func testEstimateOneRM_extendedData_appliesDetrainingPenalty() async throws {
        // Workout 8 months ago with bench press 100kg x 5
        // Raw 1RM: 100 * (1 + 5/30) = 116.667
        // With 10% penalty: 116.667 * 0.9 = 105.0
        // Rounded to nearest 2.5: 105.0
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [makeSet(weight: 100, reps: 5)]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let eightMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -8, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: eightMonthsAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)

        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate!.source, .extended)
        XCTAssertTrue(estimate!.isStale)
        // 116.667 * 0.9 = 105.0 -> rounded to 105.0
        XCTAssertEqual(estimate!.value, 105.0, accuracy: 0.01)
    }

    func testEstimateOneRM_noData_returnsNil() async throws {
        let sut = makeSUT(workouts: [])
        let estimate = try await sut.estimateOneRM(exerciseId: UUID())
        XCTAssertNil(estimate)
    }

    func testEstimateOneRM_dataOlderThan12Months_returnsNil() async throws {
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [makeSet(weight: 100, reps: 5)]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let fourteenMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -14, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: fourteenMonthsAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)
        XCTAssertNil(estimate)
    }

    func testEstimateOneRM_highRepSets_clamped() async throws {
        // Sets with reps > 15 are clamped to 15 for the formula (app-wide rule), not dropped.
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let highRepSet = makeSet(weight: 60, reps: 20)
        let workoutExercise = makeWorkoutExercise(
            exercise: exercise, sets: [highRepSet]
        )

        let oneMonthAgo = Calendar.current.date(
            byAdding: .month, value: -1, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: oneMonthAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)
        let expected = AnalyticsCalculations.calculateOneRM(weight: 60, reps: 15).rounded(toNearest: 2.5)
        XCTAssertEqual(estimate?.value, expected)
    }

    func testEstimateOneRM_roundsToNearest2_5() async throws {
        // Use a weight/rep combo that produces a non-round number
        // 80kg x 3 reps: 80 * (1 + 3/30) = 80 * 1.1 = 88.0 -> 87.5
        // Actually 88.0 is already on 2.5 boundary. Try another.
        // 85kg x 4 reps: 85 * (1 + 4/30) = 85 * 1.1333 = 96.333 -> 97.5
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [makeSet(weight: 85, reps: 4)]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let oneMonthAgo = Calendar.current.date(
            byAdding: .month, value: -1, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: oneMonthAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)

        XCTAssertNotNil(estimate)
        // 85 * (1 + 4/30) = 85 * 1.13333 = 96.333
        // Rounded to nearest 2.5: 96.333 -> 97.5
        let remainder = estimate!.value.truncatingRemainder(dividingBy: 2.5)
        XCTAssertEqual(remainder, 0, accuracy: 0.001, "Value should be a multiple of 2.5")
        XCTAssertEqual(estimate!.value, 97.5, accuracy: 0.01)
    }

    func testEstimateOneRM_singleRep_returnsWeight() async throws {
        // 1 rep at 120kg -> 1RM = 120kg
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [makeSet(weight: 120, reps: 1)]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let oneMonthAgo = Calendar.current.date(
            byAdding: .month, value: -1, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: oneMonthAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)

        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate!.value, 120.0, accuracy: 0.01)
    }

    func testEstimateOneRM_brzycki_usedForHigherReps() async throws {
        // 10 reps at 75kg: Brzycki = 75 * 36 / (37 - 10) = 75 * 36 / 27 = 100.0
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [makeSet(weight: 75, reps: 10)]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let oneMonthAgo = Calendar.current.date(
            byAdding: .month, value: -1, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: oneMonthAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)

        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate!.value, 100.0, accuracy: 0.01)
    }

    func testEstimateOneRM_picksBestEstimate() async throws {
        // Multiple sets: picks the highest 1RM estimate
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [
            makeSet(weight: 80, reps: 5),    // 80 * (1 + 5/30) = 93.33
            makeSet(weight: 100, reps: 3),   // 100 * (1 + 3/30) = 110.0
            makeSet(weight: 60, reps: 10),   // 60 * 36/27 = 80.0
        ]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let oneMonthAgo = Calendar.current.date(
            byAdding: .month, value: -1, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: oneMonthAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)

        XCTAssertNotNil(estimate)
        // Best is 110.0, rounded to nearest 2.5 = 110.0
        XCTAssertEqual(estimate!.value, 110.0, accuracy: 0.01)
    }

    func testEstimateOneRM_recentPreferredOverExtended() async throws {
        // Both recent and extended data exist. Recent should be used even if
        // extended raw value is higher (because extended gets 10% penalty).
        let exerciseId = UUID()
        let exercise = makeExercise(id: exerciseId)

        // Recent: 90kg x 5 = 90 * 1.1667 = 105.0
        let recentSets = [makeSet(weight: 90, reps: 5)]
        let recentExercise = makeWorkoutExercise(exercise: exercise, sets: recentSets)
        let twoMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -2, to: Date()
        )!
        let recentWorkout = makeCompletedWorkout(
            startedAt: twoMonthsAgo,
            exercises: [recentExercise]
        )

        // Extended: 100kg x 5 = 100 * 1.1667 = 116.67 * 0.9 = 105.0
        let extendedSets = [makeSet(weight: 100, reps: 5)]
        let extendedExercise = makeWorkoutExercise(exercise: exercise, sets: extendedSets)
        let eightMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -8, to: Date()
        )!
        let extendedWorkout = makeCompletedWorkout(
            startedAt: eightMonthsAgo,
            exercises: [extendedExercise]
        )

        let sut = makeSUT(workouts: [recentWorkout, extendedWorkout])
        let estimate = try await sut.estimateOneRM(exerciseId: exerciseId)

        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate!.source, .recent)
        XCTAssertFalse(estimate!.isStale)
    }

    func testEstimateOneRM_wrongExerciseId_returnsNil() async throws {
        let exerciseId = UUID()
        let differentId = UUID()
        let exercise = makeExercise(id: exerciseId)
        let sets = [makeSet(weight: 100, reps: 5)]
        let workoutExercise = makeWorkoutExercise(exercise: exercise, sets: sets)

        let oneMonthAgo = Calendar.current.date(
            byAdding: .month, value: -1, to: Date()
        )!
        let workout = makeCompletedWorkout(
            startedAt: oneMonthAgo,
            exercises: [workoutExercise]
        )

        let sut = makeSUT(workouts: [workout])
        let estimate = try await sut.estimateOneRM(exerciseId: differentId)
        XCTAssertNil(estimate)
    }
}
