import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("WidgetDataService Active Workout State")
struct WidgetDataServiceTests {

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

    private func makeSet(order: Int, weight: Double, reps: Int, completed: Bool) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: order,
            setType: .normal,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: completed,
            isPersonalRecord: false,
            completedAt: completed ? Date() : nil
        )
    }

    private func makeWorkoutExercise(name: String, order: Int, sets: [ExerciseSet]) -> WorkoutExercise {
        WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(name: name),
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: sets
        )
    }

    private func makeWorkout(exercises: [WorkoutExercise]) -> Workout {
        Workout(
            id: UUID(),
            name: "Push Day",
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            exercises: exercises
        )
    }

    // MARK: - buildActiveWorkoutState

    @Test("Active exercise id overrides the first-incomplete heuristic")
    func activeIdWinsOverListOrder() {
        // Exercise A still has incomplete sets, but the user jumped to C
        let a = makeWorkoutExercise(name: "Bench", order: 1, sets: [
            makeSet(order: 1, weight: 80, reps: 8, completed: false)
        ])
        let b = makeWorkoutExercise(name: "Squat", order: 2, sets: [
            makeSet(order: 1, weight: 100, reps: 5, completed: false)
        ])
        let c = makeWorkoutExercise(name: "Deadlift", order: 3, sets: [
            makeSet(order: 1, weight: 140, reps: 5, completed: true),
            makeSet(order: 2, weight: 145, reps: 3, completed: false)
        ])
        let workout = makeWorkout(exercises: [a, b, c])

        let state = WidgetDataService().buildActiveWorkoutState(
            workout: workout, isResting: true, restEndDate: Date().addingTimeInterval(90),
            activeExerciseId: c.id
        )

        #expect(state.currentExerciseName == "Deadlift")
        #expect(state.currentExerciseId == c.id.uuidString)
        // Next set targets come from within the active exercise
        #expect(state.nextSetIndex == 1)
        #expect(state.nextSetWeight == 145)
        #expect(state.nextSetReps == 3)
        // Next exercise wraps to the first incomplete one after the active
        #expect(state.nextExerciseName == "Bench")
        #expect(state.nextExerciseId == a.id.uuidString)
    }

    @Test("Without an active id, falls back to first incomplete exercise")
    func fallbackFirstIncomplete() {
        let a = makeWorkoutExercise(name: "Bench", order: 1, sets: [
            makeSet(order: 1, weight: 80, reps: 8, completed: true)
        ])
        let b = makeWorkoutExercise(name: "Squat", order: 2, sets: [
            makeSet(order: 1, weight: 100, reps: 5, completed: false)
        ])
        let workout = makeWorkout(exercises: [a, b])

        let state = WidgetDataService().buildActiveWorkoutState(
            workout: workout, isResting: false, restEndDate: nil
        )

        #expect(state.currentExerciseName == "Squat")
        #expect(state.currentExerciseId == b.id.uuidString)
        #expect(state.nextSetIndex == 0)
        #expect(state.completedSets == 1)
        #expect(state.totalPlannedSets == 2)
    }

    @Test("Fully completed active exercise stays current in the widget")
    func completedActiveStaysCurrent() {
        let a = makeWorkoutExercise(name: "Bench", order: 1, sets: [
            makeSet(order: 1, weight: 80, reps: 8, completed: false)
        ])
        let b = makeWorkoutExercise(name: "Squat", order: 2, sets: [
            makeSet(order: 1, weight: 100, reps: 5, completed: true)
        ])
        let workout = makeWorkout(exercises: [a, b])

        let state = WidgetDataService().buildActiveWorkoutState(
            workout: workout, isResting: true, restEndDate: nil,
            activeExerciseId: b.id
        )

        // The exercise you're resting from stays current...
        #expect(state.currentExerciseName == "Squat")
        #expect(state.currentExerciseId == b.id.uuidString)
        #expect(state.nextSetIndex == nil)
        #expect(state.nextSetWeight == nil)
        // ...while the "next" line still advances to the incomplete exercise
        #expect(state.nextExerciseName == "Bench")
    }

    // MARK: - Codable backward compatibility

    @Test("Old WidgetActiveWorkout JSON without the new fields still decodes")
    func decodesLegacyPayload() throws {
        let legacy = """
        {
            "workoutName": "Push Day",
            "currentExerciseName": "Bench",
            "currentExerciseId": "\(UUID().uuidString)",
            "completedSets": 3,
            "totalPlannedSets": 12,
            "startedAt": 700000000,
            "isResting": false,
            "nextSetWeight": 80,
            "nextSetReps": 8
        }
        """
        let data = Data(legacy.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decoded = try decoder.decode(WidgetActiveWorkout.self, from: data)
        #expect(decoded.workoutName == "Push Day")
        #expect(decoded.nextSetIndex == nil)
        #expect(decoded.nextExerciseId == nil)
    }
}
