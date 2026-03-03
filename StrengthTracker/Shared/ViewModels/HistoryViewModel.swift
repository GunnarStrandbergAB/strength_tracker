import Foundation
import Observation

@MainActor
@Observable
public final class HistoryViewModel {
    public var workouts: [Workout] = []
    public var selectedWorkout: Workout? = nil
    public var isLoading = false
    public var isEditing = false
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

    // MARK: - Inline Editing (History)

    public func updateSetWeight(exerciseId: UUID, setId: UUID, weight: Double?) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        workout.exercises[ei].sets[si].weight = weight
        await saveAndSync(workout)
    }

    public func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        workout.exercises[ei].sets[si].reps = reps
        await saveAndSync(workout)
    }

    public func updateSetType(exerciseId: UUID, setId: UUID, setType: SetType) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        workout.exercises[ei].sets[si].setType = setType
        await saveAndSync(workout)
    }

    public func toggleSetCompletion(exerciseId: UUID, setId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        let wasCompleted = workout.exercises[ei].sets[si].isCompleted
        workout.exercises[ei].sets[si].isCompleted = !wasCompleted
        workout.exercises[ei].sets[si].completedAt = wasCompleted ? nil : Date()
        await saveAndSync(workout)
    }

    public func addEmptySet(exerciseId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let setOrder = workout.exercises[ei].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
            setType: .normal,
            weight: nil,
            reps: nil,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: false,
            isPersonalRecord: false,
            completedAt: nil
        )
        workout.exercises[ei].sets.append(newSet)
        await saveAndSync(workout)
    }

    public func removeLastSet(exerciseId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              !workout.exercises[ei].sets.isEmpty else { return }
        workout.exercises[ei].sets.removeLast()
        await saveAndSync(workout)
    }

    // MARK: - Save Helper

    private func saveAndSync(_ workout: Workout) async {
        do {
            let saved = try await workoutRepository.save(workout)
            selectedWorkout = saved
            // Update the workouts array so the list reflects changes
            if let index = workouts.firstIndex(where: { $0.id == saved.id }) {
                workouts[index] = saved
            }
        } catch {
            // Revert on failure
            selectedWorkout = workout
        }
    }
}
