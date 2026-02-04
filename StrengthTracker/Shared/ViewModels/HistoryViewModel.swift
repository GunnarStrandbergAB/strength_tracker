import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    var workouts: [Workout] = []
    var selectedWorkout: Workout? = nil
    var isLoading = false

    private let workoutRepository: any WorkoutRepository

    init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func loadHistory() async {
        isLoading = true
        do {
            let all = try await workoutRepository.fetchAll()
            workouts = all.filter { $0.completedAt != nil }
        } catch {
            workouts = []
        }
        isLoading = false
    }

    func selectWorkout(_ workout: Workout) {
        selectedWorkout = workout
    }

    func exerciseProgression(for exerciseId: UUID) -> [(date: Date, weight: Double, reps: Int)] {
        var results: [(date: Date, weight: Double, reps: Int)] = []

        for workout in workouts {
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

        return results.sorted { $0.date < $1.date }
    }
}
