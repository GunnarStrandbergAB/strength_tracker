import Foundation

/// Recommends exercises based on training history, plateaus, and muscle balance.
/// Stateless service -- all data passed as parameters.
@MainActor
public final class ExerciseRecommendationService: Sendable {

    public init() {}

    /// Generate exercise recommendations
    /// - Parameters:
    ///   - workouts: Historical workouts for context
    ///   - availableExercises: All exercises the user can choose from
    ///   - muscleBalance: Current muscle balance analysis (nil if insufficient data)
    ///   - plateaus: Current plateau analyses
    ///   - limit: Maximum recommendations to return
    /// - Returns: Prioritized exercise recommendations
    public func generateRecommendations(
        workouts: [Workout],
        availableExercises: [Exercise],
        muscleBalance: MuscleBalance?,
        plateaus: [PlateauAnalysis],
        limit: Int = 5
    ) -> [ExerciseRecommendation] {
        var recommendations: [ExerciseRecommendation] = []

        // Current workout exercise IDs (from most recent workout)
        let currentExerciseIds = Set(workouts.first?.exercises.map { $0.exercise.id } ?? [])

        // 1. Muscle imbalance recommendations
        if let balance = muscleBalance {
            for imbalance in balance.imbalances.prefix(2) {
                let candidates = availableExercises.filter { exercise in
                    exercise.primaryMuscleGroup.rawValue == imbalance.comparisonGroup &&
                    !currentExerciseIds.contains(exercise.id)
                }

                if let exercise = candidates.first {
                    recommendations.append(ExerciseRecommendation(
                        id: UUID(),
                        exerciseId: exercise.id,
                        exerciseName: exercise.name,
                        reason: .fillsMuscleGap,
                        confidence: 0.9,
                        basedOnWorkoutCount: workouts.count
                    ))
                }
            }
        }

        // 2. Plateau breaker recommendations
        for plateau in plateaus.filter({ $0.consecutiveWeeksStalled >= 2 }).prefix(2) {
            let exerciseId = plateau.exerciseId

            // Find the stalled exercise's muscle group
            let stalledExercise = availableExercises.first { $0.id == exerciseId }
            guard let muscleGroup = stalledExercise?.primaryMuscleGroup else { continue }

            // Recommend a variation targeting the same muscle group
            let candidates = availableExercises.filter { exercise in
                exercise.primaryMuscleGroup == muscleGroup &&
                exercise.id != exerciseId &&
                !currentExerciseIds.contains(exercise.id)
            }

            if let exercise = candidates.first {
                recommendations.append(ExerciseRecommendation(
                    id: UUID(),
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    reason: .plateauBreaker,
                    confidence: 0.85,
                    basedOnWorkoutCount: workouts.count
                ))
            }
        }

        // 3. Complementary exercises (fill gaps in recent training)
        let recentMuscles = Set(workouts.prefix(5).flatMap { $0.exercises.map { $0.exercise.primaryMuscleGroup } })
        let allMajorMuscles: Set<MuscleGroup> = [.chest, .back, .shoulders, .quadriceps, .hamstrings, .biceps, .triceps]
        let missingMuscles = allMajorMuscles.subtracting(recentMuscles)

        for muscle in missingMuscles.prefix(2) {
            let candidates = availableExercises.filter { exercise in
                exercise.primaryMuscleGroup == muscle &&
                !currentExerciseIds.contains(exercise.id)
            }

            if let exercise = candidates.first {
                recommendations.append(ExerciseRecommendation(
                    id: UUID(),
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    reason: .fillsMuscleGap,
                    confidence: 0.7,
                    basedOnWorkoutCount: workouts.count
                ))
            }
        }

        // Remove duplicates (same exercise recommended for different reasons)
        var seen = Set<UUID>()
        let unique = recommendations.filter { rec in
            if seen.contains(rec.exerciseId) { return false }
            seen.insert(rec.exerciseId)
            return true
        }

        return Array(unique.prefix(limit))
    }

    /// Overload matching architecture doc's `recommend(for:allWorkouts:availableExercises:muscleBalance:limit:)` signature
    public func recommend(
        for workout: Workout,
        allWorkouts: [Workout],
        availableExercises: [Exercise],
        muscleBalance: MuscleBalance,
        limit: Int
    ) async throws -> [ExerciseRecommendation] {
        generateRecommendations(
            workouts: allWorkouts,
            availableExercises: availableExercises,
            muscleBalance: muscleBalance,
            plateaus: [],
            limit: limit
        )
    }

    // MARK: - Private

    private func calculateEstimatedVolume(for exercise: Exercise, in workouts: [Workout]) -> Double {
        let historicalVolumes = workouts.flatMap { workout in
            workout.exercises.filter { $0.exercise.id == exercise.id }.map { $0.exerciseVolume }
        }

        guard !historicalVolumes.isEmpty else { return 0 }
        return historicalVolumes.reduce(0, +) / Double(historicalVolumes.count)
    }
}
