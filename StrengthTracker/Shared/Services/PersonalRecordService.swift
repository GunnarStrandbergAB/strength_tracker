import Foundation

/// Personal records: live detection while training, and the authoritative
/// per-exercise rebuild that runs after every completed mutation.
///
/// Invariants maintained here:
/// - exactly ONE automatic row per (exercise, record type); manual rows (`setId == nil`) survive;
/// - deload workouts never produce records (live and rebuild agree);
/// - `ExerciseSet.isPersonalRecord` is true exactly on the sets that hold a current record;
/// - every effective-load part (drop segments included) is a candidate, with the
///   owning set's own exercise snapshot (bodyweight factor) applied.
@MainActor
public final class PersonalRecordService {
    private let personalRecordRepository: any PersonalRecordRepository
    private let workoutRepository: any WorkoutRepository
    private let userPreferencesService: UserPreferencesService?
    private let bodyWeightProvider: BodyWeightProvider?

    public init(
        personalRecordRepository: any PersonalRecordRepository,
        workoutRepository: any WorkoutRepository,
        userPreferencesService: UserPreferencesService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil
    ) {
        self.personalRecordRepository = personalRecordRepository
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
        self.bodyWeightProvider = bodyWeightProvider
    }

    private var bodyWeightKg: Double {
        bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    // MARK: - Live check

    /// Checks a just-completed set against the current records and replaces any
    /// beaten automatic row. Returns the most significant new record; the caller
    /// sets `isPersonalRecord` on the set and persists the workout.
    public func checkForPR(exercise: Exercise, set: ExerciseSet, isDeloadWorkout: Bool = false) async throws -> PersonalRecord? {
        guard !isDeloadWorkout, set.isCompleted, set.setType != .warmup else { return nil }

        let existing = try await personalRecordRepository.fetchForExercise(exercise.id)
        let candidates = Self.candidateRecords(exerciseId: exercise.id, exercise: exercise, set: set, bodyWeightKg: bodyWeightKg)

        var newRecords: [PersonalRecord] = []
        for candidate in candidates {
            let best = existing.filter { $0.recordType == candidate.recordType }.map(\.value).max() ?? 0
            if candidate.value > best { newRecords.append(candidate) }
        }
        guard !newRecords.isEmpty else { return nil }

        // One automatic row per type: the beaten rows go, everything else stays.
        let beatenTypes = Set(newRecords.map(\.recordType))
        let survivors = existing.filter { $0.setId != nil && !beatenTypes.contains($0.recordType) }
        try await personalRecordRepository.replace(records: survivors + newRecords, forExercise: exercise.id, keepingManual: true)

        return Self.mostSignificant(newRecords)
    }

    /// Reverse of a live PR (set un-completed or edited): re-elects the exercise's
    /// records from history — including the in-progress workout — so the previous
    /// best comes back.
    public func revokePR(exerciseId: UUID) async throws {
        _ = try await recalculatePRs(for: [exerciseId], includeInProgress: true)
    }

    /// Save a manually entered personal record
    public func saveManualRecord(_ record: PersonalRecord) async throws -> PersonalRecord {
        return try await personalRecordRepository.save(record)
    }

    /// Get all personal records for an exercise, sorted by achieved date descending
    public func getRecords(for exerciseId: UUID) async throws -> [PersonalRecord] {
        let records = try await personalRecordRepository.fetchForExercise(exerciseId)
        return records.sorted { $0.achievedAt > $1.achievedAt }
    }

    // MARK: - Rebuild

    /// Rebuilds the records of the given exercises from completed, non-deload
    /// workouts (one row per type, manual rows preserved), then sets/clears
    /// `isPersonalRecord` on every set of those exercises and persists only the
    /// workouts whose flags changed. Returns those persisted workouts by id.
    /// `includeInProgress` also lets the active workout's completed sets compete
    /// (live re-election during a session); the finalizer's authoritative rebuild
    /// at completion leaves it false.
    @discardableResult
    public func recalculatePRs(for exerciseIds: Set<UUID>, includeInProgress: Bool = false) async throws -> [UUID: Workout] {
        guard !exerciseIds.isEmpty else { return [:] }
        let allWorkouts = try await workoutRepository.fetchAll()
        let eligible = allWorkouts.filter { ($0.completedAt != nil || includeInProgress) && !$0.isDeload }
        let bodyWeight = bodyWeightKg

        var winningSetIds = Set<UUID>()
        for exerciseId in exerciseIds {
            var elected: [RecordType: PersonalRecord] = [:]
            for workout in eligible {
                for workoutExercise in workout.exercises where workoutExercise.exercise.id == exerciseId {
                    for set in workoutExercise.sets where set.isCompleted && set.setType != .warmup {
                        for candidate in Self.candidateRecords(
                            exerciseId: exerciseId, exercise: workoutExercise.exercise, set: set, bodyWeightKg: bodyWeight
                        ) {
                            if let current = elected[candidate.recordType] {
                                if candidate.value > current.value
                                    || (candidate.value == current.value && candidate.achievedAt > current.achievedAt) {
                                    elected[candidate.recordType] = candidate
                                }
                            } else {
                                elected[candidate.recordType] = candidate
                            }
                        }
                    }
                }
            }
            let records = Array(elected.values)
            try await personalRecordRepository.replace(records: records, forExercise: exerciseId, keepingManual: true)
            winningSetIds.formUnion(records.compactMap(\.setId))
        }

        // Flag pass: only the winning sets carry the badge.
        var changed: [UUID: Workout] = [:]
        for var workout in allWorkouts {
            var dirty = false
            for ei in workout.exercises.indices where exerciseIds.contains(workout.exercises[ei].exercise.id) {
                for si in workout.exercises[ei].sets.indices {
                    let desired = winningSetIds.contains(workout.exercises[ei].sets[si].id)
                    if workout.exercises[ei].sets[si].isPersonalRecord != desired {
                        workout.exercises[ei].sets[si].isPersonalRecord = desired
                        dirty = true
                    }
                }
            }
            if dirty {
                changed[workout.id] = try await workoutRepository.save(workout)
            }
        }
        return changed
    }

    /// Full rebuild across every exercise that has history or records. Also
    /// removes automatic rows for exercises that no longer appear in any workout.
    public func recalculateAllPRs() async throws {
        let allWorkouts = try await workoutRepository.fetchAll()
        var exerciseIds = Set<UUID>()
        for workout in allWorkouts where workout.completedAt != nil {
            for workoutExercise in workout.exercises {
                exerciseIds.insert(workoutExercise.exercise.id)
            }
        }
        let recordedIds = Set(try await personalRecordRepository.fetchAll().filter { $0.setId != nil }.map(\.exerciseId))
        _ = try await recalculatePRs(for: exerciseIds.union(recordedIds))
    }

    // MARK: - Election helpers

    /// The four record candidates a single set can produce, using effective loads
    /// from the set's own exercise snapshot.
    static func candidateRecords(exerciseId: UUID, exercise: Exercise, set: ExerciseSet, bodyWeightKg: Double) -> [PersonalRecord] {
        let base = exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
        let loadParts = set.effectiveLoadParts(baseLoadPerRep: base)
        let parts = set.effectiveParts
        let achievedAt = set.completedAt ?? Date()
        var records: [PersonalRecord] = []

        if let weight = loadParts.map(\.load).max(), weight > 0 {
            records.append(PersonalRecord(id: UUID(), exerciseId: exerciseId, recordType: .maxWeight, value: weight, setId: set.id, achievedAt: achievedAt))
        }
        if let reps = parts.compactMap(\.reps).filter({ $0 > 0 }).max() {
            records.append(PersonalRecord(id: UUID(), exerciseId: exerciseId, recordType: .maxReps, value: Double(reps), setId: set.id, achievedAt: achievedAt))
        }
        // Shared hybrid Epley/Brzycki — must match analytics e1RM (reps capped at 15).
        if let e1rm = loadParts.map({ AnalyticsCalculations.calculateOneRM(weight: $0.load, reps: min($0.reps, 15)) }).max(), e1rm > 0 {
            records.append(PersonalRecord(id: UUID(), exerciseId: exerciseId, recordType: .estimatedOneRepMax, value: e1rm, setId: set.id, achievedAt: achievedAt))
        }
        let volume = set.setVolume(baseLoadPerRep: base)
        if volume > 0 {
            records.append(PersonalRecord(id: UUID(), exerciseId: exerciseId, recordType: .maxVolume, value: volume, setId: set.id, achievedAt: achievedAt))
        }
        return records
    }

    static func mostSignificant(_ records: [PersonalRecord]) -> PersonalRecord? {
        records.first { $0.recordType == .estimatedOneRepMax }
            ?? records.first { $0.recordType == .maxWeight }
            ?? records.first
    }
}
