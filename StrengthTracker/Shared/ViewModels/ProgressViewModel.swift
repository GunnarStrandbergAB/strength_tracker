import Foundation
import Observation

@MainActor
@Observable
final class ProgressViewModel {
    var selectedExercise: Exercise? = nil
    var exercises: [Exercise] = []
    var progressionData: [(date: Date, weight: Double, reps: Int)] = []
    var isLoading = false

    var bestWeight: Double? {
        progressionData.map(\.weight).max()
    }

    var bestReps: Int? {
        progressionData.map(\.reps).max()
    }

    /// Epley formula: 1RM = weight * (1 + reps / 30)
    var estimated1RM: Double? {
        progressionData
            .map { $0.weight * (1.0 + Double($0.reps) / 30.0) }
            .max()
    }

    var totalVolume: Double {
        progressionData.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository

    init(exerciseRepository: any ExerciseRepository, workoutRepository: any WorkoutRepository) {
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
    }

    func loadExercises() async {
        isLoading = true
        do {
            exercises = try await exerciseRepository.fetchAll()
        } catch {
            exercises = []
        }
        isLoading = false
    }

    func loadProgression(for exerciseId: UUID) async {
        isLoading = true
        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            let completed = allWorkouts.filter { $0.completedAt != nil }
            var results: [(date: Date, weight: Double, reps: Int)] = []

            for workout in completed {
                for workoutExercise in workout.exercises {
                    if workoutExercise.exercise.id == exerciseId {
                        for set in workoutExercise.sets where set.isCompleted {
                            if let weight = set.weight, let reps = set.reps {
                                results.append((date: workout.startedAt, weight: weight, reps: reps))
                            }
                        }
                    }
                }
            }

            progressionData = results.sorted { $0.date < $1.date }
        } catch {
            progressionData = []
        }
        isLoading = false
    }

    func selectExercise(_ exercise: Exercise) async {
        selectedExercise = exercise
        await loadProgression(for: exercise.id)
    }
}
