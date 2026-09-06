import Foundation

/// Template-based insight text generator. Works on all devices.
/// Generates natural-language insights from computed analytics data using templates.
public final class TemplateInsightGenerator: InsightTextGenerating, @unchecked Sendable {

    /// Display unit for slope strings (defaults to kg for tests).
    private let weightUnit: @MainActor () -> WeightUnit

    public init(weightUnit: @escaping @MainActor () -> WeightUnit = { .kg }) {
        self.weightUnit = weightUnit
    }

    /// Highlight rules, in priority order. The verdict decides the load story so
    /// "Deload Recommended" and "Optimal Training Load" can never share a list:
    /// - active deload → "Deload In Progress" first, every warning suppressed
    /// - deload → "Deload Recommended" (verdict action), no load-zone praise
    /// - hold → "Hold Steady", no load-zone praise, no deload warning
    /// - progress → never a deload warning; load-zone praise allowed
    @MainActor
    public func generateHighlights(
        trainingLoad: TrainingLoad?,
        overloadTrends: [OverloadTrend],
        deloadRecommendation: DeloadRecommendation?,
        trainingDrift: TrainingDrift?,
        trainingPhase: TrainingPhaseDetection?,
        recoveryPatterns: [RecoveryPattern],
        optimalVolumes: [OptimalVolumeRange],
        verdict: TrainingVerdict?
    ) async -> [AnalyticsHighlight] {
        var highlights: [AnalyticsHighlight] = []
        if let verdict, verdict.kind != .progress || verdict.isActiveDeload {
            highlights.append(AnalyticsHighlight(type: verdict.kind == .deload ? .warning : .milestone,
                title: verdict.headline, detail: verdict.action, topic: "verdict", computedAt: verdict.computedAt, isAction: true))
        }
        // Observations must never turn a hold/deload action into encouragement to push.
        if verdict?.kind != .hold && verdict?.kind != .deload {
            for trend in overloadTrends.filter({ $0.trendStatus == .progressing }).prefix(2) {
                highlights.append(AnalyticsHighlight(type: .improvement, title: "\(trend.exerciseName) Progressing",
                    detail: "\(AnalyticsFormatting.slope(kgPerWeek: trend.slopePerWeek, unit: weightUnit())) · recent 12-week estimate",
                    topic: "progress-\(trend.exerciseId.uuidString)"))
            }
        }
        if let load = trainingLoad, highlights.count < 3 {
            highlights.append(AnalyticsHighlight(type: .milestone, title: "Training load",
                detail: "\(AnalyticsFormatting.acwr(load.acwr)) × baseline · smoothed daily load", topic: "load"))
        }
        if highlights.isEmpty, let verdict {
            highlights.append(AnalyticsHighlight(type: .milestone, title: verdict.headline,
                detail: verdict.action, topic: "verdict", computedAt: verdict.computedAt, isAction: true))
        }
        return highlights
    }

    @MainActor
    public func generateBlockSummary(dimensionDeltas: [DimensionDrift]) async -> String {
        if dimensionDeltas.isEmpty {
            return "Training has been consistent between blocks."
        }

        let changes = dimensionDeltas.prefix(3).map { drift in
            let direction = drift.delta > 0 ? "increased" : "decreased"
            let name = drift.featureName.replacingOccurrences(of: "_", with: " ")
            return "\(name) \(direction)"
        }

        return "Key changes: \(changes.joined(separator: ", "))."
    }

    @MainActor
    public func generateDriftExplanation(drift: TrainingDrift) async -> String {
        if drift.driftingDimensions.isEmpty {
            return "Training is consistent with your established baseline."
        }

        let top = drift.driftingDimensions.prefix(2).map { d in
            let name = d.featureName.replacingOccurrences(of: "_", with: " ")
            let direction = d.delta > 0 ? "higher" : "lower"
            return "\(name) is \(direction) than usual"
        }

        let pct = String(format: "%.0f%%", drift.overallDriftScore * 100)
        return "Your recent training is \(pct) different from baseline. \(top.joined(separator: " and "))."
    }

    @MainActor
    public func generateEarlyHighlights(
        plateaus: [PlateauAnalysis],
        muscleBalance: MuscleBalance?,
        recommendations: [ExerciseRecommendation],
        workoutCount: Int
    ) async -> [AnalyticsHighlight] {
        // Legacy plateau/recommendation heuristics no longer publish independent advice.
        return []
    }

    @MainActor
    public func enhancePostWorkoutBullets(_ bullets: [CoachingInsight]) async -> [CoachingInsight] {
        bullets // pass-through: template generator returns bullets unchanged
    }

    // MARK: - Helpers

    private func phaseDisplayName(_ phase: DetectedPhase) -> String {
        switch phase {
        case .accumulation: return "Accumulation"
        case .intensification: return "Intensification"
        case .peaking: return "Peaking"
        case .deload: return "Deload"
        case .mixed: return "General"
        }
    }

    private func phaseDescription(_ phase: DetectedPhase) -> String {
        switch phase {
        case .accumulation: return "High volume phase — building work capacity and muscle"
        case .intensification: return "Moderate volume, heavier weights — building strength"
        case .peaking: return "Low volume, near-max weights — expressing strength"
        case .deload: return "Recovery phase — reduced training to dissipate fatigue"
        case .mixed: return "Varied training pattern — no single phase dominates"
        }
    }
}
