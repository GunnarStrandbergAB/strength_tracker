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

    public private(set) var latestSessionScore: WorkoutQualityScore?
    public var aggregateQuality: AggregateQualityScore?
    public var trainingState: TrainingStateSummary?
    public var completedHistory: [Workout] = []

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
    public let userPreferencesService: UserPreferencesService?
    private let bodyWeightProvider: BodyWeightProvider?

    public var weightUnit: WeightUnit { userPreferencesService?.weightUnit ?? .kg }

    private var lastInsightsLoadTime: Date?
    private let dataRevision: DataRevision?
    private var lastLoadedRevision: Int?
    private var inflightLoad: Task<Int?, Never>?

    /// Views key their `.task(id:)` on this so any completed mutation reloads them.
    public var currentRevision: Int { dataRevision?.value ?? 0 }

    private static let migrationKey = "analytics_migration_complete"

    // MARK: - Init

    public init(
        analyticsService: WorkoutAnalyticsService,
        qualityScoreService: WorkoutQualityScoreService,
        featureGate: AnalyticsFeatureGate,
        workoutRepository: (any WorkoutRepository)? = nil,
        proFeatureGate: ProFeatureGate? = nil,
        adherenceService: AdherenceAnalysisService? = nil,
        coachingInsightService: CoachingInsightService? = nil,
        userPreferencesService: UserPreferencesService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil,
        dataRevision: DataRevision? = nil
    ) {
        self.bodyWeightProvider = bodyWeightProvider
        self.dataRevision = dataRevision
        self.analyticsService = analyticsService
        self.qualityScoreService = qualityScoreService
        self.featureGate = featureGate
        self.workoutRepository = workoutRepository
        self.proFeatureGate = proFeatureGate
        self.adherenceService = adherenceService
        self.coachingInsightService = coachingInsightService
        self.userPreferencesService = userPreferencesService
    }

    // MARK: - Dashboard (loads WorkoutInsights aggregate)

    /// Exercise deep links need source history, not the aggregate's trend gates.
    /// The destination owns this result; a late response cannot navigate the app.
    public func fetchCompletedHistory() async throws -> [Workout] {
        let workouts: [Workout]
        if let workoutRepository { workouts = try await workoutRepository.fetchAll() }
        else { workouts = completedHistory }
        try Task.checkCancellation()
        return workouts.filter { $0.completedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }

    /// Load all analytics for dashboard as a consistent snapshot
    public func loadDashboardInsights(force: Bool = false) async {
        repeat {
            let revision = dataRevision?.value
            let attempted: Int?
            if let inflightLoad {
                attempted = await inflightLoad.value
            } else {
                if !force, lastLoadedRevision == revision, insights.workoutCount > 0,
                   let last = lastInsightsLoadTime, Date().timeIntervalSince(last) < 60 { return }
                let task = Task {
                    await performInsightsLoad(revision: revision)
                    inflightLoad = nil
                    return revision
                }
                inflightLoad = task
                attempted = await task.value
            }
            if attempted == dataRevision?.value { return }
        } while !Task.isCancelled
    }

    private func performInsightsLoad(revision: Int?) async {
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

            let features = try await featureGate.unlockedFeatures()
            let next = try? await featureGate.nextUnlock()
            let raw = try await analyticsService.generateInsights()
            let history = try await workoutRepository?.fetchAll() ?? []
            let completed = history.filter { $0.completedAt != nil }
            let scoreEnabled = features.contains(.qualityScore) && workoutRepository != nil
            let response = scoreEnabled ? try await analyticsService.volumeResponse() : []
            guard revision == dataRevision?.value else { return }

            // Publish only after the final await, so a previous revision cannot
            // replace any part of the current dashboard or its historical charts.
            unlockedFeatures = features
            nextFeatureUnlock = next
            insights = applyFeatureGates(raw)
            completedHistory = completed
            trainingState = workoutRepository == nil ? nil : TrainingStateService.summarize(workouts: completed)
            let latest = completed.max { $0.trainingDate < $1.trainingDate }
            latestSessionScore = scoreEnabled ? latest.map { qualityScoreService.computeScore(for: $0, history: completed) } : nil
            aggregateQuality = scoreEnabled ? qualityScoreService.computeAggregateScore(workouts: completed) : nil
            volumeResponseAnalyses = response
            adherenceAnalysis = adherenceService?.analyze(workouts: history)
            weeklyDigest = features.contains(.weeklyDigest) && adherenceService != nil
                ? coachingInsightService?.generateWeeklyDigest(workouts: history, overloadTrends: insights.overloadTrends,
                                                              bodyWeightKg: resolvedBodyWeightKg, verdict: insights.verdict)
                : nil
            lastLoadedRevision = revision
            lastInsightsLoadTime = Date()
            errorMessage = nil
        } catch {
            guard revision == dataRevision?.value else { return }
            isMigrating = false
            errorMessage = "Failed to load insights: \(error.localizedDescription)"
            insights = .empty
        }
    }

    /// Strips data for locked features in a single pass.
    /// (Replaces the previous chain of full-struct re-inits, where each step
    /// silently dropped fields it didn't copy over.)
    private func applyFeatureGates(_ raw: WorkoutInsights) -> WorkoutInsights {
        let quality = unlockedFeatures.contains(.qualityScore)
        return WorkoutInsights(
            generatedAt: raw.generatedAt,
            workoutCount: raw.workoutCount,
            plateaus: quality && unlockedFeatures.contains(.plateauDetection) ? raw.plateaus : [],
            muscleBalance: quality ? raw.muscleBalance : nil,
            recommendations: quality ? raw.recommendations : [],
            recoveryPatterns: raw.recoveryPatterns,
            optimalVolumes: raw.optimalVolumes,
            trainingLoad: quality ? raw.trainingLoad : nil,
            overloadTrends: quality ? raw.overloadTrends : [],
            deloadRecommendation: quality ? raw.deloadRecommendation : nil,
            trainingDrift: quality ? raw.trainingDrift : nil,
            trainingPhase: quality ? raw.trainingPhase : nil,
            blockComparison: quality ? raw.blockComparison : nil,
            anomalies: quality ? raw.anomalies : [],
            highlights: quality ? raw.highlights : [],
            archetypes: raw.archetypes,
            trainingFingerprint: unlockedFeatures.contains(.trainingFingerprint) ? raw.trainingFingerprint : nil,
            timeOfDayAnalysis: raw.timeOfDayAnalysis,
            verdict: quality ? raw.verdict : nil
        )
    }

    /// First archetype not performed in 14+ days — surfaced as a "neglected workout type" nudge.
    public var staleArchetype: WorkoutArchetype? {
        insights.archetypes.first { ($0.daysSinceLastPerformed ?? 0) >= 14 }
    }

    public func recordRecovery(_ pattern: RecoveryPattern, feelsReady: Bool) async {
        guard let last = pattern.lastTrainedDate else { return }
        RecoveryFeedbackStore().record(muscle: pattern.muscleGroup, feelsReady: feelsReady,
            hoursSince: max(0, Date().timeIntervalSince(last) / 3600), predictedHours: pattern.averageRecoveryHours)
        analyticsService.invalidateDerivedCaches()
        await loadDashboardInsights(force: true)
    }

    // MARK: - Per-Workout (outside aggregate)

    public func loadSimilarWorkouts(to workout: Workout, limit: Int = 5) async {
        isSimilarWorkoutsLoading = true
        defer { isSimilarWorkoutsLoading = false }

        do {
            let results = try await analyticsService.findSimilarWorkouts(
                to: workout, limit: limit, minSimilarity: 0.7
            )
            guard !Task.isCancelled else { return }
            similarWorkouts = results
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Failed to load similar workouts: \(error.localizedDescription)"
            similarWorkouts = []
        }
    }

    public var resolvedBodyWeightKg: Double {
        bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    public func historicalQuality() -> [QualityHistoryObservation] {
        qualityScoreService.computeHistory(workouts: completedHistory)
    }

    public func historicalLoad() -> TrainingLoad? {
        let now = Date()
        let bests = AnalyticsCalculations.buildBestE1RMMap(from: completedHistory.filter { !$0.isDeload }, bodyWeightKg: resolvedBodyWeightKg, asOf: now)
        return TrainingLoadService.computeTrainingLoad(bodyWeightKg: resolvedBodyWeightKg, workouts: completedHistory, bestE1RM: bests, now: now, historyDays: nil)
    }

    public var loggedExercises: [Exercise] {
        var seen = Set<UUID>()
        return completedHistory.sorted { $0.trainingDate > $1.trainingDate }.flatMap(\.exercises).map(\.exercise)
            .filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The requesting detail view owns this result and its loading state.
    public func score(for workout: Workout) async throws -> WorkoutQualityScore {
        try await qualityScoreService.computeScore(for: workout)
    }

    // MARK: - Advanced Insights Accessors

    public var advancedInsightsLoaded: Bool {
        trainingState != nil
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
        AnalyticsFormatting.acwr(acwr)
    }

    public func formatSlope(_ slope: Double) -> String {
        AnalyticsFormatting.slope(kgPerWeek: slope, unit: weightUnit)
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
        case .sequencePrediction: return "Sequence Prediction"
        case .workoutSuggestion: return "Workout Suggestions"
        case .muscleBalance: return "Muscle Balance"
        case .recoveryTimeline: return "Recovery Timeline"
        case .advancedInsights: return "Advanced Insights"
        case .trainingFingerprint: return "Training Fingerprint"
        case .muscleNeglect: return "Muscle Neglect Detection"
        case .timeOfDayAnalysis: return "Time-of-Day Analysis"
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
        case .sequencePrediction: return "Predict your likely next workout type"
        case .workoutSuggestion: return "Recovery-aware next workout suggestion"
        case .muscleBalance: return "Check if opposing muscle groups are trained evenly"
        case .recoveryTimeline: return "Optimal rest days between sessions"
        case .advancedInsights: return "Deep analysis across your full training history"
        case .trainingFingerprint: return "Your training variety and consistency profile"
        case .muscleNeglect: return "Detect declining volume in muscle groups"
        case .timeOfDayAnalysis: return "Find your optimal training window"
        }
    }
}
