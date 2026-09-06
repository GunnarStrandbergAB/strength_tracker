import Foundation

/// High-level orchestrator for all analytics operations.
/// Coordinates between vectorizer, search, and domain-specific services.
/// Caches frequently accessed data.
@MainActor
public final class WorkoutAnalyticsService: Sendable {

    private let analyticsRepository: any AnalyticsRepository
    private let workoutRepository: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository
    private let vectorizer: WorkoutVectorizer
    private let searchService: VectorSearchService
    private let plateauService: PlateauDetectionService
    private let muscleBalanceService: MuscleBalanceService
    private let recommendationService: ExerciseRecommendationService

    private let trainingStatusDetector: TrainingStatusDetector?
    private let userPreferencesService: UserPreferencesService?
    private let bodyWeightProvider: BodyWeightProvider?
    /// Single resolved body weight for every volume/e1RM computation in this service.
    private var resolvedBodyWeightKg: Double {
        bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    /// Current vector schema version — bump when normalization constants change
    // v3: WorkoutVector.createdAt now carries the training date (workout.startedAt)
    // instead of vectorization wall-clock time — re-vectorize once so historical
    // vectors get correct dates.
    // v4: vectors are computed from effective load (bodyweight base + extra kg)
    /// v5: vectors are built with the resolved body weight (earlier ones used 70 kg).
    private static let currentVectorVersion = 5

    // Advanced Insights services
    private let volumeLandmarkService: VolumeLandmarkService?
    private let recoveryEstimationService: RecoveryEstimationService?
    private let driftService: TrainingDriftService?
    private let phaseDetectionService: PhaseDetectionService?
    private let blockComparisonService: BlockComparisonService?
    private let anomalyDetectionService: AnomalyDetectionService?
    private let insightGenerator: (any InsightTextGenerating)?
    private let archetypeService: WorkoutArchetypeService?
    private let changePointService: ChangePointDetectionService?
    private let qualityScoreService: WorkoutQualityScoreService?
    private let trainingAdvisor: TrainingAdvisor?

    // Caches, all keyed on the data revision so any completed mutation drops them.
    private let dataRevision: DataRevision?
    private var cachedInsights: (revision: Int, window: TimeInterval, insights: WorkoutInsights)?
    // Stable routine membership; included in the time-limited analytics snapshot.
    private var cachedArchetypes: [WorkoutArchetype] = []
    private var archetypeCacheRevision: Int = -1
    // Quality scores memoized per workout (completed workouts are immutable).

    public init(
        analyticsRepository: any AnalyticsRepository,
        workoutRepository: any WorkoutRepository,
        exerciseRepository: any ExerciseRepository,
        vectorizer: WorkoutVectorizer,
        searchService: VectorSearchService,
        plateauService: PlateauDetectionService,
        muscleBalanceService: MuscleBalanceService,
        recommendationService: ExerciseRecommendationService,
        trainingStatusDetector: TrainingStatusDetector? = nil,
        userPreferencesService: UserPreferencesService? = nil,
        volumeLandmarkService: VolumeLandmarkService? = nil,
        recoveryEstimationService: RecoveryEstimationService? = nil,
        driftService: TrainingDriftService? = nil,
        phaseDetectionService: PhaseDetectionService? = nil,
        blockComparisonService: BlockComparisonService? = nil,
        anomalyDetectionService: AnomalyDetectionService? = nil,
        insightGenerator: (any InsightTextGenerating)? = nil,
        archetypeService: WorkoutArchetypeService? = nil,
        changePointService: ChangePointDetectionService? = nil,
        qualityScoreService: WorkoutQualityScoreService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil,
        dataRevision: DataRevision? = nil,
        trainingAdvisor: TrainingAdvisor? = nil
    ) {
        self.trainingAdvisor = trainingAdvisor
        self.bodyWeightProvider = bodyWeightProvider
        self.dataRevision = dataRevision
        self.analyticsRepository = analyticsRepository
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
        self.vectorizer = vectorizer
        self.searchService = searchService
        self.plateauService = plateauService
        self.muscleBalanceService = muscleBalanceService
        self.recommendationService = recommendationService
        self.trainingStatusDetector = trainingStatusDetector
        self.userPreferencesService = userPreferencesService
        self.volumeLandmarkService = volumeLandmarkService
        self.recoveryEstimationService = recoveryEstimationService
        self.driftService = driftService
        self.phaseDetectionService = phaseDetectionService
        self.blockComparisonService = blockComparisonService
        self.anomalyDetectionService = anomalyDetectionService
        self.insightGenerator = insightGenerator
        self.archetypeService = archetypeService
        self.changePointService = changePointService
        self.qualityScoreService = qualityScoreService
    }

    // MARK: - Similar Workouts

    /// Find workouts similar to the given workout
    public func findSimilarWorkouts(
        to workout: Workout,
        limit: Int = 5,
        minSimilarity: Double = 0.7
    ) async throws -> [SimilarWorkout] {
        // Ensure workout is vectorized
        try await ensureVectorized(workout)

        // Get all vectors
        let allVectors = try await analyticsRepository.fetchAllVectors()
        let queryVector = allVectors.first { $0.workoutId == workout.id }

        guard let queryVector = queryVector else {
            throw AnalyticsError.vectorNotFound
        }

        // Search for similar vectors (exclude self)
        let vectors = allVectors.filter { $0.workoutId != workout.id }
        let similarities = searchService.findSimilar(
            query: queryVector.dimensions,
            vectors: vectors.map(\.dimensions),
            topK: limit * 2
        )

        // Filter by minimum similarity and map to domain
        let filtered = similarities.filter { $0.similarity >= minSimilarity }
        let topResults = Array(filtered.prefix(limit))

        // Fetch corresponding workouts
        let allWorkouts = try await workoutRepository.fetchAll()
        let workoutMap = Dictionary(allWorkouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let displayBodyWeightKg = resolvedBodyWeightKg

        return topResults.compactMap { result in
            guard result.index < vectors.count else { return nil }
            let matchedVector = vectors[result.index]
            guard let matchedWorkout = workoutMap[matchedVector.workoutId] else { return nil }

            let matchedFeatures = identifyTopMatchedFeatures(
                query: queryVector.dimensions,
                match: matchedVector.dimensions,
                topK: 3
            )

            return SimilarWorkout(
                id: UUID(),
                workoutId: matchedWorkout.id,
                workoutName: matchedWorkout.name,
                workoutDate: matchedWorkout.startedAt,
                totalVolume: matchedWorkout.totalVolume(bodyWeightKg: displayBodyWeightKg),
                similarityScore: result.similarity,
                matchedFeatures: matchedFeatures
            )
        }
    }

    // MARK: - Dashboard Aggregate

    /// Generate a consistent WorkoutInsights snapshot for the dashboard
    public func generateInsights(timeWindow: TimeInterval = 2_592_000, now: Date = Date()) async throws -> WorkoutInsights {
        if let dataRevision, let cached = cachedInsights,
           cached.revision == dataRevision.value, cached.window == timeWindow, now >= cached.insights.generatedAt, now.timeIntervalSince(cached.insights.generatedAt) < 60 {
            return cached.insights
        }
        let insights = try await computeInsights(timeWindow: timeWindow, now: now)
        if let dataRevision {
            cachedInsights = (dataRevision.value, timeWindow, insights)
        }
        return insights
    }

    /// Drops every derived in-memory cache. Called by the finalizer after any
    /// completed mutation (the revision bump alone already misses `cachedArchetypes`
    /// only when the value wraps, but be explicit).
    public func invalidateDerivedCaches() {
        cachedInsights = nil
        cachedArchetypes = []
        archetypeCacheRevision = -1
    }

    private func computeInsights(timeWindow: TimeInterval, now: Date) async throws -> WorkoutInsights {
        // Migrate vectors if normalization constants changed
        let bodyWeightKg = resolvedBodyWeightKg
        try await migrateVectorsIfNeeded(bodyWeightKg: bodyWeightKg)

        let workouts = try await workoutRepository.fetchAll()
        let completedWorkouts = workouts.filter { $0.completedAt != nil && $0.trainingDate <= now }
        let nonDeloadWorkouts = completedWorkouts.filter { !$0.isDeload }

        // One canonical exercise-progress result. Legacy plateau/recommendation fields remain
        // empty for backwards-compatible decoding, not as a second source of advice.
        let plateausResult: [PlateauAnalysis] = []
        let recommendationsResult: [ExerciseRecommendation] = []
        let muscleBalanceResult = muscleBalanceService.analyze(workouts: completedWorkouts, timeWindow: timeWindow, bodyWeightKg: bodyWeightKg, now: now)

        // Recovery patterns (Phase 3) — include deloads (affects recovery timelines)
        let recoveryPatterns = try await recoveryEstimationService?.computeRecoveryPatterns(workouts: completedWorkouts, bodyWeightKg: bodyWeightKg, now: now) ?? []

        // Volume landmarks (Phase 4) — exclude deloads (don't lower averages)
        let optimalVolumes = try await volumeLandmarkService?.computeVolumeLandmarks(workouts: nonDeloadWorkouts) ?? []

        // Advanced Insights (50+ workouts)
        var trainingLoad: TrainingLoad?
        var overloadTrends: [OverloadTrend] = []
        var deloadRecommendation: DeloadRecommendation?
        var trainingDrift: TrainingDrift?
        var trainingPhase: TrainingPhaseDetection?
        var blockComparison: BlockComparison?
        var anomalies: [WorkoutAnomaly] = []
        var highlights: [AnalyticsHighlight] = []
        var archetypes: [WorkoutArchetype] = []
        var trainingFingerprint: TrainingFingerprint?
        var timeOfDayAnalysis: TimeOfDayAnalysis?
        var verdict: TrainingVerdict?

        if completedWorkouts.count >= AnalyticsFeatureGate.threshold(for: .qualityScore) {
            let bestE1RM = AnalyticsCalculations.buildBestE1RMMap(from: nonDeloadWorkouts, bodyWeightKg: bodyWeightKg, asOf: now)

            // Core services: ACWR needs all workouts (must see load drop), others exclude deloads
            trainingLoad = TrainingLoadService.computeTrainingLoad(
                bodyWeightKg: bodyWeightKg, workouts: completedWorkouts, bestE1RM: bestE1RM, now: now
            )
            overloadTrends = OverloadTrackingService.computeOverloadTrends(workouts: nonDeloadWorkouts, bodyWeightKg: bodyWeightKg, now: now)
            deloadRecommendation = DeloadDetectionService.detectDeload(
                bodyWeightKg: bodyWeightKg,
                workouts: completedWorkouts,
                overloadTrends: overloadTrends,
                trainingLoad: trainingLoad,
                bestE1RM: bestE1RM, now: now
            )

            // The one deload / hold / progress call every surface consults.
            verdict = (trainingLoad != nil || overloadTrends.contains { $0.trendStatus != .inactive && $0.trendStatus != .uncertain }) ? trainingAdvisor?.evaluate(TrainingAdvisor.Input(
                workouts: completedWorkouts,
                trainingLoad: trainingLoad,
                overloadTrends: overloadTrends,
                deloadRecommendation: deloadRecommendation,
                recoveryPatterns: recoveryPatterns, now: now
            )) : nil
            let activeDeload = verdict?.isActiveDeload ?? false

            // Vector-powered services — filter deload vectors for drift/anomaly/block
            let allVectors = try await analyticsRepository.fetchAllVectors()
            let deloadWorkoutIds = Set(completedWorkouts.filter(\.isDeload).map(\.id))
            let nonDeloadVectors = allVectors.filter { !deloadWorkoutIds.contains($0.workoutId) }

            trainingDrift = driftService?.computeDrift(vectors: nonDeloadVectors)
            trainingPhase = phaseDetectionService?.detectPhases(vectors: allVectors)
            blockComparison = blockComparisonService?.compareBlocks(vectors: nonDeloadVectors)
            anomalies = anomalyDetectionService?.detectAnomalies(vectors: nonDeloadVectors) ?? []

            // Workout archetypes + training fingerprint.
            // Frequencies and comparison windows advance without requiring a workout edit.
            if let archetypeService {
                let revision = dataRevision?.value ?? nonDeloadVectors.count
                do { // Refresh time-dependent frequencies even when history is unchanged.
                    cachedArchetypes = archetypeService.cluster(
                        vectors: nonDeloadVectors, workouts: nonDeloadWorkouts, bodyWeightKg: bodyWeightKg
                    )
                    archetypeCacheRevision = revision
                }
                archetypes = cachedArchetypes
                trainingFingerprint = archetypeService.fingerprint(
                    archetypes: archetypes, vectors: nonDeloadVectors
                )
            }

            // Time-of-day quality analysis (per-workout scores come from the quality
            // service's own memo, which the finalizer invalidates on every change).
            if let changePointService, let qualityScoreService {
                var qualityScores: [UUID: WorkoutQualityScore] = [:]
                for workout in completedWorkouts {
                    qualityScores[workout.id] = qualityScoreService.computeScore(
                        for: workout, history: completedWorkouts
                    )
                }
                timeOfDayAnalysis = changePointService.analyzeTimeOfDay(
                    workouts: completedWorkouts, qualityScores: qualityScores, now: now
                )
            }

            // Smart highlights (the generator owns the verdict-aware rules, so
            // no post-filtering here)
            if let generator = insightGenerator {
                highlights = await generator.generateHighlights(
                    trainingLoad: trainingLoad,
                    overloadTrends: overloadTrends,
                    deloadRecommendation: deloadRecommendation,
                    trainingDrift: activeDeload ? nil : trainingDrift,
                    trainingPhase: trainingPhase,
                    recoveryPatterns: recoveryPatterns,
                    optimalVolumes: optimalVolumes,
                    verdict: verdict
                )
            }
        }

        return WorkoutInsights(
            generatedAt: now,
            workoutCount: completedWorkouts.count,
            plateaus: plateausResult,
            muscleBalance: muscleBalanceResult,
            recommendations: recommendationsResult,
            recoveryPatterns: recoveryPatterns,
            optimalVolumes: optimalVolumes,
            trainingLoad: trainingLoad,
            overloadTrends: overloadTrends,
            deloadRecommendation: deloadRecommendation,
            trainingDrift: trainingDrift,
            trainingPhase: trainingPhase,
            blockComparison: blockComparison,
            anomalies: anomalies,
            highlights: highlights,
            archetypes: archetypes,
            trainingFingerprint: trainingFingerprint,
            timeOfDayAnalysis: timeOfDayAnalysis,
            verdict: verdict
        )
    }

    public func volumeResponse(muscle: String? = nil, lookbackWeeks: Int = 104, now: Date = Date()) async throws -> [VolumeResponseAnalysis] {
        let weeks = min(260, max(8, lookbackWeeks))
        let cutoff = Calendar.mondayStart.date(byAdding: .weekOfYear, value: -weeks, to: now)!
        let workouts = try await workoutRepository.fetchAll().filter { $0.trainingDate >= cutoff && $0.trainingDate <= now }
        let series = OverloadTrackingService.computeOverloadTrends(workouts: workouts, bodyWeightKg: resolvedBodyWeightKg, now: now)
        return VolumeResponseService.computeAnalyses(workouts: workouts, overloadTrends: series, now: now)
            .filter { muscle == nil || $0.muscleGroup.caseInsensitiveCompare(muscle!) == .orderedSame }
    }

    // MARK: - Vector Access

    /// Fetch all stored workout vectors.
    public func fetchAllVectors() async throws -> [WorkoutVector] {
        try await analyticsRepository.fetchAllVectors()
    }

    // MARK: - Vectorization Management

    /// Ensure a workout has been vectorized
    public func ensureVectorized(_ workout: Workout) async throws {
        let existing = try await analyticsRepository.fetchVector(for: workout.id)
        if existing == nil {
            try await vectorizeWorkout(workout)
        }
    }

    /// Vectorize a single workout and store
    public func vectorizeWorkout(_ workout: Workout) async throws {
        let bodyWeightKg = resolvedBodyWeightKg
        let allWorkouts = try await workoutRepository.fetchAll()
        let vector = vectorizer.vectorize(workout, historicalWorkouts: allWorkouts, bodyWeightKg: bodyWeightKg)

        // Compute denormalized metadata for the entity
        let totalVolume = vectorizer.calculateTotalVolume(workout, bodyWeightKg: bodyWeightKg)
        let primaryMuscleGroups = computePrimaryMuscleGroups(workout, bodyWeightKg: bodyWeightKg)

        try await analyticsRepository.storeVector(
            vector,
            totalVolume: totalVolume,
            workoutDate: workout.startedAt,
            primaryMuscleGroups: primaryMuscleGroups
        )
        // Re-vectorization implies the workout changed — memoized quality scores are
        // history-relative, so drop them all (cheap; recomputed lazily).
        qualityScoreService?.invalidateAll()
        invalidateDerivedCaches()
    }

    /// Deletes vectors whose workout no longer exists or is not completed.
    public func sweepOrphanVectors() async throws {
        let completedIds = Set(try await workoutRepository.fetchAll().filter { $0.completedAt != nil }.map(\.id))
        for vector in try await analyticsRepository.fetchAllVectors() where !completedIds.contains(vector.workoutId) {
            try await analyticsRepository.deleteVector(for: vector.workoutId)
        }
    }

    /// Batch vectorize all workouts missing vectors
    public func vectorizeAllWorkouts() async throws {
        let bodyWeightKg = resolvedBodyWeightKg
        let allWorkouts = try await workoutRepository.fetchAll()
        let existingVectors = try await analyticsRepository.fetchAllVectors()
        let vectorizedIds = Set(existingVectors.map(\.workoutId))

        // Only completed workouts get vectors; an active workout that is later
        // cancelled would otherwise leave an orphan behind.
        let needsVectorization = allWorkouts.filter { $0.completedAt != nil && !vectorizedIds.contains($0.id) }

        for workout in needsVectorization {
            let vector = vectorizer.vectorize(workout, historicalWorkouts: allWorkouts, bodyWeightKg: bodyWeightKg)
            let totalVolume = vectorizer.calculateTotalVolume(workout, bodyWeightKg: bodyWeightKg)
            let primaryMuscleGroups = computePrimaryMuscleGroups(workout, bodyWeightKg: bodyWeightKg)
            try await analyticsRepository.storeVector(
                vector,
                totalVolume: totalVolume,
                workoutDate: workout.startedAt,
                primaryMuscleGroups: primaryMuscleGroups
            )
        }

    }

    // MARK: - Vector Migration

    /// Re-vectorize all workouts if normalization constants have changed.
    private func migrateVectorsIfNeeded(bodyWeightKg: Double) async throws {
        guard let prefs = userPreferencesService,
              prefs.vectorVersion < Self.currentVectorVersion else { return }
        try await analyticsRepository.deleteAllVectors()
        try await vectorizeAllWorkouts()
        prefs.vectorVersion = Self.currentVectorVersion
    }

    // MARK: - Helpers

    /// Top 3 muscle groups by volume for a workout
    private func computePrimaryMuscleGroups(_ workout: Workout, bodyWeightKg: Double) -> [String] {
        var volumes: [String: Double] = [:]
        for exercise in workout.exercises {
            // Drop-aware; also now excludes warmups like every other volume site
            // (this only feeds muscle-group ranking).
            let vol = exercise.exerciseVolume(bodyWeightKg: bodyWeightKg)
            let group = exercise.exercise.primaryMuscleGroup.rawValue
            volumes[group, default: 0] += vol
        }
        return volumes.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    private func identifyTopMatchedFeatures(
        query: [Double],
        match: [Double],
        topK: Int
    ) -> [String] {
        let differences = zip(query, match).map { abs($0 - $1) }
        let indexed = differences.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { $0.1 < $1.1 }

        return sorted.prefix(topK).compactMap { index, _ in
            index < WorkoutVector.featureNames.count ? WorkoutVector.featureNames[index] : nil
        }
    }
}
