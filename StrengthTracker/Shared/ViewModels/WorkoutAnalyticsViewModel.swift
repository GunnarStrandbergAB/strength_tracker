import Foundation
import Observation

@MainActor
@Observable
public final class WorkoutAnalyticsViewModel {

    // MARK: - Published State

    /// Dashboard aggregate -- loaded as a consistent snapshot
    public var insights: WorkoutInsights = .empty
    public var isInsightsLoading = false

    /// Per-workout results (loaded on demand, outside the aggregate)
    public var similarWorkouts: [SimilarWorkout] = []
    public var isSimilarWorkoutsLoading = false

    public var qualityScore: WorkoutQualityScore?
    public var isQualityScoreLoading = false

    /// Feature gating
    public var unlockedFeatures: Set<AnalyticsFeatureGate.Feature> = []
    public var nextFeatureUnlock: (feature: AnalyticsFeatureGate.Feature, workoutsNeeded: Int)?

    /// Batch migration
    public var isMigrating = false

    /// Error handling
    public var errorMessage: String?

    // MARK: - Dependencies

    private let analyticsService: WorkoutAnalyticsService
    private let qualityScoreService: WorkoutQualityScoreService
    private let featureGate: AnalyticsFeatureGate

    private static let migrationKey = "analytics_migration_complete"

    // MARK: - Init

    public init(
        analyticsService: WorkoutAnalyticsService,
        qualityScoreService: WorkoutQualityScoreService,
        featureGate: AnalyticsFeatureGate
    ) {
        self.analyticsService = analyticsService
        self.qualityScoreService = qualityScoreService
        self.featureGate = featureGate
    }

    // MARK: - Dashboard (loads WorkoutInsights aggregate)

    /// Load all analytics for dashboard as a consistent snapshot
    public func loadDashboardInsights() async {
        isInsightsLoading = true
        defer { isInsightsLoading = false }

        do {
            // Batch migration: vectorize all existing workouts on first analytics access
            if !UserDefaults.standard.bool(forKey: Self.migrationKey) {
                isMigrating = true
                try await analyticsService.vectorizeAllWorkouts()
                UserDefaults.standard.set(true, forKey: Self.migrationKey)
                isMigrating = false
            }

            // Load feature gate state
            unlockedFeatures = try await featureGate.unlockedFeatures()
            nextFeatureUnlock = try? await featureGate.nextUnlock()

            // Always generate insights (workoutCount is always useful)
            var rawInsights = try await analyticsService.generateInsights()

            // Gate quality score data
            if !unlockedFeatures.contains(.qualityScore) {
                rawInsights = WorkoutInsights(
                    generatedAt: rawInsights.generatedAt,
                    workoutCount: rawInsights.workoutCount,
                    plateaus: [],
                    muscleBalance: nil,
                    recommendations: [],
                    recoveryPatterns: rawInsights.recoveryPatterns,
                    optimalVolumes: rawInsights.optimalVolumes
                )
            }

            // Enforce feature gate: only include data for unlocked features
            if !unlockedFeatures.contains(.plateauDetection) {
                rawInsights = WorkoutInsights(
                    generatedAt: rawInsights.generatedAt,
                    workoutCount: rawInsights.workoutCount,
                    plateaus: [],
                    muscleBalance: rawInsights.muscleBalance,
                    recommendations: rawInsights.recommendations,
                    recoveryPatterns: rawInsights.recoveryPatterns,
                    optimalVolumes: rawInsights.optimalVolumes
                )
            }
            if !unlockedFeatures.contains(.muscleBalance) {
                rawInsights = WorkoutInsights(
                    generatedAt: rawInsights.generatedAt,
                    workoutCount: rawInsights.workoutCount,
                    plateaus: rawInsights.plateaus,
                    muscleBalance: nil,
                    recommendations: rawInsights.recommendations,
                    recoveryPatterns: rawInsights.recoveryPatterns,
                    optimalVolumes: rawInsights.optimalVolumes
                )
            }

            insights = rawInsights
            errorMessage = nil
        } catch {
            isMigrating = false
            errorMessage = "Failed to load insights: \(error.localizedDescription)"
            insights = .empty
        }
    }

    // MARK: - Per-Workout (outside aggregate)

    public func loadSimilarWorkouts(to workout: Workout, limit: Int = 5) async {
        isSimilarWorkoutsLoading = true
        defer { isSimilarWorkoutsLoading = false }

        do {
            similarWorkouts = try await analyticsService.findSimilarWorkouts(
                to: workout, limit: limit, minSimilarity: 0.7
            )
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load similar workouts: \(error.localizedDescription)"
            similarWorkouts = []
        }
    }

    public func loadQualityScore(for workout: Workout) async {
        isQualityScoreLoading = true
        defer { isQualityScoreLoading = false }

        do {
            qualityScore = try await qualityScoreService.computeScore(for: workout)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to compute quality score: \(error.localizedDescription)"
            qualityScore = nil
        }
    }

    // MARK: - Feature Gate Helpers

    public func isFeatureUnlocked(_ feature: AnalyticsFeatureGate.Feature) -> Bool {
        unlockedFeatures.contains(feature)
    }

    // MARK: - Formatting Helpers

    public func formatSimilarity(_ score: Double) -> String {
        String(format: "%.0f%%", score * 100)
    }

    public func formatVolume(_ volume: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: volume)) ?? "0"
    }

    public func formatRatio(_ ratio: Double) -> String {
        String(format: "%.1f:1", ratio)
    }

    public func severityColor(_ severity: ImbalanceSeverity) -> String {
        switch severity {
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        }
    }

    public func featureDisplayName(_ feature: AnalyticsFeatureGate.Feature) -> String {
        switch feature {
        case .similarWorkouts: return "Similar Workouts"
        case .qualityScore: return "Quality Score"
        case .strengthTrends: return "Strength Trends"
        case .exerciseRecommendations: return "Recommendations"
        case .plateauDetection: return "Plateau Detection"
        case .muscleBalance: return "Muscle Balance"
        case .recoveryTimeline: return "Recovery Timeline"
        case .advancedInsights: return "Advanced Insights"
        }
    }

    public func featureDescription(_ feature: AnalyticsFeatureGate.Feature) -> String {
        switch feature {
        case .similarWorkouts: return "Find past workouts that match your current session"
        case .qualityScore: return "Rate each workout on volume, intensity, and balance"
        case .strengthTrends: return "Track strength changes over time per exercise"
        case .exerciseRecommendations: return "Get exercise suggestions based on your training gaps"
        case .plateauDetection: return "Spot exercises where progress has stalled"
        case .muscleBalance: return "Check if opposing muscle groups are trained evenly"
        case .recoveryTimeline: return "Optimal rest days between sessions"
        case .advancedInsights: return "Deep analysis across your full training history"
        }
    }
}
