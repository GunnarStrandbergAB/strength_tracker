import Foundation

/// Controls which analytics features are available based on workout history.
/// Features unlock progressively as the user accumulates data, ensuring
/// meaningful insights and avoiding empty-state confusion.
///
/// Aligned with UX progressive disclosure phases:
/// - Phase 1 (1-5 workouts): Basic stats, PR tracking only
/// - Phase 2 (5-20 workouts): Quality score, basic trends, recommendations
/// - Phase 3 (20-50 workouts): Plateau detection, muscle balance, recovery
/// - Phase 4 (50+ workouts): Volume optimization, cycle comparisons, predictions
@MainActor
public final class AnalyticsFeatureGate: Sendable {

    public enum Feature: String, CaseIterable, Sendable {
        case similarWorkouts        // Phase 2: 5 workouts
        case qualityScore           // Phase 2: 5 workouts
        case strengthTrends         // Phase 2: 5 workouts
        case exerciseRecommendations // Phase 2: 5 workouts
        case plateauDetection       // Phase 3: 10 workouts
        case muscleBalance          // Phase 3: 20 workouts
        case recoveryTimeline       // Phase 3: 20 workouts
        case advancedInsights       // Phase 4: 50 workouts
    }

    private static let thresholds: [Feature: Int] = [
        .similarWorkouts: 5,
        .qualityScore: 5,
        .strengthTrends: 5,
        .exerciseRecommendations: 5,
        .plateauDetection: 10,
        .muscleBalance: 20,
        .recoveryTimeline: 20,
        .advancedInsights: 50,
    ]

    private let workoutRepository: any WorkoutRepository

    public init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    /// Check if a feature is unlocked for the current user
    public func isUnlocked(_ feature: Feature) async throws -> Bool {
        let count = try await completedWorkoutCount()
        let threshold = Self.thresholds[feature] ?? 0
        return count >= threshold
    }

    /// Get all currently unlocked features
    public func unlockedFeatures() async throws -> Set<Feature> {
        let count = try await completedWorkoutCount()
        return Set(Feature.allCases.filter { feature in
            let threshold = Self.thresholds[feature] ?? 0
            return count >= threshold
        })
    }

    /// Workouts needed to unlock the next feature
    public func nextUnlock() async throws -> (feature: Feature, workoutsNeeded: Int)? {
        let count = try await completedWorkoutCount()
        let locked = Feature.allCases
            .filter { (Self.thresholds[$0] ?? 0) > count }
            .sorted { (Self.thresholds[$0] ?? 0) < (Self.thresholds[$1] ?? 0) }

        guard let next = locked.first,
              let threshold = Self.thresholds[next] else { return nil }

        return (next, threshold - count)
    }

    // MARK: - Private

    private func completedWorkoutCount() async throws -> Int {
        let all = try await workoutRepository.fetchAll()
        return all.filter { $0.completedAt != nil }.count
    }
}
