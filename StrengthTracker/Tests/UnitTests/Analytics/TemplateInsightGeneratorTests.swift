import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("TemplateInsightGenerator highlights")
@MainActor
struct TemplateInsightGeneratorTests {

    private let generator = TemplateInsightGenerator()

    private func load(acwr: Double) -> TrainingLoad {
        TrainingLoad(acuteLoad: acwr * 100, chronicLoad: 100, acwr: acwr, loadZone: LoadZone.from(acwr: acwr))
    }

    private func verdict(_ kind: TrainingVerdict.Kind, active: Bool = false) -> TrainingVerdict {
        TrainingVerdict(kind: kind, urgency: kind == .deload ? 0.6 : 0, reasons: ["r"], signals: [],
                        action: "Action for \(kind.rawValue)", since: Date(), computedAt: Date(), isActiveDeload: active)
    }

    private func recommendation() -> DeloadRecommendation {
        DeloadRecommendation(urgencyScore: 0.6, triggers: [.highACWR, .effortCreep], weeksSinceLastDeload: 9, suggestedAction: "Lighter week")
    }

    private func pattern(_ group: String, lastTrained: Date) -> RecoveryPattern {
        RecoveryPattern(muscleGroup: group, averageRecoveryHours: 48, optimalRestDays: 2,
                        lastTrainedDate: lastTrained, readyToTrainDate: nil, recoveryStatus: .fatigued)
    }

    private func highlights(
        load: TrainingLoad?, rec: DeloadRecommendation? = nil, verdict: TrainingVerdict?,
        recovery: [RecoveryPattern] = [], volumes: [OptimalVolumeRange] = []
    ) async -> [AnalyticsHighlight] {
        await generator.generateHighlights(
            trainingLoad: load, overloadTrends: [], deloadRecommendation: rec, trainingDrift: nil,
            trainingPhase: nil, recoveryPatterns: recovery, optimalVolumes: volumes, verdict: verdict
        )
    }

    @Test("Deload verdict: 'Deload Recommended' never sits next to 'Optimal Training Load'")
    func deloadNeverWithOptimal() async {
        let hs = await highlights(load: load(acwr: 1.0), rec: recommendation(), verdict: verdict(.deload))
        let titles = hs.map(\.title)
        #expect(titles.first == "Deload Recommended")
        #expect(!titles.contains("Optimal Training Load"))
        #expect(!titles.contains("High Training Load"))
        #expect(hs.first?.detail == "Action for deload")
    }

    @Test("Progress verdict never produces 'Deload Recommended', even with a raw recommendation")
    func progressNeverDeload() async {
        let hs = await highlights(load: load(acwr: 1.0), rec: recommendation(), verdict: verdict(.progress))
        let titles = hs.map(\.title)
        #expect(!titles.contains("Deload Recommended"))
        #expect(titles.contains("Training load"))
    }

    @Test("Hold verdict shows 'Hold Steady' and no load-zone praise")
    func holdSteady() async {
        let hs = await highlights(load: load(acwr: 1.0), verdict: verdict(.hold))
        let titles = hs.map(\.title)
        #expect(titles.first == "Hold Steady")
        #expect(!titles.contains("Optimal Training Load"))
        #expect(!titles.contains("Deload Recommended"))
    }

    @Test("Active deload: 'Deload In Progress' first and every warning suppressed")
    func activeDeloadSuppressesWarnings() async {
        let old = Date().addingTimeInterval(-5 * 86_400)
        let volumes = [OptimalVolumeRange(muscleGroup: "chest", minimumWeeklySets: 10, maximumWeeklySets: 20,
                                          currentWeeklySets: 30, volumeStatus: .overVolume)]
        let hs = await highlights(
            load: load(acwr: 1.7), rec: recommendation(), verdict: verdict(.hold, active: true),
            recovery: [pattern("chest", lastTrained: old), pattern("back", lastTrained: old), pattern("quads", lastTrained: old)],
            volumes: volumes
        )
        #expect(hs.first?.title == "Deload In Progress")
        #expect(!hs.contains { $0.type == .warning })
    }

    @Test("Recovery observations never override the shared advisor verdict")
    func fatigueIsSystemicOnly() async {
        let old = Date().addingTimeInterval(-5 * 86_400)
        let justNow = Date().addingTimeInterval(-3600)
        let two = await highlights(load: nil, verdict: verdict(.progress),
                                   recovery: [pattern("chest", lastTrained: old), pattern("back", lastTrained: old)])
        #expect(!two.map(\.title).contains("Recovery Lagging"))

        let three = await highlights(load: nil, verdict: verdict(.progress),
                                     recovery: [pattern("chest", lastTrained: old), pattern("back", lastTrained: old), pattern("quads", lastTrained: old)])
        #expect(three.first?.title == "Clear to Progress")

        let mixed = await highlights(load: nil, verdict: verdict(.progress),
                                     recovery: [pattern("chest", lastTrained: justNow), pattern("back", lastTrained: old), pattern("quads", lastTrained: old)])
        #expect(!mixed.map(\.title).contains("Recovery Lagging"))
    }

    @Test("Without a verdict only descriptive observations are published")
    func noVerdictFallback() async {
        let hs = await highlights(load: load(acwr: 1.0), rec: recommendation(), verdict: nil)
        let titles = hs.map(\.title)
        #expect(titles == ["Training load"])
        #expect(!titles.contains("Optimal Training Load"))
    }
}
