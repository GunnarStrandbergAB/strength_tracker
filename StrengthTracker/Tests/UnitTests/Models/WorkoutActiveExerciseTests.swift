import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("Workout Active Exercise")
struct WorkoutActiveExerciseTests {

    // MARK: - Helpers

    private func makeExercise(name: String) -> Exercise {
        Exercise(
            id: UUID(),
            name: name,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeSet(order: Int, completed: Bool, completedAt: Date? = nil) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: order,
            setType: .normal,
            weight: 100,
            reps: 8,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: completed,
            isPersonalRecord: false,
            completedAt: completed ? (completedAt ?? Date()) : nil
        )
    }

    /// Builds a WorkoutExercise with one set per entry in `setStates` (true = completed).
    private func makeWorkoutExercise(name: String, order: Int, setStates: [Bool], completedAt: Date? = nil) -> WorkoutExercise {
        WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(name: name),
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: setStates.enumerated().map { i, done in
                makeSet(order: i + 1, completed: done, completedAt: completedAt)
            }
        )
    }

    private func makeWorkout(exercises: [WorkoutExercise]) -> Workout {
        Workout(
            id: UUID(),
            name: "Test",
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            exercises: exercises
        )
    }

    // MARK: - activeExercise(preferredId:)

    @Test("Preferred exercise with incomplete sets stays active")
    func preferredWithIncompleteStays() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false, false])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true, false])
        let workout = makeWorkout(exercises: [a, b])

        let active = workout.activeExercise(preferredId: b.id)
        #expect(active?.id == b.id)
    }

    @Test("Fully complete preferred exercise advances to next incomplete")
    func preferredCompleteAdvances() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true, true])
        let c = makeWorkoutExercise(name: "C", order: 3, setStates: [false])
        let workout = makeWorkout(exercises: [a, b, c])

        let active = workout.activeExercise(preferredId: b.id)
        #expect(active?.id == c.id)
    }

    @Test("Advance wraps past the end back to the first incomplete")
    func preferredCompleteWraps() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true])
        let c = makeWorkoutExercise(name: "C", order: 3, setStates: [true])
        let workout = makeWorkout(exercises: [a, b, c])

        let active = workout.activeExercise(preferredId: c.id)
        #expect(active?.id == a.id)
    }

    @Test("All exercises complete — stays on preferred")
    func allCompleteStaysOnPreferred() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [true])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true])
        let workout = makeWorkout(exercises: [a, b])

        let active = workout.activeExercise(preferredId: b.id)
        #expect(active?.id == b.id)
    }

    @Test("Nil preference falls back to first incomplete")
    func nilPreferenceFirstIncomplete() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [true])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [false])
        let workout = makeWorkout(exercises: [a, b])

        let active = workout.activeExercise(preferredId: nil)
        #expect(active?.id == b.id)
    }

    @Test("Nil preference with everything complete falls back to last")
    func nilPreferenceAllCompleteLast() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [true])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true])
        let workout = makeWorkout(exercises: [a, b])

        let active = workout.activeExercise(preferredId: nil)
        #expect(active?.id == b.id)
    }

    @Test("Unknown preferred id falls back to heuristic")
    func unknownPreferredFallsBack() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false])
        let workout = makeWorkout(exercises: [a])

        let active = workout.activeExercise(preferredId: UUID())
        #expect(active?.id == a.id)
    }

    @Test("Empty workout has no active exercise")
    func emptyWorkoutNil() {
        let workout = makeWorkout(exercises: [])
        let active = workout.activeExercise(preferredId: nil)
        #expect(active == nil)
    }

    // MARK: - nextIncompleteExercise(afterId:)

    @Test("Next incomplete exercise skips completed ones and excludes self")
    func nextIncompleteSkipsCompleted() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true])
        let c = makeWorkoutExercise(name: "C", order: 3, setStates: [false])
        let workout = makeWorkout(exercises: [a, b, c])

        let next = workout.nextIncompleteExercise(afterId: a.id)
        #expect(next?.id == c.id)
    }

    @Test("Next incomplete exercise wraps to the top")
    func nextIncompleteWraps() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [false])
        let workout = makeWorkout(exercises: [a, b])

        let next = workout.nextIncompleteExercise(afterId: b.id)
        #expect(next?.id == a.id)
    }

    @Test("Next incomplete exercise is nil when no other exercise has work left")
    func nextIncompleteNilWhenAlone() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false])
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true])
        let workout = makeWorkout(exercises: [a, b])

        let next = workout.nextIncompleteExercise(afterId: a.id)
        #expect(next == nil)
    }

    // MARK: - lastInteractedExerciseId

    @Test("Last interacted exercise is the one with the newest completedAt")
    func lastInteractedNewestWins() {
        let earlier = Date(timeIntervalSinceNow: -600)
        let later = Date(timeIntervalSinceNow: -60)
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [true], completedAt: later)
        let b = makeWorkoutExercise(name: "B", order: 2, setStates: [true, false], completedAt: earlier)
        let workout = makeWorkout(exercises: [a, b])

        #expect(workout.lastInteractedExerciseId == a.id)
    }

    @Test("Last interacted is nil when nothing is completed")
    func lastInteractedNilWhenUntouched() {
        let a = makeWorkoutExercise(name: "A", order: 1, setStates: [false])
        let workout = makeWorkout(exercises: [a])

        #expect(workout.lastInteractedExerciseId == nil)
    }
}
