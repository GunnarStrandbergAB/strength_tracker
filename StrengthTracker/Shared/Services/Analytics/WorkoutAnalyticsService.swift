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
        recommendationService: ExerciseRecommendationService
    ) {
        self.analyticsRepository = analyticsRepository
        self.workoutRepository = workoutRepository
        self.exerciseRepository = exerciseRepository
        self.vectorizer = vectorizer
        self.searchService = searchService
        self.plateauService = plateauService
        self.muscleBalanceService = muscleBalanceService
        self.recommendationService = recommendationService
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
        let workouts = try await workoutRepository.fetchAll()
        let completedWorkouts = workouts.filter { $0.completedAt != nil }

        let plateausResult = plateauService.analyzePlateaus(workouts: completedWorkouts)
        let muscleBalanceResult = muscleBalanceService.analyze(workouts: completedWorkouts, timeWindow: timeWindow)

        // Generate recommendations using plateau and balance data
        let availableExercises = try await exerciseRepository.fetchAll()
        let recommendationsResult = recommendationService.generateRecommendations(
            workouts: completedWorkouts,
            availableExercises: availableExercises,
            muscleBalance: muscleBalanceResult,
            plateaus: plateausResult,
            limit: 5
        )

        return WorkoutInsights(
            generatedAt: Date(),
            workoutCount: completedWorkouts.count,
            plateaus: plateausResult,
            muscleBalance: muscleBalanceResult,
            recommendations: recommendationsResult,
            recoveryPatterns: [],  // Phase 3 feature — requires per-muscle-group date tracking
            optimalVolumes: []     // Phase 4 feature — requires 50+ workouts of history
        )
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
    public func vectorizeWorkout(_ workout: Workout, bodyWeightKg: Double = 70.0) async throws {
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
    public func vectorizeAllWorkouts(bodyWeightKg: Double = 70.0) async throws {
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
