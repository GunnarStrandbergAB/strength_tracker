import Testing
@testable import StrengthTrackerShared
import Foundation

@Suite("WorkoutHistory Tests")
struct WorkoutHistoryTests {

    private func makeWorkout(
        name: String = "Workout",
        startedAt: Date = Date(),
        completedAt: Date? = Date(),
        exercises: [WorkoutExercise] = []
    ) -> Workout {
        Workout(
            id: UUID(),
            name: name,
            startedAt: startedAt,
            completedAt: completedAt,
            notes: nil,
            templateId: nil,
            exercises: exercises
        )
    }

    private func makeExercise() -> Exercise {
        Exercise(
            id: UUID(),
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeWorkoutExercise(weight: Double, reps: Int) -> WorkoutExercise {
        let set = ExerciseSet(
            id: UUID(),
            order: 0,
            setType: .normal,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )
        return WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: [set]
        )
    }

    // MARK: - Empty history

    @Test("Empty history returns zero for all aggregates")
    func testEmptyHistory() {
        let history = WorkoutHistory(id: UUID(), workouts: [])

        #expect(history.completedWorkouts.isEmpty)
        #expect(history.sortedByDate.isEmpty)
        #expect(history.totalWorkouts == 0)
        #expect(history.totalVolume == 0)
        #expect(history.averageDuration == nil)
    }

    // MARK: - Filtering completed vs in-progress

    @Test("completedWorkouts filters out in-progress workouts")
    func testCompletedWorkoutsFiltering() {
        let completed = makeWorkout(name: "Done", completedAt: Date())
        let inProgress = makeWorkout(name: "Active", completedAt: nil)

        let history = WorkoutHistory(id: UUID(), workouts: [completed, inProgress])

        #expect(history.completedWorkouts.count == 1)
        #expect(history.completedWorkouts.first?.name == "Done")
        #expect(history.totalWorkouts == 1)
    }

    // MARK: - Sorting

    @Test("sortedByDate returns workouts newest first")
    func testSortedByDate() {
        let older = makeWorkout(name: "Old", startedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeWorkout(name: "New", startedAt: Date(timeIntervalSince1970: 2000))

        let history = WorkoutHistory(id: UUID(), workouts: [older, newer])

        #expect(history.sortedByDate.first?.name == "New")
        #expect(history.sortedByDate.last?.name == "Old")
    }

    // MARK: - Total volume

    @Test("totalVolume sums volume of completed workouts only")
    func testTotalVolume() {
        let ex = makeWorkoutExercise(weight: 100, reps: 10) // 1000
        let completed = makeWorkout(completedAt: Date(), exercises: [ex])
        let inProgress = makeWorkout(completedAt: nil, exercises: [ex])

        let history = WorkoutHistory(id: UUID(), workouts: [completed, inProgress])

        #expect(history.totalVolume == 1000.0)
    }

    // MARK: - Average duration

    @Test("averageDuration computes average of completed workouts with duration")
    func testAverageDuration() {
        let start = Date()
        let w1 = makeWorkout(startedAt: start, completedAt: start.addingTimeInterval(3600))
        let w2 = makeWorkout(startedAt: start, completedAt: start.addingTimeInterval(1800))

        let history = WorkoutHistory(id: UUID(), workouts: [w1, w2])

        #expect(history.averageDuration == 2700.0)
    }

    @Test("averageDuration returns nil when no completed workouts have duration")
    func testAverageDurationNilWhenNoDurations() {
        let history = WorkoutHistory(id: UUID(), workouts: [])

        #expect(history.averageDuration == nil)
    }

    // MARK: - Weekly streak

    @Test("currentWeeklyStreak returns 0 for empty history")
    func testStreakEmpty() {
        let history = WorkoutHistory(id: UUID(), workouts: [])

        #expect(history.currentWeeklyStreak() == 0)
    }

    @Test("currentWeeklyStreak counts consecutive weeks with workouts")
    func testStreakConsecutiveWeeks() {
        let calendar = Calendar.current
        let now = Date()
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!

        let w1 = makeWorkout(startedAt: now, completedAt: now)
        let w2 = makeWorkout(startedAt: lastWeek, completedAt: lastWeek)

        let history = WorkoutHistory(id: UUID(), workouts: [w1, w2])

        #expect(history.currentWeeklyStreak() >= 2)
    }

    // MARK: - Workouts by month

    @Test("workoutsByMonth groups completed workouts by yyyy-MM")
    func testWorkoutsByMonth() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let jan = formatter.date(from: "2025-01-15")!
        let feb = formatter.date(from: "2025-02-10")!

        let w1 = makeWorkout(startedAt: jan, completedAt: jan)
        let w2 = makeWorkout(startedAt: feb, completedAt: feb)

        let history = WorkoutHistory(id: UUID(), workouts: [w1, w2])
        let grouped = history.workoutsByMonth()

        #expect(grouped["2025-01"]?.count == 1)
        #expect(grouped["2025-02"]?.count == 1)
    }

    // MARK: - Codable roundtrip

    @Test("WorkoutHistory encodes and decodes correctly")
    func testCodableRoundtrip() throws {
        let workout = makeWorkout(name: "Test Workout", completedAt: Date())
        let history = WorkoutHistory(id: UUID(), workouts: [workout])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutHistory.self, from: data)

        #expect(decoded.id == history.id)
        #expect(decoded.workouts.count == 1)
        #expect(decoded.workouts.first?.name == "Test Workout")
    }

    // MARK: - Identifiable & Hashable

    @Test("WorkoutHistory conforms to Identifiable and Hashable")
    func testIdentifiableHashable() {
        let id = UUID()
        let h1 = WorkoutHistory(id: id, workouts: [])
        let h2 = WorkoutHistory(id: id, workouts: [])

        #expect(h1.id == h2.id)
        #expect(h1 == h2)
        #expect(h1.hashValue == h2.hashValue)
    }
}
