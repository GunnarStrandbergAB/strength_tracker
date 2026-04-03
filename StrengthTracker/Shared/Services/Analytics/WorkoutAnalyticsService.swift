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

    /// Current vector schema version — bump when normalization constants change
    private static let currentVectorVersion = 2

    // Advanced Insights services
    private let volumeLandmarkService: VolumeLandmarkService?
    private let recoveryEstimationService: RecoveryEstimationService?
    private let driftService: TrainingDriftService?
    private let phaseDetectionService: PhaseDetectionService?
    private let blockComparisonService: BlockComparisonService?
    private let anomalyDetectionService: AnomalyDetectionService?
    private let insightGenerator: (any InsightTextGenerating)?

    // Cache
    private var cachedVectors: [UUID: WorkoutVector] = [:]
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300

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
        insightGenerator: (any InsightTextGenerating)? = nil
    ) {
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
        let workoutMap = Dictionary(uniqueKeysWithValues: allWorkouts.map { ($0.id, $0) })

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
                totalVolume: matchedWorkout.totalVolume,
                similarityScore: result.similarity,
                matchedFeatures: matchedFeatures
            )
        }
    }

    // MARK: - Dashboard Aggregate

    /// Generate a consistent WorkoutInsights snapshot for the dashboard
    public func generateInsights(timeWindow: TimeInterval = 2_592_000) async throws -> WorkoutInsights {
        // Migrate vectors if normalization constants changed
        let bodyWeightKg = userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
        try await migrateVectorsIfNeeded(bodyWeightKg: bodyWeightKg)

        let workouts = try await workoutRepository.fetchAll()
        let completedWorkouts = workouts.filter { $0.completedAt != nil }
        let nonDeloadWorkouts = completedWorkouts.filter { !$0.isDeload }
        let latestIsDeload = completedWorkouts
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .last?.isDeload ?? false

        let trainingStatus = try await trainingStatusDetector?.detect() ?? .intermediate
        let plateausResult = plateauService.analyzePlateaus(workouts: nonDeloadWorkouts, trainingStatus: trainingStatus)
        let muscleBalanceResult = muscleBalanceService.analyze(workouts: nonDeloadWorkouts, timeWindow: timeWindow)

        // Generate recommendations using plateau and balance data
        let availableExercises = try await exerciseRepository.fetchAll()
        let recommendationsResult = recommendationService.generateRecommendations(
            workouts: nonDeloadWorkouts,
            availableExercises: availableExercises,
            muscleBalance: muscleBalanceResult,
            plateaus: plateausResult,
            limit: 5
        )

        // Recovery patterns (Phase 3) — include deloads (affects recovery timelines)
        let recoveryPatterns = try await recoveryEstimationService?.computeRecoveryPatterns(workouts: completedWorkouts) ?? []

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

        if completedWorkouts.count >= 19 {
            let bestE1RM = AnalyticsCalculations.buildBestE1RMMap(from: nonDeloadWorkouts)

            // Core services: ACWR needs all workouts (must see load drop), others exclude deloads
            trainingLoad = TrainingLoadService.computeTrainingLoad(
                workouts: completedWorkouts, bestE1RM: bestE1RM
            )
            overloadTrends = OverloadTrackingService.computeOverloadTrends(workouts: nonDeloadWorkouts)
            deloadRecommendation = DeloadDetectionService.detectDeload(
                workouts: completedWorkouts,
                overloadTrends: overloadTrends,
                trainingLoad: trainingLoad,
                bestE1RM: bestE1RM
            )

            // Vector-powered services — filter deload vectors for drift/anomaly/block
            let allVectors = try await analyticsRepository.fetchAllVectors()
            let deloadWorkoutIds = Set(completedWorkouts.filter(\.isDeload).map(\.id))
            let nonDeloadVectors = allVectors.filter { !deloadWorkoutIds.contains($0.workoutId) }

            trainingDrift = driftService?.computeDrift(vectors: nonDeloadVectors)
            trainingPhase = phaseDetectionService?.detectPhases(vectors: allVectors)
            blockComparison = blockComparisonService?.compareBlocks(vectors: nonDeloadVectors)
            anomalies = anomalyDetectionService?.detectAnomalies(vectors: nonDeloadVectors) ?? []

            // Smart highlights
            if let generator = insightGenerator {
                highlights = await generator.generateHighlights(
                    trainingLoad: trainingLoad,
                    overloadTrends: overloadTrends,
                    deloadRecommendation: deloadRecommendation,
                    trainingDrift: latestIsDeload ? nil : trainingDrift,
                    trainingPhase: trainingPhase,
                    recoveryPatterns: recoveryPatterns,
                    optimalVolumes: optimalVolumes
                )

                // During active deload, suppress false warnings and add positive highlight
                if latestIsDeload {
                    highlights = highlights.filter {
                        ($0.type != .warning || $0.title == "Deload Recommended") &&
                        $0.title != "Optimal Training Load"
                    }
                    let deloadHighlight = AnalyticsHighlight(
                        type: .improvement,
                        title: "Deload In Progress",
                        detail: "Intentional recovery phase — reduced volume and intensity as planned"
                    )
                    highlights.insert(deloadHighlight, at: 0)
                }
            }
        } else if completedWorkouts.count >= 5, let generator = insightGenerator {
            // Early highlights from Phase 2/3 data (plateaus, balance, recommendations)
            highlights = await generator.generateEarlyHighlights(
                plateaus: plateausResult,
                muscleBalance: muscleBalanceResult,
                recommendations: recommendationsResult,
                workoutCount: completedWorkouts.count
            )
        }

        return WorkoutInsights(
            generatedAt: Date(),
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
            highlights: highlights
        )
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
    public func vectorizeWorkout(_ workout: Workout, bodyWeightKg: Double = UserPreferencesService.defaultBodyWeightKg) async throws {
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
        cachedVectors[workout.id] = vector
    }

    /// Batch vectorize all workouts missing vectors
    public func vectorizeAllWorkouts(bodyWeightKg: Double = UserPreferencesService.defaultBodyWeightKg) async throws {
        let allWorkouts = try await workoutRepository.fetchAll()
        let existingVectors = try await analyticsRepository.fetchAllVectors()
        let vectorizedIds = Set(existingVectors.map(\.workoutId))

        let needsVectorization = allWorkouts.filter { !vectorizedIds.contains($0.id) }

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

        cachedVectors.removeAll()
        cacheTimestamp = nil
    }

    // MARK: - Vector Migration

    /// Re-vectorize all workouts if normalization constants have changed.
    private func migrateVectorsIfNeeded(bodyWeightKg: Double) async throws {
        guard let prefs = userPreferencesService,
              prefs.vectorVersion < Self.currentVectorVersion else { return }
        try await analyticsRepository.deleteAllVectors()
        try await vectorizeAllWorkouts(bodyWeightKg: bodyWeightKg)
        prefs.vectorVersion = Self.currentVectorVersion
    }

    // MARK: - Helpers

    /// Top 3 muscle groups by volume for a workout
    private func computePrimaryMuscleGroups(_ workout: Workout, bodyWeightKg: Double) -> [String] {
        var volumes: [String: Double] = [:]
        for exercise in workout.exercises {
            let vol = exercise.sets.filter(\.isCompleted).reduce(0.0) { sum, set in
                let weight = set.weight ?? (exercise.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0.0)
                return sum + weight * Double(set.reps ?? 0)
            }
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
