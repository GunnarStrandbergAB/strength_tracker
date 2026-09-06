import XCTest
import SwiftUI
@testable import StrengthTracker
@testable import StrengthTrackerShared

/// Production cards rendered at compact and accessibility sizes for visual review.
@MainActor
final class AnalyticsViewRenderingTests: XCTestCase {
    func testAnalyticsCardsAtPhoneAndAccessibilitySizes() async throws {
        let repo = MockWorkoutRepository()
        let quality = WorkoutQualityScoreService(workoutRepository: repo, muscleBalanceService: MuscleBalanceService(), healthKitService: MockHealthKitService(), userPreferencesService: UserPreferencesService())
        let service = WorkoutAnalyticsService(analyticsRepository: MockAnalyticsRepository(), workoutRepository: repo, exerciseRepository: MockExerciseRepository(), vectorizer: WorkoutVectorizer(), searchService: VectorSearchService(), plateauService: PlateauDetectionService(), muscleBalanceService: MuscleBalanceService(), recommendationService: ExerciseRecommendationService())
        let model = WorkoutAnalyticsViewModel(analyticsService: service, qualityScoreService: quality, featureGate: AnalyticsFeatureGate(workoutRepository: repo))
        model.insights = WorkoutInsights(generatedAt: Date(), workoutCount: 115, plateaus: [], muscleBalance: nil, recommendations: [], recoveryPatterns: [], optimalVolumes: [], trainingLoad: TrainingLoad(acuteLoad: 27, chronicLoad: 35, acwr: 0.77, loadZone: .optimal))
        model.aggregateQuality = AggregateQualityScore(ewmaOverall: 73.5, ewmaVolume: 73, ewmaIntensity: 76, ewmaBalance: 56, ewmaConsistency: 89, trendVsPrior: -6, percentileRank: 0.5, workoutsIncluded: 110, computedAt: Date())
        for (name, width, typeSize) in [("compact", 375.0, DynamicTypeSize.large), ("accessibility", 430.0, DynamicTypeSize.accessibility2)] {
            let content = VStack(spacing: 14) {
                AnalyticsLoadCard(viewModel: model)
                AnalyticsQualityCard(viewModel: model)
                AnalyticsTrendRow(trend: OverloadTrend(exerciseId: UUID(), exerciseName: "Weighted hanging knee raise with a long exercise name", weeklyE1RMs: [], slopePerWeek: 0.3, trendStatus: .progressing, overloadIndex: 1), viewModel: model)
                AdvancedInsightsCardView(viewModel: model)
            }.padding(18).background(STColors.background).foregroundStyle(STColors.textPrimary)
                .environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, .dark)
            let host = UIHostingController(rootView: content)
            let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
            XCTAssertGreaterThan(size.height, 500)
            XCTAssertLessThanOrEqual(size.width, width + 1)
            let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: width, height: size.height)))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await Task.yield()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "analytics-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertNotNil(image.pngData())
            window.isHidden = true
        }
    }
}
