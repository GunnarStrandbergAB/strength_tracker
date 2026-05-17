import Testing
import Foundation
@testable import StrengthTrackerShared

@MainActor
@Suite("AnomalyDetectionService")
struct AnomalyDetectionServiceTests {

    // MARK: - Helpers

    private func makeService() -> AnomalyDetectionService {
        AnomalyDetectionService(searchService: VectorSearchService())
    }

    /// Build a vector at a given day offset with explicit (non-normalised) dim values.
    /// Values are L2-normalised before storage so the vectors match the production shape.
    private func makeVector(daysAgo: Int, dims: [Double]) -> WorkoutVector {
        let normalised = AnalyticsCalculations.l2Normalize(dims)
        return WorkoutVector(
            id: UUID(),
            workoutId: UUID(),
            dimensions: normalised,
            magnitude: nil,
            createdAt: Date().addingTimeInterval(Double(-daysAgo) * 86400)
        )
    }

    /// A "normal" 18-dim vector: high activation on volume/sets/duration.
    /// Orthogonal axes are chosen to make outliers easy to construct with maximum cosine distance.
    private static let normalDims: [Double] = [
        0.90, 0.00, 0.00, 0.90, 0.00, 0.90,    // 0-5
        0.00, 0.00, 0.00, 0.00, 0.00, 0.00,    // 6-11
        0.00, 0.00, 0.00, 0.00, 0.00, 0.00,    // 12-17
    ]

    /// Make N "normal" vectors spread across the last `spanDays` days.
    private func makeNormalVectors(count: Int, spanDays: Int = 60) -> [WorkoutVector] {
        let step = max(1, spanDays / count)
        return (0..<count).map { i in makeVector(daysAgo: i * step, dims: Self.normalDims) }
    }

    // MARK: - Tests

    @Test("Below 20-vector minimum returns empty")
    func underMinimumSample() {
        let service = makeService()
        let nineteen = makeNormalVectors(count: 19)
        #expect(service.detectAnomalies(vectors: nineteen).isEmpty)
    }

    @Test("With 20 identical vectors no anomaly is flagged")
    func identicalVectorsProduceNoAnomalies() {
        let service = makeService()
        let twenty = makeNormalVectors(count: 20)
        #expect(service.detectAnomalies(vectors: twenty).isEmpty)
    }

    @Test("A near-orthogonal outlier is flagged")
    func orthogonalOutlierIsFlagged() {
        let service = makeService()
        var vectors = makeNormalVectors(count: 20)
        // Outlier on axes orthogonal to the normal (low volume/sets/duration, high weight/diversity/RPE).
        let outlierDims: [Double] = [
            0.00, 0.90, 0.90, 0.00, 0.90, 0.00,   // 0-5
            0.00, 0.00, 0.00, 0.00, 0.00, 0.00,   // 6-11
            0.00, 0.90, 0.00, 0.00, 0.00, 0.00,   // 12-17
        ]
        vectors.append(makeVector(daysAgo: 0, dims: outlierDims))

        let anomalies = service.detectAnomalies(vectors: vectors)
        #expect(!anomalies.isEmpty, "Near-orthogonal workout should be flagged")
        for a in anomalies {
            #expect(a.anomalyScore >= AnomalyDetectionService.surfaceScoreFloor)
        }
    }

    @Test("Reasons never contain time_of_day, volume_vs_prev_*, or muscle ratios")
    func noiseDimsExcludedFromReasons() {
        let service = makeService()
        var vectors = makeNormalVectors(count: 20)
        // Outlier on orthogonal axes including all the noise/redundant dims.
        let outlierDims: [Double] = [
            0.00, 0.90, 0.90, 0.00, 0.00, 0.00,   // 0-5 (avg_weight, avg_reps — both allow-listed)
            0.00, 0.90, 0.00, 0.00, 0.00, 0.00,   // 6-11 (back_ratio — suppressed)
            0.00, 0.90, 0.90, 0.90, 0.00, 0.90,   // 12-17 (compound/rpe allow-listed; vol_7d/30d/time suppressed)
        ]
        vectors.append(makeVector(daysAgo: 0, dims: outlierDims))

        let anomalies = service.detectAnomalies(vectors: vectors)
        let suppressed: Set<String> = [
            "volume_vs_prev_7d", "volume_vs_prev_30d", "time_of_day",
            "chest_ratio", "back_ratio", "legs_ratio", "shoulders_ratio", "arms_ratio", "core_ratio"
        ]
        #expect(!anomalies.isEmpty, "Fixture should produce at least one anomaly to test reason filtering against")
        for a in anomalies {
            for d in a.deviatingDimensions {
                #expect(!suppressed.contains(d.featureName),
                        "Suppressed dim '\(d.featureName)' must not appear in anomaly reasons")
            }
        }
    }

    @Test("Surface floor suppresses borderline scores")
    func surfaceFloorSuppressesBorderline() {
        let service = makeService()
        var vectors = makeNormalVectors(count: 20)
        // Tiny perturbation: only slightly off — score below 0.5 floor, even if it crosses mean+2σ.
        var outlierDims = Self.normalDims
        outlierDims[0] = 0.55  // 0.05 nudge to total_volume_norm
        vectors.append(makeVector(daysAgo: 0, dims: outlierDims))

        let anomalies = service.detectAnomalies(vectors: vectors)
        // Either no anomaly at all, or one that comfortably clears 0.5.
        for a in anomalies {
            #expect(a.anomalyScore >= AnomalyDetectionService.surfaceScoreFloor)
        }
    }
}
