import Foundation

/// Computes a post-workout quality score (0-100) shown on the completion sheet.
/// Score breakdown (25 points each): Volume, Intensity, Rest times, Balance.
@MainActor
public final class WorkoutQualityScoreService: Sendable {

    private let workoutRepository: any WorkoutRepository
    private let muscleBalanceService: MuscleBalanceService

    public init(
        workoutRepository: any WorkoutRepository,
        muscleBalanceService: MuscleBalanceService
    ) {
        self.workoutRepository = workoutRepository
        self.muscleBalanceService = muscleBalanceService
    }

    /// Compute quality score for a completed workout
    public func computeScore(for workout: Workout) async throws -> WorkoutQualityScore {
        let recentWorkouts = try await workoutRepository.fetchAll()

        let volumeScore = computeVolumeScore(workout, history: recentWorkouts)
        let intensityScore = computeIntensityScore(workout)
        let consistencyScore = computeConsistencyScore(workout)
        let balanceScore = computeBalanceScore(workout)

        let overall = (volumeScore + intensityScore + consistencyScore + balanceScore) / 4.0

        return WorkoutQualityScore(
            id: UUID(),
            workoutId: workout.id,
            overallScore: overall,
            volumeScore: volumeScore,
            intensityScore: intensityScore,
            balanceScore: balanceScore,
            consistencyScore: consistencyScore
        )
    }

    /// Alias matching architecture doc naming
    public func scoreWorkout(_ workout: Workout) async throws -> WorkoutQualityScore {
        try await computeScore(for: workout)
    }

    // MARK: - Scoring Components (0-100 scale each)

    private func computeVolumeScore(_ workout: Workout, history: [Workout]) -> Double {
        let recentCompleted = history.filter { $0.completedAt != nil }.suffix(12)
        let avgVolume = recentCompleted.isEmpty ? 0.0 :
            recentCompleted.map(\.totalVolume).reduce(0, +) / Double(recentCompleted.count)

        guard avgVolume > 0 else { return 80.0 }

        let ratio = workout.totalVolume / avgVolume
        switch ratio {
        case 0.8...1.2: return 100.0
        case 0.6...1.4: return 80.0
        case 0.4...1.6: return 50.0
        default:        return 20.0
        }
    }

    private func computeIntensityScore(_ workout: Workout) -> Double {
        let sets = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }
        let rpes = sets.compactMap(\.rpe)

        guard !rpes.isEmpty else { return 72.0 }

        let avgRPE = rpes.reduce(0, +) / Double(rpes.count)
        switch avgRPE {
        case 6.0...8.5: return 100.0
        case 5.0...9.0: return 80.0
        case 4.0...9.5: return 50.0
        default:        return 20.0
        }
    }

    private func computeConsistencyScore(_ workout: Workout) -> Double {
        let duration = workout.duration ?? 0
        let setCount = workout.exercises.flatMap { $0.sets.filter(\.isCompleted) }.count

        guard setCount > 0, duration > 0 else { return 72.0 }

        let avgTimePerSet = duration / Double(setCount)
        switch avgTimePerSet {
        case 60...180: return 100.0
        case 45...240: return 80.0
        case 30...300: return 50.0
        default:       return 20.0
        }
    }

    private func computeBalanceScore(_ workout: Workout) -> Double {
        let balance = muscleBalanceService.analyze(workouts: [workout], timeWindow: 0)

        switch balance.overallBalanceScore {
        case 0.8...1.0: return 100.0
        case 0.6...0.8: return 80.0
        case 0.4...0.6: return 50.0
        default:        return 20.0
        }
    }
}
