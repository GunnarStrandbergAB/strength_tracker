import Foundation

@MainActor
public final class PersonalRecordService {
    private let personalRecordRepository: any PersonalRecordRepository
    private let workoutRepository: any WorkoutRepository

    public init(
        personalRecordRepository: any PersonalRecordRepository,
        workoutRepository: any WorkoutRepository
    ) {
        self.personalRecordRepository = personalRecordRepository
        self.workoutRepository = workoutRepository
    }

    /// Check if a completed set is a new personal record
    /// - Parameters:
    ///   - exercise: The exercise being performed
    ///   - set: The completed set to check
    /// - Returns: A new PersonalRecord if this set represents a PR, nil otherwise
    public func checkForPR(exercise: Exercise, set: ExerciseSet) async throws -> PersonalRecord? {
        guard set.isCompleted, set.setType != .warmup else { return nil }

        let existingRecords = try await personalRecordRepository.fetchForExercise(exercise.id)

        // Every performed segment is a candidate — for a grouped drop set that means
        // each drop entry; a plain set contributes its single mirrored part.
        let parts = set.effectiveParts

        var newRecords: [PersonalRecord] = []

        // Check max weight PR
        if let weight = parts.compactMap(\.weight).filter({ $0 > 0 }).max() {
            // Compare against the best existing record — multiple records of the same
            // type can accumulate, and `.first` would pick an arbitrary (possibly
            // stale, lower) one, flagging false PRs.
            let bestWeight = existingRecords.filter { $0.recordType == .maxWeight }.map(\.value).max() ?? 0
            if weight > bestWeight {
                newRecords.append(PersonalRecord(
                    id: UUID(),
                    exerciseId: exercise.id,
                    recordType: .maxWeight,
                    value: weight,
                    setId: set.id,
                    achievedAt: set.completedAt ?? Date()
                ))
            }
        }

        // Check max reps PR (at any weight) — best single segment, never the summed total
        if let reps = parts.compactMap(\.reps).filter({ $0 > 0 }).max() {
            let bestReps = existingRecords.filter { $0.recordType == .maxReps }.map(\.value).max() ?? 0
            if Double(reps) > bestReps {
                newRecords.append(PersonalRecord(
                    id: UUID(),
                    exerciseId: exercise.id,
                    recordType: .maxReps,
                    value: Double(reps),
                    setId: set.id,
                    achievedAt: set.completedAt ?? Date()
                ))
            }
        }

        // Check estimated 1RM PR (shared hybrid Epley/Brzycki — must match analytics e1RM)
        let partE1RMs = parts.compactMap { part -> Double? in
            guard let weight = part.weight, let reps = part.reps, weight > 0, reps > 0 else { return nil }
            return AnalyticsCalculations.calculateOneRM(weight: weight, reps: reps)
        }
        if let estimated1RM = partE1RMs.max() {
            let bestE1RM = existingRecords.filter { $0.recordType == .estimatedOneRepMax }.map(\.value).max() ?? 0
            if estimated1RM > bestE1RM {
                newRecords.append(PersonalRecord(
                    id: UUID(),
                    exerciseId: exercise.id,
                    recordType: .estimatedOneRepMax,
                    value: estimated1RM,
                    setId: set.id,
                    achievedAt: set.completedAt ?? Date()
                ))
            }
        }

        // Check max volume PR (whole-set total — includes all drop segments)
        if set.setVolume > 0 {
            let bestVolume = existingRecords.filter { $0.recordType == .maxVolume }.map(\.value).max() ?? 0
            if set.setVolume > bestVolume {
                newRecords.append(PersonalRecord(
                    id: UUID(),
                    exerciseId: exercise.id,
                    recordType: .maxVolume,
                    value: set.setVolume,
                    setId: set.id,
                    achievedAt: set.completedAt ?? Date()
                ))
            }
        }

        // Save all new records
        for record in newRecords {
            _ = try await personalRecordRepository.save(record)
        }

        // Return the most significant record (estimated 1RM if available, else max weight, else first)
        return newRecords.first { $0.recordType == .estimatedOneRepMax }
            ?? newRecords.first { $0.recordType == .maxWeight }
            ?? newRecords.first
    }

    /// Save a manually entered personal record
    public func saveManualRecord(_ record: PersonalRecord) async throws -> PersonalRecord {
        return try await personalRecordRepository.save(record)
    }

