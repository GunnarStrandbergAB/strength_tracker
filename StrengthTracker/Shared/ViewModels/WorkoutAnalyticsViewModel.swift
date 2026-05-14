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
    public var aggregateQuality: AggregateQualityScore?
    public var isQualityScoreLoading = false

    /// Feature gating
    public var unlockedFeatures: Set<AnalyticsFeatureGate.Feature> = []
    public var nextFeatureUnlock: (feature: AnalyticsFeatureGate.Feature, workoutsNeeded: Int)?

    /// Batch migration
    public var isMigrating = false

    /// Pre-workout context (M4)
    public var adherenceAnalysis: AdherenceAnalysis?
    public var weeklyDigest: WeeklyDigest?

    /// Per-muscle volume-response analyses. Observation-only; landmarks are derived
    /// from the user's logged history with explicit data-shape gating per muscle.
    public var volumeResponseAnalyses: [VolumeResponseAnalysis] = []

    /// Error handling
    public var errorMessage: String?

    // MARK: - Dependencies

    private let analyticsService: WorkoutAnalyticsService
    private let qualityScoreService: WorkoutQualityScoreService
    private let featureGate: AnalyticsFeatureGate
    private let workoutRepository: (any WorkoutRepository)?
    private let proFeatureGate: ProFeatureGate?
    private let adherenceService: AdherenceAnalysisService?
    private let coachingInsightService: CoachingInsightService?

    private var lastInsightsLoadTime: Date?

    private static let migrationKey = "analytics_migration_complete"

    // MARK: - Init

    public init(
        analyticsService: WorkoutAnalyticsService,
        qualityScoreService: WorkoutQualityScoreService,
        featureGate: AnalyticsFeatureGate,
        workoutRepository: (any WorkoutRepository)? = nil,
        proFeatureGate: ProFeatureGate? = nil,
        adherenceService: AdherenceAnalysisService? = nil,
        coachingInsightService: CoachingInsightService? = nil
    ) {
        self.analyticsService = analyticsService
        self.qualityScoreService = qualityScoreService
        self.featureGate = featureGate
        self.workoutRepository = workoutRepository
        self.proFeatureGate = proFeatureGate
        self.adherenceService = adherenceService
        self.coachingInsightService = coachingInsightService
    }

    // MARK: - Dashboard (loads WorkoutInsights aggregate)

    /// Load all analytics for dashboard as a consistent snapshot
    public func loadDashboardInsights(force: Bool = false) async {
        // Skip reload if fresh (within 60s) unless forced
        if !force,
           let lastLoad = lastInsightsLoadTime,
           Date().timeIntervalSince(lastLoad) < 60,
           insights.workoutCount > 0 {
            return
        }

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
            lastInsightsLoadTime = Date()

            // Auto-load quality score and aggregate using the same workouts
            if unlockedFeatures.contains(.qualityScore),
               let repo = workoutRepository {
                let allCompleted = try await repo.fetchAll()
                let completedWorkouts = allCompleted.filter { $0.completedAt != nil }

                // Per-workout score for the latest workout (used in detail views)
                if qualityScore == nil,
                   let latest = completedWorkouts
                    .sorted(by: { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })
                    .first {
                    qualityScore = qualityScoreService.computeScore(for: latest, history: allCompleted)
                }

                // Aggregate EWMA quality across all workouts
                aggregateQuality = qualityScoreService.computeAggregateScore(workouts: allCompleted)

                // Per-muscle volume-response analyses (data-shape gated per muscle).
                volumeResponseAnalyses = VolumeResponseService.computeAnalyses(
                    workouts: allCompleted,
                    overloadTrends: rawInsights.overloadTrends
                )
            } else {
                volumeResponseAnalyses = []
            }

            // Adherence analysis (M3)
            if let adherenceSvc = adherenceService, let repo = workoutRepository {
                let allWorkouts = try await repo.fetchAll()
                adherenceAnalysis = adherenceSvc.analyze(workouts: allWorkouts)

                // Weekly digest (M5)
                if unlockedFeatures.contains(.weeklyDigest),
                   let coaching = coachingInsightService {
                    let bw = 80.0 // Default; actual body weight resolved in view layer
                    weeklyDigest = coaching.generateWeeklyDigest(
                        workouts: allWorkouts,
                        overloadTrends: rawInsights.overloadTrends,
                        bodyWeightKg: bw
                    )
                }
            }
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

    // MARK: - Advanced Insights Accessors

    public var advancedInsightsLoaded: Bool {
        isFeatureUnlocked(.advancedInsights) && insights.workoutCount >= 19
    }

    public var loadZoneColor: String {
        switch insights.trainingLoad?.loadZone {
        case .underTraining: return "blue"
        case .optimal: return "green"
        case .caution: return "orange"
        case .danger: return "red"
        case nil: return "gray"
        }
    }

    public var readyMuscleCount: Int {
        insights.recoveryPatterns.filter { $0.recoveryStatus == .ready }.count
    }

    public var recoveringMuscleCount: Int {
        insights.recoveryPatterns.filter { $0.recoveryStatus != .ready }.count
    }

    public var topHighlight: AnalyticsHighlight? {
        insights.highlights.first
    }

    public var currentPhaseDisplayName: String {
        guard let phase = insights.trainingPhase?.currentPhase else { return "—" }
        switch phase {
        case .accumulation: return "Accumulation"
        case .intensification: return "Intensification"
        case .peaking: return "Peaking"
        case .deload: return "Deload"
        case .mixed: return "General"
        }
    }

    public func formatACWR(_ acwr: Double) -> String {
        String(format: "%.2f", acwr)
    }

    public func formatSlope(_ slope: Double) -> String {
        String(format: "%+.1f kg/wk", slope)
    }

    // MARK: - Feature Gate Helpers

    public func isFeatureUnlocked(_ feature: AnalyticsFeatureGate.Feature) -> Bool {
        unlockedFeatures.contains(feature)
    }

    /// Whether Pro subscription is active (or beta bypass). Nil gate means no restriction.
    public var hasProAccess: Bool {
        proFeatureGate?.hasProAccess ?? true
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
        case .postWorkoutDebrief: return "Post-Workout Debrief"
        case .weightSuggestion: return "Weight Suggestions"
        case .weeklyDigest: return "Weekly Digest"
        case .effortCreepWarning: return "Effort Creep Warnings"
        case .exerciseHints: return "Exercise Hints"
        case .similarWorkouts: return "Similar Workouts"
        case .qualityScore: return "Quality Score"
        case .strengthTrends: return "Strength Trends"
        case .exerciseRecommendations: return "Recommendations"
        case .preWorkoutContext: return "Pre-Workout Context"
        case .plateauDetection: return "Plateau Detection"
        case .archetypeClustering: return "Workout Archetypes"
        case .achievements: return "Achievements"
        case .sequencePrediction: return "Sequence Prediction"
        case .workoutSuggestion: return "Workout Suggestions"
        case .muscleBalance: return "Muscle Balance"
        case .recoveryTimeline: return "Recovery Timeline"
        case .advancedInsights: return "Advanced Insights"
        case .trajectoryAnalysis: return "Training Trajectory"
        case .trainingFingerprint: return "Training Fingerprint"
        case .muscleNeglect: return "Muscle Neglect Detection"
        case .timeOfDayAnalysis: return "Time-of-Day Analysis"
        case .changePointDetection: return "Change Point Detection"
        }
    }

    public func featureDescription(_ feature: AnalyticsFeatureGate.Feature) -> String {
        switch feature {
        case .postWorkoutDebrief: return "Summary and coaching insights after each workout"
        case .weightSuggestion: return "Suggested weights based on recent performance"
        case .weeklyDigest: return "Weekly training summary with top insight"
        case .effortCreepWarning: return "Alert when RPE climbs without strength gains"
        case .exerciseHints: return "Inline hints per exercise during logging"
        case .similarWorkouts: return "Find past workouts that match your current session"
        case .qualityScore: return "Rate each workout on volume, intensity, and balance"
        case .strengthTrends: return "Track strength changes over time per exercise"
        case .exerciseRecommendations: return "Get exercise suggestions based on your training gaps"
        case .preWorkoutContext: return "Recovery and load status before training"
        case .plateauDetection: return "Spot exercises where progress has stalled"
        case .archetypeClustering: return "Identify your distinct workout types"
        case .achievements: return "Earn badges for training milestones"
        case .sequencePrediction: return "Predict your likely next workout type"
        case .workoutSuggestion: return "Recovery-aware next workout suggestion"
        case .muscleBalance: return "Check if opposing muscle groups are trained evenly"
        case .recoveryTimeline: return "Optimal rest days between sessions"
        case .advancedInsights: return "Deep analysis across your full training history"
        case .trajectoryAnalysis: return "Track how your training is changing over time"
        case .trainingFingerprint: return "Your training variety and consistency profile"
        case .muscleNeglect: return "Detect declining volume in muscle groups"
        case .timeOfDayAnalysis: return "Find your optimal training window"
        case .changePointDetection: return "Identify major shifts in your training"
        }
    }
}
