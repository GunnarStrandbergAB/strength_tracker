import Foundation
import Observation

@MainActor
@Observable
final class WatchWorkoutViewModel {
    var activeWorkout: Workout? = nil
    var currentExerciseIndex: Int = 0
    var isActive = false

    private let workoutRepository: any WorkoutRepository

    init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func startWorkout(name: String, exercises: [Exercise]) async {
        let workoutExercises = exercises.enumerated().map { index, exercise in
            WorkoutExercise(
                id: UUID(),
                exercise: exercise,
                order: index + 1,
                supersetGroup: nil,
                notes: nil,
                restTimerSeconds: nil,
                sets: []
            )
        }

        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            exercises: workoutExercises
        )

        do {
            activeWorkout = try await workoutRepository.save(workout)
            currentExerciseIndex = 0
            isActive = true
        } catch {
            // Offline-ready: still set workout locally even if save fails
            activeWorkout = workout
            currentExerciseIndex = 0
            isActive = true
        }
    }

    func logSet(weight: Double?, reps: Int?) async throws {
        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard currentExerciseIndex < workout.exercises.count else {
            throw WorkoutError.exerciseNotFound
        }

        let setOrder = workout.exercises[currentExerciseIndex].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
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

        workout.exercises[currentExerciseIndex].sets.append(newSet)
        activeWorkout = workout
    }

    func nextExercise() {
        guard let workout = activeWorkout else { return }
        if currentExerciseIndex < workout.exercises.count - 1 {
            currentExerciseIndex += 1
        }
    }

    func previousExercise() {
        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
        }
    }

    func completeWorkout() async throws {
        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        workout.completedAt = Date()
        activeWorkout = try await workoutRepository.save(workout)
        isActive = false
    }
}
