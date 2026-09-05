import Foundation

/// Edits one completed workout through an AI-owned `HistoryViewModel`, so the
/// same mutators, backdating rules and `endEditing()` finalization (re-vectorize,
/// PR recalculation) apply as when the user edits in the History tab.
@MainActor
public final class HistoryWorkoutEditor: WorkoutEditor {
    private let viewModel: HistoryViewModel
    private let workoutID: UUID
    /// Peer sync hook: the UI's own HistoryViewModel mirrors each saved state.
    private let onWorkoutChanged: ((Workout) -> Void)?

    public init(viewModel: HistoryViewModel, workout: Workout, onWorkoutChanged: ((Workout) -> Void)? = nil) {
        self.viewModel = viewModel
        self.workoutID = workout.id
        self.onWorkoutChanged = onWorkoutChanged
        viewModel.selectWorkout(workout)
        viewModel.isEditing = true
    }

    public var scope: AIReceipt.Scope { .historyWorkout }

    public func snapshot() throws -> Workout {
        guard let workout = viewModel.selectedWorkout, workout.id == workoutID else {
            throw WorkoutEditError.workoutNotFound("The workout is no longer selected for editing.")
        }
        return workout
    }

    @discardableResult
    public func addExercise(_ exercise: Exercise, sets: [SetPrefill], restSeconds: Int?, notes: String?) async throws -> WorkoutExercise {
        _ = try snapshot()
        let built = sets.enumerated().map { $1.makeSet(order: $0 + 1) }
        let added = try await perform {
            await viewModel.addExercise(exercise, sets: built, restTimerSeconds: restSeconds, notes: notes)
        }
        guard let added else { throw WorkoutEditError.workoutNotFound("The workout is no longer selected for editing.") }
        return added
    }

    public func removeExercise(id: UUID) async throws {
        _ = try exercise(id: id)
        try await perform { await viewModel.removeExercise(exerciseId: id) }
    }

    public func replaceExercise(id: UUID, with exercise: Exercise) async throws {
        _ = try self.exercise(id: id)
        try await perform { await viewModel.replaceExercise(exerciseId: id, with: exercise) }
    }

    @discardableResult
    public func addSets(exerciseId: UUID, prefills: [SetPrefill]) async throws -> [ExerciseSet] {
        _ = try exercise(id: exerciseId)
        let built = prefills.enumerated().map { $1.makeSet(order: $0 + 1) }
        return try await perform { await viewModel.appendSets(exerciseId: exerciseId, sets: built) }
    }

    public func removeSet(exerciseId: UUID, setId: UUID) async throws {
        guard try exercise(id: exerciseId).sets.contains(where: { $0.id == setId }) else {
            throw WorkoutEditError.invalidArgument("The set is no longer in this workout.")
        }
        try await perform { await viewModel.removeSet(exerciseId: exerciseId, setId: setId) }
    }

    @discardableResult
    public func updateSet(exerciseId: UUID, setId: UUID, changes: SetChanges) async throws -> ExerciseSet {
        let exercise = try exercise(id: exerciseId)
        guard let current = exercise.sets.first(where: { $0.id == setId }) else {
            throw WorkoutEditError.invalidArgument("The set is no longer in this workout.")
        }
        try validateDropSetEdit(current, exerciseName: exercise.exercise.name, changes: changes)

        try await perform {
            await WorkoutEditSupport.applySetChanges(changes, to: current, exerciseId: exerciseId, via: viewModel)
            if let isCompleted = changes.isCompleted,
               let now = viewModel.selectedWorkout?.exercises
                    .first(where: { $0.id == exerciseId })?.sets.first(where: { $0.id == setId }),
               now.isCompleted != isCompleted {
                // Stamps the workout's own window (history rule), not "now".
                await viewModel.toggleSetCompletion(exerciseId: exerciseId, setId: setId)
            }
        }

        guard let updated = try self.exercise(id: exerciseId).sets.first(where: { $0.id == setId }) else {
            throw WorkoutEditError.invalidArgument("The set is no longer in this workout.")
        }
        return updated
    }

    public func setWorkoutNotes(_ notes: String?) async throws {
        _ = try snapshot()
        try await perform { await viewModel.updateNotes(notes) }
    }

    public func setExerciseNotes(exerciseId: UUID, notes: String?) async throws {
        _ = try exercise(id: exerciseId)
        try await perform { await viewModel.updateExerciseNotes(exerciseId: exerciseId, notes: notes) }
    }

    public func setDeload(_ isDeload: Bool) async throws {
        _ = try snapshot()
        try await perform { await viewModel.setDeload(isDeload) }
    }

    /// Runs the deferred history side effects once (re-vectorize, PR recalc,
    /// quality-score invalidation, widget refresh). Idempotent.
    public func commit() async {
        await viewModel.endEditing()
        if let workout = viewModel.selectedWorkout {
            onWorkoutChanged?(workout)
        }
    }

    /// Clears the VM's error, runs the mutation, rethrows a failed persist and
    /// mirrors the saved state to the UI's own instance.
    private func perform<T>(_ mutation: () async -> T) async throws -> T {
        viewModel.errorMessage = nil
        let result = await mutation()
        if let message = viewModel.errorMessage {
            viewModel.errorMessage = nil
            throw WorkoutEditError.saveFailed(message)
        }
        if let workout = viewModel.selectedWorkout {
            onWorkoutChanged?(workout)
        }
        return result
    }
}
