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
        let revision = dataRevision?.value
        let insights = try await computeInsights(timeWindow: timeWindow, now: now, revision: revision)
        guard revision == dataRevision?.value else { throw CancellationError() }
        if let revision {
            cachedInsights = (revision, timeWindow, insights)
        }
        return insights
    }

    public func invalidateDerivedCaches() {
        cachedInsights = nil
    }

    private func computeInsights(timeWindow: TimeInterval, now: Date, revision: Int?) async throws -> WorkoutInsights {
        // Migrate vectors if normalization constants changed
        let bodyWeightKg = resolvedBodyWeightKg
        try await migrateVectorsIfNeeded()

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

            // The advisor persists its verdict. Discard superseded input before writing it.
            guard revision == dataRevision?.value else { throw CancellationError() }
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
                archetypes = archetypeService.cluster(
                    vectors: nonDeloadVectors, workouts: nonDeloadWorkouts, bodyWeightKg: bodyWeightKg
                )
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
        if try await analyticsRepository.fetchVector(for: workout.id) == nil {
            try await vectorizeWorkout(workout)
        }
    }

    // A lazy backfill and a History edit can run concurrently. Acquire the
    // writer before fetching source history so an older batch cannot write last.
    private var vectorWriter: Task<Void, Never>?
    private func updateVectors<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = vectorWriter
        let task = Task {
            await previous?.value
            return try await operation()
        }
        vectorWriter = Task { _ = await task.result }
        return try await task.value
    }

    public func vectorizeWorkout(_ workout: Workout) async throws {
        try await updateVectors { [self] in
            let history = try await workoutRepository.fetchAll()
            guard let saved = history.first(where: { $0.id == workout.id && $0.completedAt != nil }) else { return }
            try await storeVector(for: saved, history: history, bodyWeightKg: resolvedBodyWeightKg)
            qualityScoreService?.invalidateAll()
            invalidateDerivedCaches()
        }
    }

    /// Upsert from one post-election history snapshot. For deletes and date
    /// corrections the old date still identifies sessions that used its volume.
    @discardableResult
    func rebuildVectors(after mutation: Workout, previous: Workout? = nil, changedRecordIds: Set<UUID>,
                        checkLiveRecords: Bool = false) async throws -> Workout? {
        try await updateVectors { [self] in
            let history = try await workoutRepository.fetchAll().filter { $0.completedAt != nil }
            let saved = history.first { $0.id == mutation.id }
            if saved == nil { try await analyticsRepository.deleteVector(for: mutation.id) }

            // Live PR re-election can change flags on earlier sessions before
            // Finish. Check their stored count without vectorizing every session.
            let vectors = checkLiveRecords ? try await analyticsRepository.fetchAllVectors() : []
            let byId = Dictionary(vectors.map { ($0.workoutId, $0) }, uniquingKeysWith: { first, _ in first })
            let dates = Set([previous, mutation, saved].compactMap { $0?.completedAt })
            let bodyWeightKg = resolvedBodyWeightKg
            for workout in history {
                let dependent = dates.contains { WorkoutVectorizer.usesVolume(completedAt: $0, in: workout) }
                let needsRecordUpdate = checkLiveRecords && !workout.exerciseIds.isDisjoint(with: mutation.exerciseIds)
                    && !vectorizer.matchesRecordCount(byId[workout.id], workout: workout)
                if workout.id == mutation.id || changedRecordIds.contains(workout.id) || dependent || needsRecordUpdate {
                    try await storeVector(for: workout, history: history, bodyWeightKg: bodyWeightKg)
                }
            }
            return saved
        }
    }

    private func storeVector(for workout: Workout, history: [Workout], bodyWeightKg: Double) async throws {
        let vector = vectorizer.vectorize(workout, historicalWorkouts: history, bodyWeightKg: bodyWeightKg)
        try await analyticsRepository.storeVector(vector,
            totalVolume: vectorizer.calculateTotalVolume(workout, bodyWeightKg: bodyWeightKg),
            workoutDate: workout.startedAt,
            primaryMuscleGroups: computePrimaryMuscleGroups(workout, bodyWeightKg: bodyWeightKg))
    }

    public func sweepOrphanVectors() async throws {
        try await updateVectors { [self] in
            let completedIds = Set(try await workoutRepository.fetchAll().filter { $0.completedAt != nil }.map(\.id))
            try await deleteOrphans(in: analyticsRepository.fetchAllVectors(), completedIds: completedIds)
        }
    }

    private func deleteOrphans(in vectors: [WorkoutVector], completedIds: Set<UUID>) async throws {
        for vector in vectors where !completedIds.contains(vector.workoutId) {
            try await analyticsRepository.deleteVector(for: vector.workoutId)
        }
    }

    /// Backfill missing rows. A repair also replaces existing rows and removes orphans.
    public func vectorizeAllWorkouts(replacingExisting: Bool = false) async throws {
        try await updateVectors { [self] in
            let history = try await workoutRepository.fetchAll().filter { $0.completedAt != nil }
            let vectors = try await analyticsRepository.fetchAllVectors()
            let existingIds = Set(vectors.map(\.workoutId))
            let bodyWeightKg = resolvedBodyWeightKg
            for workout in history where replacingExisting || !existingIds.contains(workout.id) {
                try await storeVector(for: workout, history: history, bodyWeightKg: bodyWeightKg)
            }
            if replacingExisting { try await deleteOrphans(in: vectors, completedIds: Set(history.map(\.id))) }
        }
    }

    // MARK: - Vector Migration

    /// Re-vectorize all workouts if normalization constants have changed.
    private func migrateVectorsIfNeeded() async throws {
        guard let prefs = userPreferencesService,
              prefs.vectorVersion < Self.currentVectorVersion else { return }
        try await vectorizeAllWorkouts(replacingExisting: true)
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
