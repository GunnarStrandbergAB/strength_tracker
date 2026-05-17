import Testing
import Foundation
@testable import StrengthTrackerShared

@MainActor
@Suite("BlockComparisonService")
struct BlockComparisonServiceTests {

    private func makeService() -> BlockComparisonService {
        BlockComparisonService(searchService: VectorSearchService())
    }

    /// Make a vector with explicit dim values (L2-normalised before storage), placed at a date.
    private func makeVector(weeksAgo: Int, values: [Double]) -> WorkoutVector {
        let calendar = Calendar.mondayStart
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart)!
        let date = weekStart.addingTimeInterval(60 * 60 * 24) // Tuesday-ish

        return WorkoutVector(
            id: UUID(),
            workoutId: UUID(),
            dimensions: AnalyticsCalculations.l2Normalize(values),
            magnitude: nil,
            createdAt: date
        )
    }

    /// 18-dim vector: write specific values at indices, fill the rest with `fill`.
    private func makeDims(_ assignments: [Int: Double], fill: Double = 0.0) -> [Double] {
        var v = Array(repeating: fill, count: 18)
        for (i, value) in assignments { v[i] = value }
        return v
    }

    @Test("Drift confined to time_of_day never surfaces in dimensionDeltas")
    func timeOfDayDriftIsExcluded() {
        let service = makeService()
        // Previous block (weeks 5-8): time_of_day low.
        let previous = (5...8).flatMap { w in
            (0..<3).map { _ in makeVector(weeksAgo: w, values: makeDims([0: 0.5, 17: 0.10])) }
        }
        // Current block (weeks 0-3): time_of_day high (big shift), volume same.
        let current = (0...3).flatMap { w in
            (0..<3).map { _ in makeVector(weeksAgo: w, values: makeDims([0: 0.5, 17: 0.90])) }
        }
        let comparison = service.compareBlocks(vectors: previous + current)
        let deltas = comparison?.dimensionDeltas ?? []
        for d in deltas {
            #expect(d.featureName != "time_of_day",
                    "time_of_day must be filtered out (got delta \(d.delta))")
        }
    }

    @Test("Sub-threshold drift produces no entry")
    func smallDriftBelowThresholdProducesNoEntry() {
        let service = makeService()
        let previous = (5...8).flatMap { w in
            (0..<3).map { _ in makeVector(weeksAgo: w, values: makeDims([0: 0.50, 1: 0.50])) }
        }
        let current = (0...3).flatMap { w in
            (0..<3).map { _ in makeVector(weeksAgo: w, values: makeDims([0: 0.50, 1: 0.52])) }
        }
        let comparison = service.compareBlocks(vectors: previous + current)
        let deltas = comparison?.dimensionDeltas ?? []
        for d in deltas {
            #expect(abs(d.delta) > BlockComparisonService.dimensionDeltaThreshold,
                    "Reported delta \(d.delta) for \(d.featureName) must exceed the threshold")
        }
    }

    @Test("Summary text uses human-readable phrasing, not raw feature names")
    func summaryIsHumanReadable() {
        let service = makeService()
        let previous = (5...8).flatMap { w in
            (0..<3).map { _ in makeVector(weeksAgo: w, values: makeDims([0: 0.5, 13: 0.30])) }
        }
        let current = (0...3).flatMap { w in
            (0..<3).map { _ in makeVector(weeksAgo: w, values: makeDims([0: 0.5, 13: 0.85])) }
        }
        let comparison = service.compareBlocks(vectors: previous + current)
        let summary = comparison?.summaryText ?? ""
        #expect(!summary.contains("avg rpe"),
                "Raw feature name must not appear: \(summary)")
        #expect(!summary.contains("time of day"),
                "Time-of-day must not appear: \(summary)")
    }
}
