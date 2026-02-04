import Testing
@testable import StrengthTrackerShared
import Foundation

@Suite("ExerciseSet Tests")
struct ExerciseSetTests {

    @Test("ExerciseSet creation with weight, reps, and RPE")
    func testCreationWithWeightRepsRPE() {
        let set = ExerciseSet(
            id: UUID(),
            order: 0,
            setType: .normal,
            weight: 100.0,
            reps: 8,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: 8.5,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )

        #expect(set.weight == 100.0)
        #expect(set.reps == 8)
        #expect(set.rpe == 8.5)
        #expect(set.setType == .normal)
        #expect(set.isCompleted == true)
    }

    @Test("setVolume returns weight * reps for completed normal set")
    func testSetVolumeCompletedNormal() {
        let set = ExerciseSet(
            id: UUID(),
            order: 0,
            setType: .normal,
            weight: 100.0,
            reps: 10,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )

        #expect(set.setVolume == 1000.0)
    }

    @Test("setVolume returns 0 for warmup set")
    func testSetVolumeWarmup() {
        let set = ExerciseSet(
            id: UUID(),
            order: 0,
            setType: .warmup,
            weight: 60.0,
            reps: 10,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )

        #expect(set.setVolume == 0.0)
    }

    @Test("setVolume returns 0 when isCompleted is false")
    func testSetVolumeNotCompleted() {
        let set = ExerciseSet(
            id: UUID(),
            order: 0,
            setType: .normal,
            weight: 100.0,
            reps: 10,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: false,
            isPersonalRecord: false,
            completedAt: nil
        )

        #expect(set.setVolume == 0.0)
    }

    @Test("setVolume returns 0 when weight is zero")
    func testSetVolumeZeroWeight() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 0.0, reps: 10,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.setVolume == 0.0)
    }

    @Test("setVolume returns 0 when reps is zero")
    func testSetVolumeZeroReps() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: 100.0, reps: 0,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.setVolume == 0.0)
    }

    @Test("setVolume returns 0 when both weight and reps are nil")
    func testSetVolumeNilWeightNilReps() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: nil, reps: nil,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.setVolume == 0.0)
    }

    @Test("setVolume returns 0 when weight is nil but reps is valid")
    func testSetVolumeNilWeightValidReps() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .normal,
            weight: nil, reps: 10,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.setVolume == 0.0)
    }

    @Test("setVolume counts dropset type")
    func testSetVolumeDropset() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .dropset,
            weight: 80.0, reps: 12,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.setVolume == 960.0)
    }

    @Test("setVolume counts failure type")
    func testSetVolumeFailure() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .failure,
            weight: 90.0, reps: 5,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.setVolume == 450.0)
    }

    @Test("setVolume counts restPause type")
    func testSetVolumeRestPause() {
        let set = ExerciseSet(
            id: UUID(), order: 0, setType: .restPause,
            weight: 70.0, reps: 8,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: true, isPersonalRecord: false, completedAt: Date()
        )
        #expect(set.setVolume == 560.0)
    }
}

@Suite("WorkoutExercise Tests")
struct WorkoutExerciseTests {

    private func makeExercise() -> Exercise {
        Exercise(
            id: UUID(),
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    @Test("exerciseVolume sums all completed non-warmup set volumes")
    func testExerciseVolume() {
        let sets: [ExerciseSet] = [
            ExerciseSet(id: UUID(), order: 0, setType: .warmup, weight: 60.0, reps: 10,
                        durationSeconds: nil, distanceMeters: nil, rpe: nil,
                        isCompleted: true, isPersonalRecord: false, completedAt: Date()),
            ExerciseSet(id: UUID(), order: 1, setType: .normal, weight: 100.0, reps: 8,
                        durationSeconds: nil, distanceMeters: nil, rpe: 7.0,
                        isCompleted: true, isPersonalRecord: false, completedAt: Date()),
            ExerciseSet(id: UUID(), order: 2, setType: .normal, weight: 100.0, reps: 8,
                        durationSeconds: nil, distanceMeters: nil, rpe: 8.0,
                        isCompleted: true, isPersonalRecord: false, completedAt: Date()),
            ExerciseSet(id: UUID(), order: 3, setType: .normal, weight: 100.0, reps: 6,
                        durationSeconds: nil, distanceMeters: nil, rpe: 9.0,
                        isCompleted: false, isPersonalRecord: false, completedAt: nil),
        ]

        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            sets: sets
        )

        // warmup: 0, set1: 800, set2: 800, set3: 0 (not completed)
        #expect(workoutExercise.exerciseVolume == 1600.0)
    }

    @Test("exerciseVolume returns 0 for empty sets array")
    func testExerciseVolumeEmptySets() {
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: []
        )
        #expect(workoutExercise.exerciseVolume == 0.0)
    }
}

