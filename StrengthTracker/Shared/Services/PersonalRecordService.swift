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

        var newRecords: [PersonalRecord] = []

        // Check max weight PR
        if let weight = set.weight, weight > 0 {
            let maxWeightRecord = existingRecords.first { $0.recordType == .maxWeight }
            if maxWeightRecord == nil || weight > maxWeightRecord!.value {
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

        // Check max reps PR (at any weight)
        if let reps = set.reps, reps > 0 {
            let maxRepsRecord = existingRecords.first { $0.recordType == .maxReps }
            if maxRepsRecord == nil || Double(reps) > maxRepsRecord!.value {
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

        // Check estimated 1RM PR (Epley formula: weight * (1 + reps/30))
        if let weight = set.weight, let reps = set.reps, weight > 0, reps > 0 {
            let estimated1RM = weight * (1.0 + Double(reps) / 30.0)
            let e1RMRecord = existingRecords.first { $0.recordType == .estimatedOneRepMax }
            if e1RMRecord == nil || estimated1RM > e1RMRecord!.value {
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

        // Check max volume PR (weight * reps for this single set)
        if set.setVolume > 0 {
            let maxVolumeRecord = existingRecords.first { $0.recordType == .maxVolume }
            if maxVolumeRecord == nil || set.setVolume > maxVolumeRecord!.value {
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
            // Delete existing records
            try await personalRecordRepository.deleteForExercise(exerciseId)

            guard let firstSet = sets.first else { continue }
            _ = firstSet.exercise

            // Find max weight
            if let maxWeightSet = sets.max(by: { ($0.set.weight ?? 0) < ($1.set.weight ?? 0) }),
               let weight = maxWeightSet.set.weight, weight > 0 {
                let record = PersonalRecord(
                    id: UUID(),
                    exerciseId: exerciseId,
                    recordType: .maxWeight,
                    value: weight,
                    setId: maxWeightSet.set.id,
                    achievedAt: maxWeightSet.set.completedAt ?? Date()
                )
                _ = try await personalRecordRepository.save(record)
            }

            // Find max reps
            if let maxRepsSet = sets.max(by: { ($0.set.reps ?? 0) < ($1.set.reps ?? 0) }),
               let reps = maxRepsSet.set.reps, reps > 0 {
                let record = PersonalRecord(
                    id: UUID(),
                    exerciseId: exerciseId,
                    recordType: .maxReps,
                    value: Double(reps),
                    setId: maxRepsSet.set.id,
                    achievedAt: maxRepsSet.set.completedAt ?? Date()
                )
                _ = try await personalRecordRepository.save(record)
            }

            // Find max estimated 1RM
            let setsWithE1RM = sets.compactMap { item -> (set: ExerciseSet, e1RM: Double)? in
                guard let weight = item.set.weight, let reps = item.set.reps,
                      weight > 0, reps > 0 else { return nil }
                let e1RM = weight * (1.0 + Double(reps) / 30.0)
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
