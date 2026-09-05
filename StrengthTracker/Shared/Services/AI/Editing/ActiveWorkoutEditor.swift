import Foundation

/// Edits the in-progress workout through the shared `WorkoutViewModel` and the
/// session coordinator, so every AI write lands in the same observable state the
/// Workout tab renders and every completion runs the same tap side effects.
@MainActor
public final class ActiveWorkoutEditor: WorkoutEditor {
    private let viewModel: WorkoutViewModel
    private let coordinator: WorkoutSessionCoordinator

    public init(viewModel: WorkoutViewModel, coordinator: WorkoutSessionCoordinator) {
        self.viewModel = viewModel
        self.coordinator = coordinator
    }

    public var scope: AIReceipt.Scope { .activeWorkout }

    public func snapshot() throws -> Workout {
        guard viewModel.isActive, let workout = viewModel.currentWorkout else {
            throw WorkoutEditError.noActiveWorkout
        }
        return workout
    }

    @discardableResult
    public func addExercise(_ exercise: Exercise, sets: [SetPrefill], restSeconds: Int?, notes: String?) async throws -> WorkoutExercise {
        _ = try snapshot()
        let built = sets.enumerated().map { $1.makeSet(order: $0 + 1) }
        let added = await viewModel.addExercise(exercise, sets: built, restTimerSeconds: restSeconds, notes: notes)
        try checkSave()
        guard let added else { throw WorkoutEditError.noActiveWorkout }
        return added
    }

    public func removeExercise(id: UUID) async throws {
        _ = try exercise(id: id)
        await viewModel.removeExercise(exerciseId: id)
        try checkSave()
    }

    public func replaceExercise(id: UUID, with exercise: Exercise) async throws {
        _ = try self.exercise(id: id)
        await viewModel.replaceExercise(exerciseId: id, with: exercise)
        try checkSave()
    }

    @discardableResult
    public func addSets(exerciseId: UUID, prefills: [SetPrefill]) async throws -> [ExerciseSet] {
        _ = try exercise(id: exerciseId)
        let built = prefills.enumerated().map { $1.makeSet(order: $0 + 1) }
        let added = await viewModel.appendSets(exerciseId: exerciseId, sets: built)
        try checkSave()
        return added
    }

    public func removeSet(exerciseId: UUID, setId: UUID) async throws {
        guard try exercise(id: exerciseId).sets.contains(where: { $0.id == setId }) else {
            throw WorkoutEditError.invalidArgument("The set is no longer in this workout.")
        }
        await viewModel.removeSet(exerciseId: exerciseId, setId: setId)
        try checkSave()
    }

    @discardableResult
    public func updateSet(exerciseId: UUID, setId: UUID, changes: SetChanges) async throws -> ExerciseSet {
        let exercise = try exercise(id: exerciseId)
        guard let current = exercise.sets.first(where: { $0.id == setId }) else {
            throw WorkoutEditError.invalidArgument("The set is no longer in this workout.")
        }
        try validateDropSetEdit(current, exerciseName: exercise.exercise.name, changes: changes)

        await WorkoutEditSupport.applySetChanges(changes, to: current, exerciseId: exerciseId, via: viewModel)
        try checkSave()

        // Completion last, so the rest timer / widget see the final values.
        if let isCompleted = changes.isCompleted {
            if isCompleted {
                try await coordinator.completeSet(exerciseId: exerciseId, setId: setId)
            } else {
                try await coordinator.uncompleteSet(exerciseId: exerciseId, setId: setId)
            }
            try checkSave()
        }

        guard let updated = try self.exercise(id: exerciseId).sets.first(where: { $0.id == setId }) else {
            throw WorkoutEditError.invalidArgument("The set is no longer in this workout.")
        }
        return updated
    }

    public func setWorkoutNotes(_ notes: String?) async throws {
        _ = try snapshot()
        await viewModel.updateNotes(notes ?? "")
        try checkSave()
    }

    public func setExerciseNotes(exerciseId: UUID, notes: String?) async throws {
        _ = try exercise(id: exerciseId)
        await viewModel.updateExerciseNotes(exerciseId: exerciseId, notes: notes ?? "")
        try checkSave()
    }

    public func setDeload(_ isDeload: Bool) async throws {
        _ = try snapshot()
        await viewModel.setDeload(isDeload)
        try checkSave()
    }

    public func commit() async {
        coordinator.refreshWidget()
    }

    private func checkSave() throws {
        if let message = viewModel.lastSaveError {
            throw WorkoutEditError.saveFailed(message)
        }
    }
}