@Suite("Workout Tests")
struct WorkoutTests {

    private func makeExercise() -> Exercise {
        Exercise(
            id: UUID(),
            name: "Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeWorkoutExercise(setVolumes: [(weight: Double, reps: Int)]) -> WorkoutExercise {
        let sets = setVolumes.enumerated().map { index, pair in
            ExerciseSet(
                id: UUID(),
                order: index,
                setType: .normal,
                weight: pair.weight,
                reps: pair.reps,
                durationSeconds: nil,
                distanceMeters: nil,
                rpe: nil,
                isCompleted: true,
                isPersonalRecord: false,
                completedAt: Date()
            )
        }
        return WorkoutExercise(
            id: UUID(),
            exercise: makeExercise(),
            order: 0,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: sets
        )
    }

    @Test("Workout creation with date and exercises")
    func testWorkoutCreation() {
        let startDate = Date()
        let workout = Workout(
            id: UUID(),
            name: "Leg Day",
            startedAt: startDate,
            completedAt: nil,
            notes: "Felt strong",
            templateId: nil,
            exercises: []
        )

        #expect(workout.name == "Leg Day")
        #expect(workout.startedAt == startDate)
        #expect(workout.isInProgress == true)
        #expect(workout.notes == "Felt strong")
    }

    @Test("totalVolume sums all exercise volumes")
    func testTotalVolume() {
        let ex1 = makeWorkoutExercise(setVolumes: [(100, 10), (100, 8)])   // 1000 + 800 = 1800
        let ex2 = makeWorkoutExercise(setVolumes: [(60, 12), (60, 10)])    // 720 + 600 = 1320

        let workout = Workout(
            id: UUID(),
            name: "Full Body",
            startedAt: Date(),
            completedAt: Date(),
            notes: nil,
            templateId: nil,
            exercises: [ex1, ex2]
        )

        #expect(workout.totalVolume == 3120.0)
    }

    @Test("duration returns completedAt minus startedAt")
    func testDuration() {
        let start = Date()
        let end = start.addingTimeInterval(3600) // 1 hour

        let workout = Workout(
            id: UUID(),
            name: "Push Day",
            startedAt: start,
            completedAt: end,
            notes: nil,
            templateId: nil,
            exercises: []
        )

        #expect(workout.duration == 3600.0)
    }

    @Test("duration returns nil when completedAt is nil")
    func testDurationNilWhenNotCompleted() {
        let workout = Workout(
            id: UUID(),
            name: "Push Day",
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            exercises: []
        )

        #expect(workout.duration == nil)
    }

    @Test("isInProgress is true when completedAt is nil")
    func testIsInProgressWhenNotCompleted() {
        let workout = Workout(
            id: UUID(),
            name: "Morning Lift",
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            exercises: []
        )

        #expect(workout.isInProgress == true)
    }

    @Test("isInProgress is false when completedAt is set")
    func testIsNotInProgressWhenCompleted() {
        let workout = Workout(
            id: UUID(),
            name: "Morning Lift",
            startedAt: Date(),
            completedAt: Date(),
            notes: nil,
            templateId: nil,
            exercises: []
        )

        #expect(workout.isInProgress == false)
    }

    @Test("totalVolume returns 0 for empty exercises array")
    func testTotalVolumeEmptyExercises() {
        let workout = Workout(
            id: UUID(),
            name: "Empty",
            startedAt: Date(),
            completedAt: Date(),
            notes: nil,
            templateId: nil,
            exercises: []
        )
        #expect(workout.totalVolume == 0.0)
    }

    @Test("Workout Codable roundtrip preserves all fields")
    func testCodableRoundtrip() throws {
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let templateId = UUID()

        let workout = Workout(
            id: UUID(),
            name: "Codable Test",
            startedAt: start,
            completedAt: end,
            notes: "Some notes",
            templateId: templateId,
            exercises: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workout)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workout.self, from: data)

        #expect(decoded.id == workout.id)
        #expect(decoded.name == "Codable Test")
        #expect(decoded.notes == "Some notes")
        #expect(decoded.templateId == templateId)
        #expect(decoded.completedAt != nil)
        #expect(decoded.isInProgress == false)
    }

    @Test("duration handles negative value when completedAt is before startedAt")
    func testNegativeDuration() {
        let start = Date()
        let beforeStart = start.addingTimeInterval(-600) // 10 minutes before

        let workout = Workout(
            id: UUID(),
            name: "Time Travel",
            startedAt: start,
            completedAt: beforeStart,
            notes: nil,
            templateId: nil,
            exercises: []
        )

        #expect(workout.duration != nil)
        #expect(workout.duration! < 0)
    }
}
