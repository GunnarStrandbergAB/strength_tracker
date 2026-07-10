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
    public let userPreferencesService: UserPreferencesService?

    public init(
        workoutRepository: any WorkoutRepository,
        userPreferencesService: UserPreferencesService? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
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
                        // One point per performed segment so drop-set parts feed the
                        // charts like any other effort.
                        for part in set.effectiveParts {
                            if let weight = part.weight, let reps = part.reps {
                                results.append((date: workout.startedAt, weight: weight, reps: reps))
                            }
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
        // Parent fields of a grouped drop set mirror its top segment — edit the segment instead.
        guard workout.exercises[ei].sets[si].dropSets.isEmpty else { return }
        workout.exercises[ei].sets[si].weight = weight
        await saveAndSync(workout)
    }

    public func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        guard workout.exercises[ei].sets[si].dropSets.isEmpty else { return }
        workout.exercises[ei].sets[si].reps = reps
        await saveAndSync(workout)
    }

    public func updateSetType(exerciseId: UUID, setId: UUID, setType: SetType) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        // A grouped drop set's type is managed by applyDropSets — never silently
        // destroy its segments by retyping it.
        guard workout.exercises[ei].sets[si].dropSets.isEmpty else { return }
        workout.exercises[ei].sets[si].setType = setType
        await saveAndSync(workout)
    }

    public func toggleSetCompletion(exerciseId: UUID, setId: UUID) async {
        guard var workout = selectedWorkout,
              workout.toggleSetCompletion(exerciseId: exerciseId, setId: setId) != nil else { return }
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

    // MARK: - Delete Workout

    public func deleteWorkout(_ workout: Workout) async {
        do {
            try await workoutRepository.delete(workout)
            workouts.removeAll { $0.id == workout.id }
            if selectedWorkout?.id == workout.id {
                selectedWorkout = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Intensity & Failure Editing

    public func updateSetRPE(exerciseId: UUID, setId: UUID, rpe: Double?) async {
        await updateSetIntensity(exerciseId: exerciseId, setId: setId, value: rpe, metric: .rpe)
    }

    public func updateSetIntensity(exerciseId: UUID, setId: UUID, value: Double?, metric: IntensityMetric) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        workout.exercises[ei].sets[si].applyIntensity(value, metric: metric)
        await saveAndSync(workout)
    }

    public func toggleSetFailure(exerciseId: UUID, setId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        var set = workout.exercises[ei].sets[si]
        let effective = set.isFailure || set.setType == .failure
        // Normalize legacy failure-typed rows into the per-set flag on first touch.
        if set.setType == .failure { set.setType = .normal }
        set.setFailureFlag(!effective)
        workout.exercises[ei].sets[si] = set
        await saveAndSync(workout)
    }

    // MARK: - Drop Set Editing

    public func addDropEntry(exerciseId: UUID, setId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        var set = workout.exercises[ei].sets[si]
        if set.dropSets.isEmpty {
            // Convert: current values become the top segment, plus one empty entry to fill in.
            let top = DropSetEntry(weight: set.weight, reps: set.reps, rpe: set.rpe, rir: set.rir, isFailure: set.isFailure)
            set.applyDropSets([top, DropSetEntry()])
        } else {
            set.applyDropSets(set.dropSets + [DropSetEntry()])
        }
        workout.exercises[ei].sets[si] = set
        await saveAndSync(workout)
    }

    public func removeDropEntry(exerciseId: UUID, setId: UUID, entryId: UUID) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }) else { return }
        var set = workout.exercises[ei].sets[si]
        var entries = set.dropSets
        entries.removeAll { $0.id == entryId }
        if entries.count == 1, let survivor = entries.first {
            // Collapse back to a plain set carrying the surviving segment's values.
            set.applyDropSets([survivor])
            set.applyDropSets([])
        } else {
            set.applyDropSets(entries)
        }
        workout.exercises[ei].sets[si] = set
        await saveAndSync(workout)
    }

    public func updateDropEntryWeight(exerciseId: UUID, setId: UUID, entryId: UUID, weight: Double?) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.weight = weight }
    }

    public func updateDropEntryReps(exerciseId: UUID, setId: UUID, entryId: UUID, reps: Int?) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.reps = reps }
    }

    public func updateDropEntryIntensity(exerciseId: UUID, setId: UUID, entryId: UUID, value: Double?, metric: IntensityMetric) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.applyIntensity(value, metric: metric) }
    }

    public func toggleDropEntryFailure(exerciseId: UUID, setId: UUID, entryId: UUID) async {
        await mutateDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) { $0.setFailureFlag(!$0.isFailure) }
    }

    private func mutateDropEntry(exerciseId: UUID, setId: UUID, entryId: UUID, _ mutate: (inout DropSetEntry) -> Void) async {
        guard var workout = selectedWorkout,
              let ei = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let si = workout.exercises[ei].sets.firstIndex(where: { $0.id == setId }),
              let di = workout.exercises[ei].sets[si].dropSets.firstIndex(where: { $0.id == entryId }) else { return }
        var set = workout.exercises[ei].sets[si]
        var entries = set.dropSets
        mutate(&entries[di])
        set.applyDropSets(entries)
        workout.exercises[ei].sets[si] = set
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
