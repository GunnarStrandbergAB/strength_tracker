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
        case postWorkoutDebrief     // Phase 1: 1 workout (progressive content)
        case weightSuggestion       // Phase 2: 5 workouts
        case weeklyDigest           // Phase 2: 5 workouts
        case similarWorkouts        // Phase 2: 5 workouts
        case qualityScore           // Phase 2: 5 workouts
        case strengthTrends         // Phase 2: 5 workouts
        case exerciseRecommendations // Phase 2: 5 workouts
        case preWorkoutContext      // Phase 2: 5 workouts
        case effortCreepWarning     // Phase 3: 10 workouts
        case exerciseHints          // Phase 3: 10 workouts
        case plateauDetection       // Phase 3: 10 workouts
        case archetypeClustering    // Phase 3: 10 workouts
        case sequencePrediction     // Phase 3: 15 workouts
        case workoutSuggestion      // Phase 3: 15 workouts
        case muscleBalance          // Phase 3: 19 workouts
        case advancedInsights       // Phase 3: 19 workouts
        case trainingFingerprint    // Phase 3: 19 workouts
        case muscleNeglect          // Phase 3: 19 workouts
        case recoveryTimeline       // Phase 3: 20 workouts
        case timeOfDayAnalysis      // Phase 3: 20 workouts
    }

    private static let thresholds: [Feature: Int] = [
        .postWorkoutDebrief: 1,
        .weightSuggestion: 5,
        .weeklyDigest: 5,
        .similarWorkouts: 5,
        .qualityScore: 5,
        .strengthTrends: 5,
        .exerciseRecommendations: 5,
        .preWorkoutContext: 5,
        .effortCreepWarning: 10,
        .exerciseHints: 10,
        .plateauDetection: 10,
        .archetypeClustering: 10,
        .sequencePrediction: 15,
        .workoutSuggestion: 15,
        .muscleBalance: 19,
        .advancedInsights: 19,
        .trainingFingerprint: 19,
        .muscleNeglect: 19,
        .recoveryTimeline: 20,
        .timeOfDayAnalysis: 20,
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
