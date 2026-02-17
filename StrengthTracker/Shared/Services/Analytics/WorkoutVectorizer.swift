import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Extracts 18-dimensional feature vectors from workout data.
/// Stateless service (DDD: services should not hold mutable state).
/// Historical context is passed as a parameter, not stored.
@MainActor
public final class WorkoutVectorizer: Sendable {

    // MARK: - Normalization Constants (99th percentile)
    private let maxVolume: Double = 50000.0
    private let maxWeight: Double = 300.0
    private let maxReps: Int = 30
    private let maxSets: Int = 100
    private let maxExercises: Int = 15
    private let maxDuration: TimeInterval = 7200
    private let maxPRs: Int = 10

    public init() {}

    /// Extract feature vector from a workout
    /// - Parameters:
    ///   - workout: The workout to vectorize
    ///   - historicalWorkouts: Recent workouts for computing relative features (7d/30d averages)
    ///   - bodyWeightKg: User's body weight for pure bodyweight exercise volume (default 70kg)
    public func vectorize(_ workout: Workout, historicalWorkouts: [Workout] = [], bodyWeightKg: Double = 70.0) -> WorkoutVector {
        var features = [Double](repeating: 0.0, count: 18)

        // 0: Total volume (normalized) — use body-weight-aware calculation
        let totalVol = calculateTotalVolume(workout, bodyWeightKg: bodyWeightKg)
        features[0] = min(totalVol / maxVolume, 1.0)

        // 1: Average weight across all sets (bodyweight fallback for bodyweightReps)
        let allSets = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }
        let weights = zip(workout.exercises, workout.exercises.map { ex in
            ex.sets.filter(\.isCompleted).map { s in
                s.weight ?? (ex.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0.0)
            }
        }).flatMap(\.1)
        let avgWeight = weights.isEmpty ? 0.0 : weights.reduce(0, +) / Double(weights.count)
        features[1] = min(avgWeight / maxWeight, 1.0)

        // 2: Average reps
        let reps = allSets.compactMap(\.reps)
        let avgReps = reps.isEmpty ? 0 : reps.reduce(0, +) / reps.count
        features[2] = min(Double(avgReps) / Double(maxReps), 1.0)

        // 3: Set count (normalized)
        features[3] = min(Double(allSets.count) / Double(maxSets), 1.0)

        // 4: Exercise diversity
        let uniqueExercises = Set(workout.exercises.map { $0.exercise.id }).count
        features[4] = min(Double(uniqueExercises) / Double(maxExercises), 1.0)

        // 5: Duration (normalized)
        if let duration = workout.duration {
            features[5] = min(duration / maxDuration, 1.0)
        }

        // 6-11: Muscle group ratios (percentage of total volume)
        let muscleVolumes = calculateMuscleGroupVolumes(workout, bodyWeightKg: bodyWeightKg)
        let totalVolDenom = totalVol > 0 ? totalVol : 1.0

        features[6] = (muscleVolumes[.chest] ?? 0.0) / totalVolDenom
        features[7] = (muscleVolumes[.back] ?? 0.0) / totalVolDenom

        let legsVol = (muscleVolumes[.quadriceps] ?? 0.0) + (muscleVolumes[.hamstrings] ?? 0.0) +
                      (muscleVolumes[.glutes] ?? 0.0) + (muscleVolumes[.calves] ?? 0.0)
        features[8] = legsVol / totalVolDenom

        features[9] = (muscleVolumes[.shoulders] ?? 0.0) / totalVolDenom

        let armsVol = (muscleVolumes[.biceps] ?? 0.0) + (muscleVolumes[.triceps] ?? 0.0)
        features[10] = armsVol / totalVolDenom

        features[11] = (muscleVolumes[.core] ?? 0.0) / totalVolDenom

        // 12: Compound exercise ratio (barbell exercises)
        let compoundCount = workout.exercises.filter { $0.exercise.category == .barbell }.count
        features[12] = Double(compoundCount) / Double(max(workout.exercises.count, 1))

        // 13: Average RPE (0-10 scale, normalized to 0-1)
        let rpeValues = allSets.compactMap(\.rpe)
        let avgRPE = rpeValues.isEmpty ? 0.0 : rpeValues.reduce(0, +) / Double(rpeValues.count)
        features[13] = avgRPE / 10.0

        // 14-15: Volume vs historical moving averages
        let (vol7d, vol30d) = calculateHistoricalVolumes(workout, historicalWorkouts: historicalWorkouts, bodyWeightKg: bodyWeightKg)
        features[14] = vol7d
        features[15] = vol30d

