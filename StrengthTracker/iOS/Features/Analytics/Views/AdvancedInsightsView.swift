#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Full detail view for advanced analytics (50+ workouts).
/// Sections: Highlights, Training Load, Phase, Volume, Recovery, Overload, Drift, Deload, Anomalies.
struct AdvancedInsightsView: View {
    let viewModel: WorkoutAnalyticsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !viewModel.insights.highlights.isEmpty {
                    highlightsSection
                }
                if viewModel.insights.trainingLoad != nil {
                    trainingLoadSection
                }
                if viewModel.insights.trainingPhase != nil {
                    phaseSection
                }
                if !viewModel.insights.optimalVolumes.isEmpty {
                    volumeLandmarkSection
                }
                if !viewModel.insights.recoveryPatterns.isEmpty {
                    recoverySection
                }
                if !viewModel.insights.overloadTrends.isEmpty {
                    overloadSection
                }
                if let drift = viewModel.insights.trainingDrift {
                    driftSection(drift)
                }
                if let deload = viewModel.insights.deloadRecommendation {
                    deloadSection(deload)
                }
                if let comparison = viewModel.insights.blockComparison {
                    blockComparisonSection(comparison)
                }
                if !viewModel.insights.anomalies.isEmpty {
                    anomaliesSection
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(STColors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Advanced Insights")
        .navigationBarTitleDisplayMode(.inline)
        .stNavigationBarStyle()
    }

    // MARK: - Smart Highlights

    @ViewBuilder
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Smart Highlights")

            ForEach(viewModel.insights.highlights) { highlight in
                HStack(spacing: 10) {
                    Image(systemName: highlightIcon(highlight.type))
                        .font(.system(size: 14))
                        .foregroundStyle(highlightColor(highlight.type))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(highlight.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)
                        Text(highlight.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(STColors.textSecondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Training Load

    @ViewBuilder
    private var trainingLoadSection: some View {
        if let load = viewModel.insights.trainingLoad {
            let isDeload = viewModel.insights.highlights.contains { $0.title == "Deload In Progress" }
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Training Load")

                Text("Acute:Chronic Workload Ratio — recent effort vs. your baseline")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)

                HStack(spacing: 20) {
                    // ACWR gauge
                    ZStack {
                        Circle()
                            .stroke(STColors.background, lineWidth: 6)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: min(load.acwr / 2.0, 1.0))
                            .stroke(zoneColor(load.loadZone), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text(viewModel.formatACWR(load.acwr))
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(STColors.textPrimary)
                            Text("ACWR")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(STColors.textTertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        loadRow("Recent (7d)", value: String(format: "%.0f", load.acuteLoad))
                        loadRow("Baseline (28d)", value: String(format: "%.0f", load.chronicLoad))
                    }
                }

                Text(zoneExplanation(load.loadZone, acwr: load.acwr, isDeload: isDeload))
                    .font(.system(size: 11))
                    .foregroundStyle(zoneColor(load.loadZone))
                    .padding(.top, 4)
            }
            .padding(STSpacing.cardPadding)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        }
    }

    // MARK: - Training Phase

    @ViewBuilder
    private var phaseSection: some View {
        if let phase = viewModel.insights.trainingPhase {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Training Phase")

                HStack(spacing: 10) {
                    Image(systemName: phaseIcon(phase.currentPhase))
                        .font(.system(size: 18))
                        .foregroundStyle(STColors.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentPhaseDisplayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)
                        Text(phaseDescription(phase.currentPhase))
                            .font(.system(size: 11))
                            .foregroundStyle(STColors.textSecondary)
                    }
                }

                // Phase history timeline
                if phase.phaseHistory.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(phase.phaseHistory.enumerated()), id: \.offset) { _, window in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(phaseColor(window.phase))
                                    .frame(width: 24, height: 8)
                            }
                        }
                    }
                }
            }
            .padding(STSpacing.cardPadding)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        }
    }

    // MARK: - Volume Landmarks

    @ViewBuilder
    private var volumeLandmarkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Volume Landmarks")

            ForEach(viewModel.insights.optimalVolumes) { vol in
                HStack(spacing: 8) {
                    Circle()
                        .fill(volumeStatusColor(vol.volumeStatus))
                        .frame(width: 8, height: 8)

                    Text(vol.muscleGroup.capitalized)
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                        .frame(width: 80, alignment: .leading)

                    Text("\(vol.currentWeeklySets)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(STColors.textPrimary)

                    Text("/ \(vol.minimumWeeklySets)-\(vol.maximumWeeklySets)")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)

                    Spacer()

                    Text(volumeStatusLabel(vol.volumeStatus))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(volumeStatusColor(vol.volumeStatus))
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Recovery Status

    @ViewBuilder
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recovery Status")

            ForEach(viewModel.insights.recoveryPatterns) { pattern in
                HStack(spacing: 8) {
                    Circle()
                        .fill(recoveryColor(pattern.recoveryStatus))
                        .frame(width: 8, height: 8)

                    Text(pattern.muscleGroup.capitalized)
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                        .frame(width: 80, alignment: .leading)

                    Spacer()

                    Text(recoveryLabel(pattern.recoveryStatus))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(recoveryColor(pattern.recoveryStatus))
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Progressive Overload

    @ViewBuilder
    private var overloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Progressive Overload")

            ForEach(viewModel.insights.overloadTrends) { trend in
                HStack(spacing: 10) {
                    Image(systemName: trendIcon(trend.trendStatus))
                        .font(.system(size: 12))
                        .foregroundStyle(trendColor(trend.trendStatus))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(trend.exerciseName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)
                        Text(viewModel.formatSlope(trend.slopePerWeek))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(STColors.textSecondary)
                    }

                    Spacer()

                    Text(trendLabel(trend.trendStatus))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(trendColor(trend.trendStatus))
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Training Drift

    @ViewBuilder
    private func driftSection(_ drift: TrainingDrift) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Training Drift")

            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)

                Text(String(format: "%.0f%% drift from baseline", drift.overallDriftScore * 100))
                    .font(.system(size: 13))
                    .foregroundStyle(STColors.textPrimary)
            }

            ForEach(Array(drift.driftingDimensions.enumerated()), id: \.offset) { _, dim in
                HStack(spacing: 8) {
                    Text(dim.featureName.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)

                    Spacer()

                    Text(String(format: "%+.2f", dim.delta))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(dim.delta > 0 ? STColors.success : STColors.danger)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Deload

    @ViewBuilder
    private func deloadSection(_ deload: DeloadRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Deload Recommendation")

            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(deload.urgencyScore > 0.5 ? STColors.danger : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "Urgency: %.0f%%", deload.urgencyScore * 100))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(STColors.textPrimary)

                    Text(deload.suggestedAction)
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)

                    Text("\(deload.weeksSinceLastDeload) weeks since last deload")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Block Comparison

    @ViewBuilder
    private func blockComparisonSection(_ comparison: BlockComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Block Comparison")

            Text(comparison.summaryText)
                .font(.system(size: 13))
                .foregroundStyle(STColors.textPrimary)

            HStack {
                Text(String(format: "%.0f%% similar", comparison.overallSimilarity * 100))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(STColors.textSecondary)

                Spacer()

                Text("\(comparison.blockALabel) vs \(comparison.blockBLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(STColors.textTertiary)
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Anomalies

    @ViewBuilder
    private var anomaliesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Unusual Sessions")

            ForEach(viewModel.insights.anomalies.prefix(3)) { anomaly in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.octagon")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(anomalyDescription(anomaly.anomalyScore))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)

                        let dims = anomaly.deviatingDimensions.prefix(2)
                            .map { humanReadableDrift($0) }
                            .joined(separator: ", ")
                        if !dims.isEmpty {
                            Text(dims)
                                .font(.system(size: 11))
                                .foregroundStyle(STColors.textSecondary)
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(STColors.textSecondary)
    }

    private func loadRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(STColors.textSecondary)
        }
    }

    private func zoneColor(_ zone: LoadZone) -> Color {
        switch zone {
        case .underTraining: return .blue
        case .optimal: return STColors.success
        case .caution: return .orange
        case .danger: return STColors.danger
        }
    }

    private func zoneDisplayName(_ zone: LoadZone) -> String {
        switch zone {
        case .underTraining: return "Under Training"
        case .optimal: return "Optimal"
        case .caution: return "Caution"
        case .danger: return "Danger"
        }
    }

    private func zoneExplanation(_ zone: LoadZone, acwr: Double, isDeload: Bool) -> String {
        if isDeload {
            return "Deload phase — reduced training load is intentional for recovery"
        }
        switch zone {
        case .underTraining: return "Training well below your baseline — increase effort to keep progressing"
        case .optimal where acwr < 1.0: return "Training within a sustainable range — load is slightly below your baseline"
        case .optimal:       return "Sustainable progression — slightly above baseline is ideal for gains"
        case .caution:       return "Ramping up quickly — make sure recovery keeps up"
        case .danger:        return "Very high load spike — ease off to reduce injury risk"
        }
    }

    private func anomalyDescription(_ score: Double) -> String {
        switch score {
        case 0.7...:    return "Very different from your usual sessions"
        case 0.5..<0.7: return "Noticeably different from your usual sessions"
        default:        return "Somewhat different from your usual sessions"
        }
    }

    private func humanReadableDrift(_ drift: DimensionDrift) -> String {
        let direction = drift.delta > 0 ? "Higher" : "Lower"
        switch drift.featureName {
        case "volume_vs_prev_7d":    return "\(direction) volume than last week"
        case "volume_vs_prev_30d":   return "\(direction) volume than your monthly avg"
        case "total_volume_norm":    return "\(direction) total volume"
        case "avg_weight_norm":      return "\(direction) average weight"
        case "avg_reps_norm":        return "\(direction) reps per set"
        case "set_count_norm":       return "\(direction) number of sets"
        case "exercise_diversity":   return drift.delta > 0 ? "More exercise variety" : "Less exercise variety"
        case "duration_norm":        return drift.delta > 0 ? "Longer session" : "Shorter session"
        case "compound_ratio":       return drift.delta > 0 ? "More compound lifts" : "Fewer compound lifts"
        case "avg_rpe":              return drift.delta > 0 ? "Higher effort (RPE)" : "Lower effort (RPE)"
        case "pr_count_norm":        return drift.delta > 0 ? "More PRs than usual" : "Fewer PRs than usual"
        default:
            let name = drift.featureName.replacingOccurrences(of: "_", with: " ")
            return "\(direction) \(name)"
        }
    }

    private func highlightIcon(_ type: HighlightType) -> String {
        switch type {
        case .personalRecord: return "trophy.fill"
        case .streak: return "flame.fill"
        case .milestone: return "flag.fill"
        case .improvement: return "arrow.up.right"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private func highlightColor(_ type: HighlightType) -> Color {
        switch type {
        case .personalRecord: return STColors.primary
        case .streak: return .orange
        case .milestone: return STColors.primary
        case .improvement: return STColors.success
        case .warning: return STColors.danger
        }
    }

    private func phaseIcon(_ phase: DetectedPhase) -> String {
        switch phase {
        case .accumulation: return "arrow.up.forward"
        case .intensification: return "bolt.fill"
        case .peaking: return "mountain.2.fill"
        case .deload: return "leaf.fill"
        case .mixed: return "circle.grid.cross"
        }
    }

    private func phaseDescription(_ phase: DetectedPhase) -> String {
        switch phase {
        case .accumulation: return "High volume — building work capacity"
        case .intensification: return "Heavy weights — building strength"
        case .peaking: return "Low volume, max weights — expressing strength"
        case .deload: return "Recovery phase — dissipating fatigue"
        case .mixed: return "Varied training pattern"
        }
    }

    private func phaseColor(_ phase: DetectedPhase) -> Color {
        switch phase {
        case .accumulation: return STColors.primary
        case .intensification: return .orange
        case .peaking: return STColors.danger
        case .deload: return STColors.success
        case .mixed: return STColors.textTertiary
        }
    }

    private func volumeStatusColor(_ status: VolumeStatus) -> Color {
        switch status {
        case .underVolume: return .blue
        case .optimal: return STColors.success
        case .overVolume: return STColors.danger
        }
    }

    private func volumeStatusLabel(_ status: VolumeStatus) -> String {
        switch status {
        case .underVolume: return "Under"
        case .optimal: return "Optimal"
        case .overVolume: return "Over"
        }
    }

    private func recoveryColor(_ status: RecoveryStatus) -> Color {
        switch status {
        case .ready: return STColors.success
        case .recovering: return .yellow
        case .fatigued: return STColors.danger
        }
    }

    private func recoveryLabel(_ status: RecoveryStatus) -> String {
        switch status {
        case .ready: return "Ready"
        case .recovering: return "Recovering"
        case .fatigued: return "Fatigued"
        }
    }

    private func trendIcon(_ status: TrendStatus) -> String {
        switch status {
        case .progressing: return "arrow.up.right"
        case .plateau: return "arrow.right"
        case .regressing: return "arrow.down.right"
        }
    }

    private func trendColor(_ status: TrendStatus) -> Color {
        switch status {
        case .progressing: return STColors.success
        case .plateau: return .yellow
        case .regressing: return STColors.danger
        }
    }

    private func trendLabel(_ status: TrendStatus) -> String {
        switch status {
        case .progressing: return "Progressing"
        case .plateau: return "Plateau"
        case .regressing: return "Regressing"
        }
    }
}

#endif
