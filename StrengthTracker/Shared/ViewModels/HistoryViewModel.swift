import Foundation
import Observation

@MainActor
@Observable
public final class HistoryViewModel {
    public var workouts: [Workout] = []
    public var selectedWorkout: Workout? = nil
    public var isLoading = false
    public var errorMessage: String? = nil

    private let workoutRepository: any WorkoutRepository

    public init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    public func loadHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await workoutRepository.fetchAll()
            workouts = all.filter { $0.completedAt != nil }
        } catch {
            errorMessage = error.localizedDescription
            workouts = []
        }
        isLoading = false
    }

    public func selectWorkout(_ workout: Workout) {
        selectedWorkout = workout
    }

    public func exerciseProgression(for exerciseId: UUID) -> [(date: Date, weight: Double, reps: Int)] {
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
