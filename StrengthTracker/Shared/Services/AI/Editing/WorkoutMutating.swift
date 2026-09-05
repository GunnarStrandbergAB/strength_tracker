import Foundation

/// The per-set / per-exercise mutators both ViewModels expose with identical
/// signatures. Lets the two editors share one ordered set-update routine so the
/// AI applies changes exactly the way the UI does (drop-set guards, RPE↔RIR
/// derivation, failure normalization).
@MainActor
protocol WorkoutMutating: AnyObject {
    func updateSetWeight(exerciseId: UUID, setId: UUID, weight: Double?) async
    func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async
    func updateSetDuration(exerciseId: UUID, setId: UUID, seconds: Int?) async
    func updateSetDistance(exerciseId: UUID, setId: UUID, meters: Double?) async
    func updateSetIntensity(exerciseId: UUID, setId: UUID, value: Double?, metric: IntensityMetric) async
    func toggleSetFailure(exerciseId: UUID, setId: UUID) async
    func updateSetType(exerciseId: UUID, setId: UUID, setType: SetType) async
    func replaceDropSets(exerciseId: UUID, setId: UUID, entries: [DropSetEntry]) async
    func removeSet(exerciseId: UUID, setId: UUID) async
    @discardableResult
    func appendSets(exerciseId: UUID, sets: [ExerciseSet]) async -> [ExerciseSet]
    func removeExercise(exerciseId: UUID) async
    func replaceExercise(exerciseId: UUID, with exercise: Exercise) async
}

extension WorkoutViewModel: WorkoutMutating {}
extension HistoryViewModel: WorkoutMutating {}

@MainActor
enum WorkoutEditSupport {
    /// Applies every non-completion field of `changes` in the order the UI
    /// semantics require: segments first (so parent-field guards see the final
    /// shape), then weight/reps/duration/distance, intensity, set type, failure.
    /// `current` must be the set as it is right now (used for failure toggling).
    static func applySetChanges(
        _ changes: SetChanges,
        to current: ExerciseSet,
        exerciseId: UUID,
        via mutator: any WorkoutMutating
    ) async {
        let setId = current.id
        var effectiveFailure = current.isFailure || current.setType == .failure

        if let segments = changes.dropSegments {
            await mutator.replaceDropSets(exerciseId: exerciseId, setId: setId, entries: segments.map { $0.makeEntry() })
            if let first = segments.first {
                effectiveFailure = first.isFailure
            }
        }
        if let weight = changes.weightKg {
            await mutator.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: weight)
        }
        if let reps = changes.reps {
            await mutator.updateSetReps(exerciseId: exerciseId, setId: setId, reps: reps)
        }
        if let seconds = changes.durationSeconds {
            await mutator.updateSetDuration(exerciseId: exerciseId, setId: setId, seconds: seconds)
        }
        if let meters = changes.distanceMeters {
            await mutator.updateSetDistance(exerciseId: exerciseId, setId: setId, meters: meters)
        }
        if let intensity = changes.intensity {
            await mutator.updateSetIntensity(exerciseId: exerciseId, setId: setId, value: intensity.value, metric: intensity.metric)
        }
        if let setType = changes.setType, setType != .dropset {
            // Legacy `.failure` is expressed via the flag; normalize to normal + flag.
            if setType == .failure {
                await mutator.updateSetType(exerciseId: exerciseId, setId: setId, setType: .normal)
                if !effectiveFailure {
                    await mutator.toggleSetFailure(exerciseId: exerciseId, setId: setId)
                    effectiveFailure = true
                }
            } else {
                await mutator.updateSetType(exerciseId: exerciseId, setId: setId, setType: setType)
            }
        }
        if let isFailure = changes.isFailure, isFailure != effectiveFailure {
            await mutator.toggleSetFailure(exerciseId: exerciseId, setId: setId)
        }
    }
}
