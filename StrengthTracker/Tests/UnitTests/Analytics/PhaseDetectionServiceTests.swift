import Testing
import Foundation
@testable import StrengthTrackerShared

@MainActor
@Suite("PhaseDetectionService")
struct PhaseDetectionServiceTests {

    private func makeService() -> PhaseDetectionService {
        PhaseDetectionService(searchService: VectorSearchService())
    }

    /// Phase prototypes mirroring the production values for fixture construction.
    /// Active dims: 0=vol, 1=wt, 2=reps, 3=sets, 4=div, 5=dur, 12=cmp, 13=rpe, 16=pr.
    private static let prototypes: [DetectedPhase: [Int: Double]] = [
        .deload:          [0: 0.20, 1: 0.20, 2: 0.30, 3: 0.20, 4: 0.30, 5: 0.40,
                           12: 0.30, 13: 0.45, 16: 0.05],
        .accumulation:    [0: 0.65, 1: 0.40, 2: 0.55, 3: 0.65, 4: 0.55, 5: 0.65,
                           12: 0.50, 13: 0.65, 16: 0.15],
        .intensification: [0: 0.45, 1: 0.65, 2: 0.30, 3: 0.45, 4: 0.40, 5: 0.55,
                           12: 0.65, 13: 0.75, 16: 0.25],
        .peaking:         [0: 0.25, 1: 0.80, 2: 0.15, 3: 0.30, 4: 0.25, 5: 0.45,
                           12: 0.80, 13: 0.85, 16: 0.45],
    ]

    private func prototypeDims(_ phase: DetectedPhase) -> [Double] {
        var v = Array(repeating: 0.0, count: 18)
        guard let proto = Self.prototypes[phase] else { return v }
        for (i, value) in proto { v[i] = value }
        return v
    }

    /// Make a workout vector at the start of the given past week, with the supplied 18-dim values.
    private func makeVector(weeksAgo: Int, dayOffset: Int = 1, dims: [Double]) -> WorkoutVector {
        let calendar = Calendar.mondayStart
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart)!
        let date = weekStart.addingTimeInterval(Double(dayOffset) * 86400)
        return WorkoutVector(
            id: UUID(),
            workoutId: UUID(),
            dimensions: AnalyticsCalculations.l2Normalize(dims),
            magnitude: nil,
            createdAt: date
        )
    }

    /// 4 mature weeks of vectors near a given prototype. Ensures the most recent week's
    /// classifier output drives currentPhase (smoothing keeps the latest as-is).
    private func makePhaseFixture(_ phase: DetectedPhase, weeks: Int = 4, perWeek: Int = 3) -> [WorkoutVector] {
        let dims = prototypeDims(phase)
        var vectors: [WorkoutVector] = []
        for w in 0..<weeks {
            for d in 0..<perWeek {
                vectors.append(makeVector(weeksAgo: w, dayOffset: d + 1, dims: dims))
            }
        }
        return vectors
    }

    @Test("Deload prototype classifies as .deload")
    func deloadPrototypeIsClassifiedAsDeload() {
        let service = makeService()
        let detection = service.detectPhases(vectors: makePhaseFixture(.deload))
        #expect(detection?.currentPhase == .deload)
    }

    @Test("Accumulation prototype classifies as .accumulation")
    func accumulationPrototypeIsClassifiedAsAccumulation() {
        let service = makeService()
        let detection = service.detectPhases(vectors: makePhaseFixture(.accumulation))
        #expect(detection?.currentPhase == .accumulation)
    }

    @Test("Intensification prototype classifies as .intensification")
    func intensificationPrototypeIsClassifiedAsIntensification() {
        let service = makeService()
        let detection = service.detectPhases(vectors: makePhaseFixture(.intensification))
        #expect(detection?.currentPhase == .intensification)
    }

    @Test("Peaking prototype classifies as .peaking")
    func peakingPrototypeIsClassifiedAsPeaking() {
        let service = makeService()
        let detection = service.detectPhases(vectors: makePhaseFixture(.peaking))
        #expect(detection?.currentPhase == .peaking)
    }

    @Test("Smoothing preserves a phase that is unambiguous across all weeks")
    func smoothingPreservesUnanimous() {
        let service = makeService()
        let detection = service.detectPhases(vectors: makePhaseFixture(.accumulation, weeks: 6))
        #expect(detection?.phaseHistory.count == 6)
        // All windows classify as accumulation → all smoothed entries should be accumulation.
        for window in detection?.phaseHistory ?? [] {
            #expect(window.phase == .accumulation, "Got \(window.phase) for an accumulation-only fixture")
        }
    }
}
