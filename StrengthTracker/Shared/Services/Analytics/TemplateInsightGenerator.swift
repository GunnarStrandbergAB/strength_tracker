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
        let activeDeload = verdict?.isActiveDeload ?? false
        // Without a verdict (older callers/tests) fall back to the raw recommendation.
        let kind: TrainingVerdict.Kind = verdict?.kind ?? (deloadRecommendation == nil ? .progress : .deload)

        // Priority 0: the verdict's own card
        if activeDeload {
            highlights.append(AnalyticsHighlight(
                type: .improvement,
                title: "Deload In Progress",
                detail: "Intentional recovery week: reduced volume and intensity as planned"
            ))
        } else {
            switch kind {
            case .deload:
                highlights.append(AnalyticsHighlight(
                    type: .warning,
                    title: "Deload Recommended",
                    detail: verdict?.action ?? deloadRecommendation?.suggestedAction ?? "Take a lighter week"
                ))
            case .hold:
                highlights.append(AnalyticsHighlight(
                    type: .milestone,
                    title: "Hold Steady",
                    detail: verdict?.action ?? "Keep loads where they are this week"
                ))
            case .progress:
                break
            }
        }

        // Priority 1: Warnings (never during an active deload)
        if !activeDeload {
            // The ACWR story is already in a deload/hold card; only a progress
            // verdict with a danger zone (advisor disagreement) shows it separately.
            if kind == .progress, let load = trainingLoad, load.loadZone == .danger {
                highlights.append(AnalyticsHighlight(
                    type: .warning,
                    title: "High Training Load",
                    detail: "ACWR \(AnalyticsFormatting.acwr(load.acwr)), far above your baseline"
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
        }

        // Priority 2: Improvements
        let progressing = overloadTrends.filter { $0.trendStatus == .progressing }
        for trend in progressing.prefix(2) {
            highlights.append(AnalyticsHighlight(
                type: .improvement,
                title: "\(trend.exerciseName) Progressing",
                detail: "\(AnalyticsFormatting.slope(kgPerWeek: trend.slopePerWeek, unit: weightUnit())) over recent weeks"
            ))
        }

        if kind == .progress, !activeDeload, let load = trainingLoad, load.loadZone == .optimal {
            highlights.append(AnalyticsHighlight(
                type: .improvement,
                title: "Optimal Training Load",
                detail: "ACWR \(AnalyticsFormatting.acwr(load.acwr)), in a sustainable range"
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

        if !activeDeload, let drift = trainingDrift, drift.overallDriftScore > 0.15 {
            let topDrift = drift.driftingDimensions.first
            let driftDetail = topDrift.map { "\($0.featureName.replacingOccurrences(of: "_", with: " ")) shifted \($0.delta > 0 ? "up" : "down")" }
                ?? "Training pattern has shifted"
            highlights.append(AnalyticsHighlight(
                type: .milestone,
                title: "Training Drift Detected",
                detail: driftDetail
            ))
        }

        // Systemic fatigue only: a group trained yesterday is trivially "fatigued".
        if !activeDeload {
            let fatigued = recoveryPatterns.filter { $0.recoveryStatus == .fatigued }
            if fatigued.count >= TrainingAdvisor.systemicFatigueGroups, !fatigued.contains(where: \.isJustTrained) {
                let names = fatigued.prefix(3).map { $0.muscleGroup.capitalized }.joined(separator: ", ")
                highlights.append(AnalyticsHighlight(
                    type: .warning,
                    title: "Recovery Lagging",
                    detail: "\(names) still fatigued"
                ))
            }
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
                highlights.append(AnalyticsHighlight(
                    type: .warning,
                    title: "\(imbalance.primaryGroup.capitalized)/\(imbalance.comparisonGroup.capitalized) Imbalance",
                    detail: "\(AnalyticsFormatting.ratio(imbalance.ratio)) ratio"
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
