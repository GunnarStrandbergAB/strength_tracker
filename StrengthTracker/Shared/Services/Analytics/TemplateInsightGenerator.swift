import Foundation

/// Template-based insight text generator. Works on all devices.
/// Generates natural-language insights from computed analytics data using templates.
public final class TemplateInsightGenerator: InsightTextGenerating, @unchecked Sendable {

    public init() {}

    @MainActor
    public func generateHighlights(
        trainingLoad: TrainingLoad?,
        overloadTrends: [OverloadTrend],
        deloadRecommendation: DeloadRecommendation?,
        trainingDrift: TrainingDrift?,
        trainingPhase: TrainingPhaseDetection?,
        recoveryPatterns: [RecoveryPattern],
        optimalVolumes: [OptimalVolumeRange]
    ) async -> [AnalyticsHighlight] {
        var highlights: [AnalyticsHighlight] = []

        // Priority 1: Warnings
        if let deload = deloadRecommendation {
            highlights.append(AnalyticsHighlight(
                type: .warning,
                title: "Deload Recommended",
                detail: deload.suggestedAction
            ))
        }

        if let load = trainingLoad, load.loadZone == .danger {
            highlights.append(AnalyticsHighlight(
                type: .warning,
                title: "High Training Load",
                detail: String(format: "ACWR at %.2f — reduce volume to avoid overtraining", load.acwr)
            ))
        }

        let overVolume = optimalVolumes.filter { $0.volumeStatus == .overVolume }
        for vol in overVolume.prefix(2) {
            highlights.append(AnalyticsHighlight(
                type: .warning,
                title: "\(vol.muscleGroup.capitalized) Over Volume",
                detail: "\(vol.currentWeeklySets) sets/week exceeds MRV of \(vol.maximumWeeklySets)"
            ))
        }

        // Priority 2: Improvements
        let progressing = overloadTrends.filter { $0.trendStatus == .progressing }
        for trend in progressing.prefix(2) {
            highlights.append(AnalyticsHighlight(
                type: .improvement,
                title: "\(trend.exerciseName) Progressing",
                detail: String(format: "+%.1f kg/week", trend.slopePerWeek)
            ))
        }

        if let load = trainingLoad, load.loadZone == .optimal {
            highlights.append(AnalyticsHighlight(
                type: .improvement,
                title: "Optimal Training Load",
                detail: String(format: "ACWR at %.2f — sweet spot for progress", load.acwr)
            ))
        }

        // Priority 3: Milestones / Info
        if let phase = trainingPhase {
            highlights.append(AnalyticsHighlight(
                type: .milestone,
                title: "Training Phase: \(phaseDisplayName(phase.currentPhase))",
                detail: phaseDescription(phase.currentPhase)
            ))
        }

        if let drift = trainingDrift, drift.overallDriftScore > 0.15 {
            let topDrift = drift.driftingDimensions.first
            let driftDetail = topDrift.map { "\($0.featureName.replacingOccurrences(of: "_", with: " ")) shifted \($0.delta > 0 ? "up" : "down")" }
                ?? "Training pattern has shifted"
            highlights.append(AnalyticsHighlight(
                type: .milestone,
                title: "Training Drift Detected",
                detail: driftDetail
            ))
        }

        let fatigued = recoveryPatterns.filter { $0.recoveryStatus == .fatigued }
        if !fatigued.isEmpty {
            let names = fatigued.prefix(3).map { $0.muscleGroup.capitalized }.joined(separator: ", ")
            highlights.append(AnalyticsHighlight(
                type: .warning,
                title: "Muscles Still Fatigued",
                detail: "\(names) — consider extra rest before training again"
            ))
        }

        return Array(highlights.prefix(5))
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
        var highlights: [AnalyticsHighlight] = []

        // Priority 1 (Warning): Plateau warnings — top 2 by weeks stalled (need 3+ weeks)
        if workoutCount >= 10 {
            let stalledExercises = plateaus
                .filter { $0.consecutiveWeeksStalled >= 3 }
                .sorted { $0.consecutiveWeeksStalled > $1.consecutiveWeeksStalled }
            for plateau in stalledExercises.prefix(2) {
                let name = plateau.exerciseName ?? "Exercise"
                highlights.append(AnalyticsHighlight(
                    type: .warning,
                    title: "\(name) Stalled",
                    detail: "\(plateau.consecutiveWeeksStalled) weeks no progress"
                ))
            }
        }

        // Priority 2 (Warning): Muscle imbalances — moderate+ severity
        if let balance = muscleBalance {
            let significant = balance.imbalances.filter { $0.severity != .mild }
            for imbalance in significant.prefix(1) {
                let ratioStr = String(format: "%.1f", imbalance.ratio)
                highlights.append(AnalyticsHighlight(
                    type: .warning,
                    title: "\(imbalance.primaryGroup.capitalized)/\(imbalance.comparisonGroup.capitalized) Imbalance",
                    detail: "\(ratioStr)x ratio"
                ))
            }
        }

        // Priority 3 (Improvement): Top recommendation by confidence
        if let top = recommendations.sorted(by: { $0.confidence > $1.confidence }).first {
            let reasonText: String
            switch top.reason {
            case .fillsMuscleGap:
                let muscle = top.targetMuscleGroup ?? "a gap"
                reasonText = "fills \(muscle) gap"
            case .plateauBreaker:
                reasonText = "plateau breaker"
            case .similarToFavorites:
                reasonText = "matches your favorites"
            case .recoveryAppropriate:
                reasonText = "good for recovery"
            }
            highlights.append(AnalyticsHighlight(
                type: .improvement,
                title: "Try \(top.exerciseName)",
                detail: reasonText.prefix(1).uppercased() + reasonText.dropFirst()
            ))
        }

        return Array(highlights.prefix(3))
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
