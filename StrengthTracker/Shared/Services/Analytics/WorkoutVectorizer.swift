import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Extracts 18-dimensional feature vectors from workout data.
/// Stateless service (DDD: services should not hold mutable state).
/// Historical context is passed as a parameter, not stored.
@MainActor
public final class WorkoutVectorizer: Sendable {

    // MARK: - Normalization Constants (90th-95th percentile of real training)
    private let maxVolume: Double = 20000.0
    private let maxWeight: Double = 150.0
    private let maxReps: Int = 30
    private let maxSets: Int = 100
    private let maxExercises: Int = 15
    private let maxDuration: TimeInterval = 5400
    private let maxPRs: Int = 10

    public init() {}

    /// Extract feature vector from a workout
    /// - Parameters:
    ///   - workout: The workout to vectorize
    ///   - historicalWorkouts: Recent workouts for computing relative features (7d/30d averages)
    ///   - bodyWeightKg: User's body weight for pure bodyweight exercise volume
    public func vectorize(_ workout: Workout, historicalWorkouts: [Workout] = [], bodyWeightKg: Double = UserPreferencesService.defaultBodyWeightKg) -> WorkoutVector {
        var features = [Double](repeating: 0.0, count: 18)

        // 0: Total volume (normalized) — use body-weight-aware calculation
        let totalVol = calculateTotalVolume(workout, bodyWeightKg: bodyWeightKg)
        features[0] = min(totalVol / maxVolume, 1.0)

        // 1: Average weight across all sets (bodyweight fallback for bodyweightReps)
        let allSets = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }
        let weights = zip(workout.exercises, workout.exercises.map { ex -> [Double] in
            let baseLoad = ex.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
            return ex.sets.filter(\.isCompleted).map { s in
                if s.sideSets != nil {
                    return s.strengthParts(baseLoadPerRep: baseLoad, recording: ex.exercise.strengthRecording).first?.load
                        ?? ((baseLoad ?? 0) + (s.weight ?? 0) / (ex.exercise.strengthRecording?.sideWeightScale ?? 1))
                }
                return s.effectiveParts.first?.effectiveLoad(baseLoadPerRep: baseLoad) ?? 0.0
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

        // 6: Chest (no sub-groups)
        features[6] = (muscleVolumes[.chest] ?? 0.0) / totalVolDenom

        // 7: Back = .back + .lats + .traps (not .lowerBack — that's core antagonist)
        let backVol = (muscleVolumes[.back] ?? 0.0) +
                      (muscleVolumes[.lats] ?? 0.0) +
                      (muscleVolumes[.traps] ?? 0.0)
        features[7] = backVol / totalVolDenom

        // 8: Legs = quad + ham + glute + calf + adductors + abductors + hipFlexors
        let legsMain = (muscleVolumes[.quadriceps] ?? 0.0) + (muscleVolumes[.hamstrings] ?? 0.0) +
                       (muscleVolumes[.glutes] ?? 0.0) + (muscleVolumes[.calves] ?? 0.0)
        let legsSub = (muscleVolumes[.adductors] ?? 0.0) + (muscleVolumes[.abductors] ?? 0.0) +
                      (muscleVolumes[.hipFlexors] ?? 0.0)
        let legsVol = legsMain + legsSub
        features[8] = legsVol / totalVolDenom

        // 9: Shoulders (no sub-groups)
        features[9] = (muscleVolumes[.shoulders] ?? 0.0) / totalVolDenom

        // 10: Arms = biceps + triceps + forearms
        let armsVol = (muscleVolumes[.biceps] ?? 0.0) + (muscleVolumes[.triceps] ?? 0.0) +
                      (muscleVolumes[.forearms] ?? 0.0)
        features[10] = armsVol / totalVolDenom

        // 11: Core = core + obliques + lowerBack
        let coreVol = (muscleVolumes[.core] ?? 0.0) +
                      (muscleVolumes[.obliques] ?? 0.0) +
                      (muscleVolumes[.lowerBack] ?? 0.0)
        features[11] = coreVol / totalVolDenom

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
        features[16] = recordFeature(for: workout)

        // 17: Time of day (linear mapping — monotonic, no midnight/noon collision)
        let hour = Calendar.current.component(.hour, from: workout.startedAt)
        let minuteOfDay = hour * 60 + Calendar.current.component(.minute, from: workout.startedAt)
        features[17] = min(Double(minuteOfDay) / 1440.0, 1.0)

        // Capture L2 magnitude before normalization (enables future raw reconstruction)
        let magnitude = sqrt(features.reduce(0) { $0 + $1 * $1 })

        // L2 normalization for cosine similarity
        let normalized = AnalyticsCalculations.l2Normalize(features)

        return WorkoutVector(
            id: UUID(),
            workoutId: workout.id,
            dimensions: normalized,
            magnitude: magnitude,
            // The vector's date IS the training date — drift/block/archetype/phase/
            // anomaly services window on it. Wall-clock vectorization time would
            // misplace retro-logged workouts and collapse after migrations.
            createdAt: workout.startedAt
        )
    }

    // MARK: - Helper Methods

    /// Compute total volume with body-weight fallback for pure bodyweight exercises.
    func calculateTotalVolume(_ workout: Workout, bodyWeightKg: Double) -> Double {
        workout.totalVolume(bodyWeightKg: bodyWeightKg)
    }

    private func calculateMuscleGroupVolumes(_ workout: Workout, bodyWeightKg: Double) -> [MuscleGroup: Double] {
        var volumes: [MuscleGroup: Double] = [:]

        for exercise in workout.exercises {
            let exerciseVolume = exercise.exerciseVolume(bodyWeightKg: bodyWeightKg)

            let attributed = AnalyticsCalculations.attributeVolume(
                volume: exerciseVolume,
                primaryMuscle: exercise.exercise.primaryMuscleGroup,
                secondaryMuscles: exercise.exercise.secondaryMuscleGroups
            )
            for (muscle, vol) in attributed {
                volumes[muscle, default: 0] += vol
            }
        }

        return volumes
    }

    private func calculateHistoricalVolumes(
        _ workout: Workout,
        historicalWorkouts: [Workout],
        bodyWeightKg: Double
    ) -> (vol7d: Double, vol30d: Double) {
        let currentVol = calculateTotalVolume(workout, bodyWeightKg: bodyWeightKg)
        let prior = historicalWorkouts.filter { $0.id != workout.id && Self.usesVolume(completedAt: $0.completedAt, in: workout) }
        func change(relativeTo baseline: [Workout]) -> Double {
            guard !baseline.isEmpty else { return 0 }
            let average = baseline.reduce(0) { $0 + calculateTotalVolume($1, bodyWeightKg: bodyWeightKg) } / Double(baseline.count)
            return average > 0 ? (currentVol - average) / average : 0
        }
        let change7d = change(relativeTo: prior.filter { Self.usesVolume(completedAt: $0.completedAt, in: workout, days: 7) })
        let change30d = change(relativeTo: prior)

        return (
            vol7d: max(-1.0, min(1.0, change7d)),
            vol30d: max(-1.0, min(1.0, change30d))
        )
    }

    private func recordFeature(for workout: Workout) -> Double {
        let count = workout.exercises.reduce(0) { sum, exercise in
            sum + exercise.sets.filter { $0.isCompleted && $0.isPersonalRecord }.count
        }
        return min(Double(count) / Double(maxPRs), 1)
    }

    func matchesRecordCount(_ vector: WorkoutVector?, workout: Workout) -> Bool {
        guard let vector, let magnitude = vector.magnitude else { return false }
        // SwiftData stores normalized dimensions as Float32.
        return abs(vector.dimensions[16] * magnitude - recordFeature(for: workout)) < 1e-5
    }

    /// Shared by vector construction and dependency invalidation. An overlapping
    /// or later session cannot contribute to a workout's prior volume.
    static func usesVolume(completedAt end: Date?, in workout: Workout, days: Int = 30) -> Bool {
        guard let end, end <= workout.startedAt else { return false }
        let age = Calendar.current.dateComponents([.day], from: end, to: workout.startedAt).day
        return age.map { $0 <= days } ?? false
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
