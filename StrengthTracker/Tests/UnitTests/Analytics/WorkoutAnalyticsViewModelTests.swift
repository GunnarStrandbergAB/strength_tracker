import XCTest
import Foundation
@testable import StrengthTrackerShared

/// Tests for WorkoutAnalyticsViewModel.
/// Verifies that the ViewModel correctly orchestrates its service dependencies,
/// manages loading state, and handles errors gracefully.
final class WorkoutAnalyticsViewModelTests: XCTestCase {

    // MARK: - Initial State

    @MainActor
    func test_initialState_hasEmptyInsights() async {
        let (vm, _, _, _) = Self.makeViewModel()
        XCTAssertEqual(vm.insights.workoutCount, 0)
        XCTAssertTrue(vm.insights.plateaus.isEmpty)
        XCTAssertNil(vm.insights.muscleBalance)
        XCTAssertTrue(vm.insights.recommendations.isEmpty)
        XCTAssertFalse(vm.isInsightsLoading)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_initialState_hasEmptySimilarWorkouts() async {
        let (vm, _, _, _) = Self.makeViewModel()
        XCTAssertTrue(vm.similarWorkouts.isEmpty)
        XCTAssertFalse(vm.isSimilarWorkoutsLoading)
    }

    @MainActor
    func test_initialState_hasNilQualityScore() async {
        let (vm, _, _, _) = Self.makeViewModel()
        XCTAssertNil(vm.qualityScore)
        XCTAssertFalse(vm.isQualityScoreLoading)
    }

    // MARK: - loadDashboardInsights

    @MainActor
    func test_loadDashboardInsights_setsInsights() async {
        let (vm, _, workoutRepo, _) = Self.makeViewModel()
        let workouts = (0..<5).map { i in
            AnalyticsTestHelpers.makePushDayWorkout(
                startedAt: Date().addingTimeInterval(Double(-i) * 86400)
            )
        }
        workoutRepo.seed(workouts)

        await vm.loadDashboardInsights()

        XCTAssertEqual(vm.insights.workoutCount, 5)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_loadDashboardInsights_completesLoadingCycle() async {
        let (vm, _, _, _) = Self.makeViewModel()
        XCTAssertFalse(vm.isInsightsLoading)

        await vm.loadDashboardInsights()

        XCTAssertFalse(vm.isInsightsLoading)
    }

    @MainActor
    func test_loadDashboardInsights_emptyRepo_returnsZeroWorkoutCount() async {
        let (vm, _, _, _) = Self.makeViewModel()

        await vm.loadDashboardInsights()

        XCTAssertEqual(vm.insights.workoutCount, 0)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_loadDashboardInsights_setsNextFeatureUnlock() async {
        let (vm, _, workoutRepo, _) = Self.makeViewModel()
        let workouts = (0..<3).map { i in
            AnalyticsTestHelpers.makeWorkout(
                name: "Workout \(i)",
                exercises: [AnalyticsTestHelpers.makeWorkoutExercise()],
                startedAt: Date().addingTimeInterval(Double(-i) * 86400),
                completedAt: Date().addingTimeInterval(Double(-i) * 86400 + 3600)
            )
        }
        workoutRepo.seed(workouts)

        await vm.loadDashboardInsights()

        XCTAssertNotNil(vm.nextFeatureUnlock)
        if let next = vm.nextFeatureUnlock {
            XCTAssertEqual(next.workoutsNeeded, 2,
                           "With 3 completed workouts, need 2 more to reach threshold 5")
        }
    }

    @MainActor
    func test_loadDashboardInsights_error_setsErrorMessage() async {
        let (vm, _, workoutRepo, _) = Self.makeViewModel()
        workoutRepo.shouldThrowOnFetchAll = true

        await vm.loadDashboardInsights()

        XCTAssertNotNil(vm.errorMessage, "Error should set errorMessage")
        XCTAssertEqual(vm.insights.workoutCount, 0, "Insights should reset to empty on error")
    }

    // MARK: - loadSimilarWorkouts

    @MainActor
    func test_loadSimilarWorkouts_completesWithoutCrash() async {
        let (vm, analyticsRepo, workoutRepo, _) = Self.makeViewModel()
        let targetWorkout = AnalyticsTestHelpers.makePushDayWorkout(startedAt: Date())
        let similarWorkout = AnalyticsTestHelpers.makePushDayWorkout(
            startedAt: Date().addingTimeInterval(-86400)
        )
        workoutRepo.seed([targetWorkout, similarWorkout])

        let vectorizer = WorkoutVectorizer()
        let vec1 = vectorizer.vectorize(targetWorkout, bodyWeightKg: UserPreferencesService.defaultBodyWeightKg)
        let vec2 = vectorizer.vectorize(similarWorkout, bodyWeightKg: UserPreferencesService.defaultBodyWeightKg)
        try? await analyticsRepo.storeVector(vec1)
        try? await analyticsRepo.storeVector(vec2)

        await vm.loadSimilarWorkouts(to: targetWorkout)

        XCTAssertFalse(vm.isSimilarWorkoutsLoading)
    }

    @MainActor
    func test_loadSimilarWorkouts_noVectors_returnsEmptyArray() async {
        let (vm, _, workoutRepo, _) = Self.makeViewModel()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        workoutRepo.seed([workout])

        await vm.loadSimilarWorkouts(to: workout)

        // With no stored vectors, the service returns empty results (no error thrown)
        XCTAssertTrue(vm.similarWorkouts.isEmpty)
        XCTAssertFalse(vm.isSimilarWorkoutsLoading)
    }

    // MARK: - loadQualityScore

    @MainActor
    func test_loadQualityScore_setsScore() async {
        let (vm, _, workoutRepo, _) = Self.makeViewModel()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        workoutRepo.seed([workout])

        await vm.loadQualityScore(for: workout)

        XCTAssertNotNil(vm.qualityScore)
        if let score = vm.qualityScore {
            XCTAssertEqual(score.workoutId, workout.id)
            XCTAssertGreaterThan(score.overallScore, 0)
            XCTAssertLessThanOrEqual(score.overallScore, 100)
        }
        XCTAssertFalse(vm.isQualityScoreLoading)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_loadQualityScore_completesLoadingCycle() async {
        let (vm, _, workoutRepo, _) = Self.makeViewModel()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        workoutRepo.seed([workout])

        await vm.loadQualityScore(for: workout)

        XCTAssertFalse(vm.isQualityScoreLoading)
    }

    @MainActor
    func test_loadQualityScore_error_setsErrorAndNilsScore() async {
        let (vm, _, workoutRepo, _) = Self.makeViewModel()
        let workout = AnalyticsTestHelpers.makePushDayWorkout()
        workoutRepo.shouldThrowOnFetchAll = true

        await vm.loadQualityScore(for: workout)

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.qualityScore)
    }

    // MARK: - Formatting Helpers

    @MainActor
    func test_formatSimilarity_convertsToPercentage() async {
        let (vm, _, _, _) = Self.makeViewModel()
        XCTAssertEqual(vm.formatSimilarity(0.92), "92%")
        XCTAssertEqual(vm.formatSimilarity(1.0), "100%")
        XCTAssertEqual(vm.formatSimilarity(0.0), "0%")
        XCTAssertEqual(vm.formatSimilarity(0.856), "86%")
    }

    @MainActor
    func test_formatVolume_formatsWithNoDecimals() async {
        let (vm, _, _, _) = Self.makeViewModel()
        let result = vm.formatVolume(12500.0)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(vm.formatVolume(0.0), "0")
    }

    @MainActor
    func test_formatRatio_formatsWithOneDecimal() async {
        let (vm, _, _, _) = Self.makeViewModel()
        XCTAssertEqual(vm.formatRatio(1.5), "1.5:1")
        XCTAssertEqual(vm.formatRatio(2.0), "2.0:1")
        XCTAssertEqual(vm.formatRatio(1.123), "1.1:1")
    }

    @MainActor
    func test_severityColor_returnsExpectedColors() async {
        let (vm, _, _, _) = Self.makeViewModel()
        XCTAssertEqual(vm.severityColor(.mild), "yellow")
        XCTAssertEqual(vm.severityColor(.moderate), "orange")
        XCTAssertEqual(vm.severityColor(.severe), "red")
    }

    // MARK: - Factory

    @MainActor
    private static func makeViewModel() -> (
        viewModel: WorkoutAnalyticsViewModel,
        analyticsRepo: MockAnalyticsRepository,
        workoutRepo: MockWorkoutRepository,
        exerciseRepo: MockExerciseRepository
    ) {
        let (vm, a, w, e, _) = makeViewModel(withRevision: false)
        return (vm, a, w, e)
    }

    @MainActor
    private static func makeViewModel(withRevision: Bool) -> (
        viewModel: WorkoutAnalyticsViewModel,
        analyticsRepo: MockAnalyticsRepository,
        workoutRepo: MockWorkoutRepository,
        exerciseRepo: MockExerciseRepository,
        revision: DataRevision?
    ) {
        let revision: DataRevision? = withRevision ? DataRevision() : nil
        let analyticsRepo = MockAnalyticsRepository()
        let workoutRepo = MockWorkoutRepository()
        let exerciseRepo = MockExerciseRepository()

        let analyticsService = WorkoutAnalyticsService(
            analyticsRepository: analyticsRepo,
            workoutRepository: workoutRepo,
            exerciseRepository: exerciseRepo,
            vectorizer: WorkoutVectorizer(),
            searchService: VectorSearchService(),
            plateauService: PlateauDetectionService(),
            muscleBalanceService: MuscleBalanceService(),
            recommendationService: ExerciseRecommendationService(),
            dataRevision: revision
        )
        let qualityScoreService = WorkoutQualityScoreService(
            workoutRepository: workoutRepo,
            muscleBalanceService: MuscleBalanceService(),
            healthKitService: NoOpHealthKitService(),
            userPreferencesService: UserPreferencesService()
        )
        let featureGate = AnalyticsFeatureGate(workoutRepository: workoutRepo)

        let viewModel = WorkoutAnalyticsViewModel(
            analyticsService: analyticsService,
            qualityScoreService: qualityScoreService,
            featureGate: featureGate,
            workoutRepository: workoutRepo,
            dataRevision: revision
        )

        return (viewModel, analyticsRepo, workoutRepo, exerciseRepo, revision)
    }

    // MARK: - Revision gating

    @MainActor
    func test_loadDashboardInsights_revisionGate() async {
        let (vm, _, workoutRepo, _, revision) = Self.makeViewModel(withRevision: true)
        workoutRepo.seed([AnalyticsTestHelpers.makePushDayWorkout(startedAt: Date().addingTimeInterval(-86400))])

        await vm.loadDashboardInsights()
        let first = vm.insights.generatedAt
        await vm.loadDashboardInsights()
        XCTAssertEqual(vm.insights.generatedAt, first, "same revision: no reload")

        // seed() appends — add one more workout.
        workoutRepo.seed([AnalyticsTestHelpers.makePushDayWorkout(startedAt: Date().addingTimeInterval(-2 * 86400))])
        revision?.bump()
        await vm.loadDashboardInsights()
        XCTAssertEqual(vm.insights.workoutCount, 2, "bump: reloaded with the new data")

        await vm.loadDashboardInsights(force: true)
        XCTAssertEqual(vm.insights.workoutCount, 2)
    }
}