    /// Get all personal records for an exercise
    /// - Parameter exerciseId: The exercise ID
    /// - Returns: Array of personal records, sorted by achieved date descending
    public func getRecords(for exerciseId: UUID) async throws -> [PersonalRecord] {
        let records = try await personalRecordRepository.fetchForExercise(exerciseId)
        return records.sorted { $0.achievedAt > $1.achievedAt }
    }

    /// Recalculate all personal records from workout history
    /// This is useful for data correction or migrating legacy data
    public func recalculateAllPRs() async throws {
        let allWorkouts = try await workoutRepository.fetchAll()

        // Group all sets by exercise
        var setsByExercise: [UUID: [(exercise: Exercise, set: ExerciseSet)]] = [:]

        for workout in allWorkouts where workout.completedAt != nil {
            for workoutExercise in workout.exercises {
                for set in workoutExercise.sets where set.isCompleted && set.setType != .warmup {
                    let key = workoutExercise.exercise.id
                    if setsByExercise[key] == nil {
                        setsByExercise[key] = []
                    }
                    setsByExercise[key]?.append((workoutExercise.exercise, set))
                }
            }
        }

        // For each exercise, recalculate PRs
        for (exerciseId, sets) in setsByExercise {
            // Preserve manually entered records (setId == nil) — they have no backing
            // set to rebuild from and must survive the wipe.
            let manualRecords = try await personalRecordRepository.fetchForExercise(exerciseId)
                .filter { $0.setId == nil }

            // Delete existing records
            try await personalRecordRepository.deleteForExercise(exerciseId)

            for manual in manualRecords {
                _ = try await personalRecordRepository.save(manual)
            }

            guard let firstSet = sets.first else { continue }
            _ = firstSet.exercise

            // Every performed segment (drop-set parts included) is a PR candidate;
            // records keep pointing at the owning set (segments aren't fetchable rows).
            let parts: [(set: ExerciseSet, part: DropSetEntry)] = sets.flatMap { item in
                item.set.effectiveParts.map { (item.set, $0) }
            }

            // Find max weight
            if let best = parts.filter({ ($0.part.weight ?? 0) > 0 })
                .max(by: { ($0.part.weight ?? 0) < ($1.part.weight ?? 0) }),
               let weight = best.part.weight {
                let record = PersonalRecord(
                    id: UUID(),
                    exerciseId: exerciseId,
                    recordType: .maxWeight,
                    value: weight,
                    setId: best.set.id,
                    achievedAt: best.set.completedAt ?? Date()
                )
                _ = try await personalRecordRepository.save(record)
            }

            // Find max reps (best single segment)
            if let best = parts.filter({ ($0.part.reps ?? 0) > 0 })
                .max(by: { ($0.part.reps ?? 0) < ($1.part.reps ?? 0) }),
               let reps = best.part.reps {
                let record = PersonalRecord(
                    id: UUID(),
                    exerciseId: exerciseId,
                    recordType: .maxReps,
                    value: Double(reps),
                    setId: best.set.id,
                    achievedAt: best.set.completedAt ?? Date()
                )
                _ = try await personalRecordRepository.save(record)
            }

            // Find max estimated 1RM
            let setsWithE1RM = parts.compactMap { item -> (set: ExerciseSet, e1RM: Double)? in
                guard let weight = item.part.weight, let reps = item.part.reps,
                      weight > 0, reps > 0 else { return nil }
                let e1RM = AnalyticsCalculations.calculateOneRM(weight: weight, reps: reps)
                return (item.set, e1RM)
            }

            if let maxE1RM = setsWithE1RM.max(by: { $0.e1RM < $1.e1RM }) {
                let record = PersonalRecord(
                    id: UUID(),
                    exerciseId: exerciseId,
                    recordType: .estimatedOneRepMax,
                    value: maxE1RM.e1RM,
                    setId: maxE1RM.set.id,
                    achievedAt: maxE1RM.set.completedAt ?? Date()
                )
                _ = try await personalRecordRepository.save(record)
            }

            // Find max volume (single set)
            if let maxVolumeSet = sets.max(by: { $0.set.setVolume < $1.set.setVolume }),
               maxVolumeSet.set.setVolume > 0 {
                let record = PersonalRecord(
                    id: UUID(),
                    exerciseId: exerciseId,
                    recordType: .maxVolume,
                    value: maxVolumeSet.set.setVolume,
                    setId: maxVolumeSet.set.id,
                    achievedAt: maxVolumeSet.set.completedAt ?? Date()
                )
                _ = try await personalRecordRepository.save(record)
            }
        }
    }
}
