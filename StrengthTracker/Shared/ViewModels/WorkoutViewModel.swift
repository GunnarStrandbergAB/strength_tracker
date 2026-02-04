import Foundation
import Observation

enum WorkoutError: Error, Sendable {
    case noActiveWorkout
    case exerciseNotFound
}

@MainActor
@Observable
final class WorkoutViewModel {
    var currentWorkout: Workout? = nil
    var isActive = false
    var errorMessage: String? = nil

    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository

    init(workoutRepository: any WorkoutRepository, templateRepository: any TemplateRepository) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
    }

    func startWorkout(name: String, from template: WorkoutTemplate? = nil) async {
        var exercises: [WorkoutExercise] = []

        if let template = template {
            exercises = template.exercises.enumerated().map { index, te in
                WorkoutExercise(
                    id: UUID(),
                    exercise: te.exercise,
                    order: index + 1,
                    supersetGroup: te.supersetGroup,
                    notes: te.notes,
                    restTimerSeconds: te.restTimerSeconds,
                    sets: []
                )
            }
        }

        var workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: template?.id,
            exercises: exercises
        )

        do {
            workout = try await workoutRepository.save(workout)
            currentWorkout = workout
            isActive = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addExercise(_ exercise: Exercise) {
        guard var workout = currentWorkout else { return }
        let order = workout.exercises.count + 1
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: []
        )
        workout.exercises.append(workoutExercise)
        currentWorkout = workout
    }

    func logSet(exerciseId: UUID, weight: Double?, reps: Int?, setType: SetType = .normal) async throws {
        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.exercise.id == exerciseId }) else {
            throw WorkoutError.exerciseNotFound
        }

        let setOrder = workout.exercises[exerciseIndex].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )

        workout.exercises[exerciseIndex].sets.append(newSet)
        currentWorkout = workout
    }

    func completeWorkout() async throws {
        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        workout.completedAt = Date()
        let saved = try await workoutRepository.save(workout)
        currentWorkout = saved
        isActive = false
    }
}