        // 16: PR count (normalized)
        let prCount = allSets.filter(\.isPersonalRecord).count
        features[16] = min(Double(prCount) / Double(maxPRs), 1.0)

        // 17: Time of day (sin encoding for cyclical feature)
        let hour = Calendar.current.component(.hour, from: workout.startedAt)
        features[17] = sin(Double(hour) * 2.0 * .pi / 24.0) * 0.5 + 0.5

        // L2 normalization for cosine similarity
        let normalized = l2Normalize(features)

        return WorkoutVector(
            id: UUID(),
            workoutId: workout.id,
            dimensions: normalized,
            createdAt: Date()
        )
    }

    // MARK: - Helper Methods

    /// Compute total volume with body-weight fallback for pure bodyweight exercises.
    func calculateTotalVolume(_ workout: Workout, bodyWeightKg: Double) -> Double {
        workout.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).filter { $0.setType != .warmup }.reduce(0) { setTotal, set in
                let weight = set.weight ?? (exercise.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0.0)
                return setTotal + weight * Double(set.reps ?? 0)
            }
        }
    }

    private func calculateMuscleGroupVolumes(_ workout: Workout, bodyWeightKg: Double) -> [MuscleGroup: Double] {
        var volumes: [MuscleGroup: Double] = [:]

        for exercise in workout.exercises {
            let exerciseVolume = exercise.sets.filter(\.isCompleted).filter { $0.setType != .warmup }.reduce(0.0) { sum, set in
                let weight = set.weight ?? (exercise.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0.0)
                return sum + weight * Double(set.reps ?? 0)
            }

            // Primary muscle gets 70% of volume
            volumes[exercise.exercise.primaryMuscleGroup, default: 0] += exerciseVolume * 0.7

            // Secondary muscles split remaining 30%
            let secondaryCount = exercise.exercise.secondaryMuscleGroups.count
            let secondaryShare = exerciseVolume * 0.3 / Double(max(secondaryCount, 1))
            for secondary in exercise.exercise.secondaryMuscleGroups {
                volumes[secondary, default: 0] += secondaryShare
            }
        }

        return volumes
    }

    private func calculateHistoricalVolumes(
        _ workout: Workout,
        historicalWorkouts: [Workout],
        bodyWeightKg: Double
    ) -> (vol7d: Double, vol30d: Double) {
        let calendar = Calendar.current
        let workoutDate = workout.startedAt
        let currentVol = calculateTotalVolume(workout, bodyWeightKg: bodyWeightKg)

        // 7-day moving average (excluding current workout)
        let last7Days = historicalWorkouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            let daysDiff = calendar.dateComponents([.day], from: completedAt, to: workoutDate).day ?? 0
            return daysDiff >= 0 && daysDiff <= 7 && $0.id != workout.id
        }
        let avg7d = last7Days.isEmpty ? 0.0 : last7Days.map { calculateTotalVolume($0, bodyWeightKg: bodyWeightKg) }.reduce(0, +) / Double(last7Days.count)
        let change7d = avg7d > 0 ? (currentVol - avg7d) / avg7d : 0.0

        // 30-day moving average
        let last30Days = historicalWorkouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            let daysDiff = calendar.dateComponents([.day], from: completedAt, to: workoutDate).day ?? 0
            return daysDiff >= 0 && daysDiff <= 30 && $0.id != workout.id
        }
        let avg30d = last30Days.isEmpty ? 0.0 : last30Days.map { calculateTotalVolume($0, bodyWeightKg: bodyWeightKg) }.reduce(0, +) / Double(last30Days.count)
        let change30d = avg30d > 0 ? (currentVol - avg30d) / avg30d : 0.0

        return (
            vol7d: max(-1.0, min(1.0, change7d)),
            vol30d: max(-1.0, min(1.0, change30d))
        )
    }

    func l2Normalize(_ vector: [Double]) -> [Double] {
        #if canImport(Accelerate)
        var result = vector
        var magnitude: Double = 0.0
        vDSP_dotprD(vector, 1, vector, 1, &magnitude, vDSP_Length(vector.count))
        magnitude = sqrt(magnitude)

        if magnitude > 0 {
            var divisor = magnitude
            vDSP_vsdivD(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        }
        return result
        #else
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return magnitude > 0 ? vector.map { $0 / magnitude } : vector
        #endif
    }
}
