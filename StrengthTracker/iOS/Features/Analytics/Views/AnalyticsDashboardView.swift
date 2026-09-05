#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared
#if canImport(Charts)
import Charts
#endif

/// Full analytics dashboard pushed from the InsightsCard.
struct AnalyticsDashboardView: View {
    let viewModel: WorkoutAnalyticsViewModel
    @Environment(DataRevision.self) private var dataRevision: DataRevision?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isInsightsLoading || viewModel.isMigrating {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(STColors.primary)
                        Text(viewModel.isMigrating ? "Analyzing workout history..." : "Loading insights...")
                            .font(.system(size: 13))
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // Next unlock banner (if applicable)
                    if let unlock = viewModel.nextFeatureUnlock {
                        nextUnlockBanner(unlock)
                    }

                    // Workout count summary
                    workoutCountHeader

                    // Feature roadmap (shows locked features, hidden when all unlocked)
                    let roadmapFeatures: [AnalyticsFeatureGate.Feature] = [
                        .qualityScore, .plateauDetection, .muscleBalance, .advancedInsights
                    ]
                    if roadmapFeatures.contains(where: { !viewModel.isFeatureUnlocked($0) }) {
                        featureRoadmap
                    }

                    // Quality Score overview (aggregate EWMA)
                    if viewModel.isFeatureUnlocked(.qualityScore),
                       let agg = viewModel.aggregateQuality, agg.workoutsIncluded > 0 {
                        aggregateQualitySection(agg)
                    }

                    // Muscle Balance
                    if viewModel.isFeatureUnlocked(.muscleBalance),
                       let balance = viewModel.insights.muscleBalance {
                        muscleBalanceSection(balance)
                    }

                    // Volume Response (per-muscle, data-shape gated)
                    let visibleVolumeResponse = viewModel.volumeResponseAnalyses.filter { $0.confidence != .insufficient }
                    if !visibleVolumeResponse.isEmpty {
                        volumeResponseSection(visibleVolumeResponse)
                    }

                    // Plateau Warnings
                    if viewModel.isFeatureUnlocked(.plateauDetection),
                       !viewModel.insights.plateaus.isEmpty {
                        plateauSection(viewModel.insights.plateaus)
                    }

                    // Recommendations
                    if viewModel.isFeatureUnlocked(.exerciseRecommendations),
                       !viewModel.insights.recommendations.isEmpty {
                        recommendationsSection(viewModel.insights.recommendations)
                    }

                    // Advanced Insights card (50+ workouts)
                    if viewModel.isFeatureUnlocked(.advancedInsights),
                       viewModel.advancedInsightsLoaded {
                        AdvancedInsightsCardView(viewModel: viewModel)
                    }
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(STColors.background)
        .scrollIndicators(.hidden)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .stNavigationBarStyle()
        .task(id: dataRevision?.value ?? 0) {
            await viewModel.loadDashboardInsights()
        }
    }

    // MARK: - Header & Roadmap

    private var workoutCountHeader: some View {
        VStack(spacing: 4) {
            Text("\(viewModel.insights.workoutCount)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(STColors.textPrimary)
            Text("workouts completed")
                .font(.system(size: 13))
                .foregroundStyle(STColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private var featureRoadmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Feature Roadmap")

            featureRow(.qualityScore, threshold: 5, icon: "star.fill")
            featureRow(.plateauDetection, threshold: 10, icon: "exclamationmark.triangle.fill")
            featureRow(.muscleBalance, threshold: 20, icon: "arrow.left.arrow.right")
            featureRow(.advancedInsights, threshold: 19, icon: "brain.head.profile")
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func featureRow(_ feature: AnalyticsFeatureGate.Feature, threshold: Int, icon: String) -> some View {
        let unlocked = viewModel.isFeatureUnlocked(feature)
        let count = viewModel.insights.workoutCount
        let remaining = max(threshold - count, 0)
        let progress = min(Double(count) / Double(threshold), 1.0)

        return HStack(spacing: 10) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : icon)
                .font(.system(size: 14))
                .foregroundStyle(unlocked ? STColors.success : STColors.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.featureDisplayName(feature))
                    .font(.system(size: 13, weight: unlocked ? .semibold : .regular))
                    .foregroundStyle(unlocked ? STColors.textPrimary : STColors.textSecondary)

                Text(viewModel.featureDescription(feature))
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)

                if !unlocked {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(STColors.background)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(STColors.primary.opacity(0.6))
                                .frame(width: geo.size.width * CGFloat(progress), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer()

            if unlocked {
                Text("Unlocked")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(STColors.success)
            } else {
                Text("\(remaining) more")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)
            }
        }
    }

    // MARK: - Sections

    private func nextUnlockBanner(_ unlock: (feature: AnalyticsFeatureGate.Feature, workoutsNeeded: Int)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(STColors.primary)

            Text("\(unlock.workoutsNeeded) more workout\(unlock.workoutsNeeded == 1 ? "" : "s") to unlock **\(viewModel.featureDisplayName(unlock.feature))**")
                .font(.system(size: 13))
                .foregroundStyle(STColors.textSecondary)

            Spacer()
        }
        .padding(12)
        .background(STColors.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func aggregateQualitySection(_ agg: AggregateQualityScore) -> some View {
        let color = aggregateScoreColor(percentile: agg.percentileRank)

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Training Quality")

            HStack(spacing: 20) {
                // Large EWMA score
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", agg.ewmaOverall))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(color)

                    Text("/ 100")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)

                    // Trend badge
                    if abs(agg.trendVsPrior) >= 1 {
                        HStack(spacing: 2) {
                            Image(systemName: agg.trendVsPrior >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9))
                            Text(String(format: "%.0f%%", abs(agg.trendVsPrior)))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(agg.trendVsPrior >= 0 ? STColors.success : .orange)
                    }
                }
                .frame(width: 80)

                // Dimension breakdown
                VStack(spacing: 8) {
                    aggregateDimensionRow("Volume", score: agg.ewmaVolume, percentile: agg.percentileRank)
                    aggregateDimensionRow("Intensity", score: agg.ewmaIntensity, percentile: agg.percentileRank)
                    aggregateDimensionRow("Balance", score: agg.ewmaBalance, percentile: agg.percentileRank)
                    aggregateDimensionRow("Rest Rhythm", score: agg.ewmaConsistency, percentile: agg.percentileRank)
                }
            }

            // Footer
            Text("Based on \(agg.workoutsIncluded) recent workouts")
                .font(.system(size: 11))
                .foregroundStyle(STColors.textTertiary)
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func aggregateDimensionRow(_ label: String, score: Double, percentile: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(STColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(STColors.background)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(aggregateScoreColor(percentile: percentile))
                        .frame(width: geo.size.width * CGFloat(score / 100.0), height: 6)
                }
            }
            .frame(height: 6)

            Text(String(format: "%.0f", score))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(STColors.textSecondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func aggregateScoreColor(percentile: Double) -> Color {
        switch percentile {
        case 0.75...: return STColors.success      // green — top quartile
        case 0.50..<0.75: return STColors.primary  // gold
        case 0.25..<0.50: return .orange
        default: return STColors.danger            // red — bottom quartile
        }
    }

    private func muscleBalanceSection(_ balance: MuscleBalance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Muscle Balance")

            // Volume bars per muscle group
            let maxVol = balance.muscleGroupVolumes.map(\.weeklyVolume).max() ?? 1.0
            ForEach(balance.muscleGroupVolumes) { vol in
                HStack(spacing: 8) {
                    Text(vol.muscleGroup.capitalized)
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(for: vol.muscleGroup, imbalances: balance.imbalances))
                            .frame(width: geo.size.width * CGFloat(vol.weeklyVolume / max(maxVol, 1)), height: 12)
                    }
                    .frame(height: 12)

                    Text("\(vol.weeklySetCount) sets")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(STColors.textTertiary)
                        .frame(width: 50, alignment: .trailing)
                }
            }

            // Imbalance warnings
            if !balance.imbalances.isEmpty {
                Divider().overlay(STColors.border)

                ForEach(balance.imbalances) { imbalance in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(severityColor(imbalance.severity))
                            .frame(width: 8, height: 8)

                        Text(imbalance.recommendation)
                            .font(.system(size: 12))
                            .foregroundStyle(STColors.textSecondary)
                    }
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func volumeResponseSection(_ analyses: [VolumeResponseAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Volume Response")

            Text("Your personal response curve per muscle. More muscle groups appear as your training builds varied weekly volume history.")
                .font(.system(size: 11))
                .foregroundStyle(STColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(analyses, id: \.muscleGroup) { analysis in
                volumeResponseSubcard(analysis)
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func volumeResponseSubcard(_ analysis: VolumeResponseAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(analysis.muscleGroup.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)

                Spacer()

                confidencePill(analysis.confidence)
            }

            if analysis.confidence != .insufficient {
                volumeResponseChart(analysis)
                    .frame(height: 140)
            }

            Text(analysis.sentence)
                .font(.system(size: 11))
                .foregroundStyle(STColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confidencePill(_ confidence: Confidence) -> some View {
        let label: String
        let color: Color
        switch confidence {
        case .high: label = "high"; color = STColors.success
        case .medium: label = "medium"; color = STColors.primary
        case .low: label = "low"; color = STColors.textTertiary
        case .insufficient: label = "building"; color = STColors.textTertiary
        }
        return Text(label)
            .font(.system(size: 9, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func volumeResponseChart(_ analysis: VolumeResponseAnalysis) -> some View {
        #if canImport(Charts)
        let bestBin = bestBin(analysis.best)
        Chart {
            ForEach(analysis.bins, id: \.bin) { bin in
                let isBest = bin.bin == bestBin
                if let smoothed = bin.smoothed {
                    BarMark(
                        x: .value("Volume", bin.bin.label),
                        y: .value("Response", smoothed * 100)
                    )
                    .foregroundStyle(isBest ? STColors.success : STColors.primary.opacity(0.7))
                    .cornerRadius(4)
                } else {
                    BarMark(
                        x: .value("Volume", bin.bin.label),
                        y: .value("Response", 0)
                    )
                    .foregroundStyle(STColors.background)
                }

                if let q1 = bin.q1, let q3 = bin.q3, bin.observationCount >= 5 {
                    RectangleMark(
                        x: .value("Volume", bin.bin.label),
                        yStart: .value("Q1", q1 * 100),
                        yEnd: .value("Q3", q3 * 100),
                        width: .fixed(2)
                    )
                    .foregroundStyle(STColors.textTertiary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxisLabel("% change")
        #else
        Text("Charts unavailable on this platform")
            .font(.system(size: 11))
            .foregroundStyle(STColors.textTertiary)
        #endif
    }

    private func bestBin(_ status: BestRangeStatus) -> VolumeBin? {
        switch status {
        case .observedPeak(let bin), .bestObservedSoFar(let bin):
            return bin
        case .unclear(let bins):
            return bins.first
        case .insufficient:
            return nil
        }
    }

    private func plateauSection(_ plateaus: [PlateauAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Plateau Warnings")

            ForEach(plateaus) { plateau in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plateau.exerciseName ?? "Unknown Exercise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)

                        Text("Stalled for \(plateau.consecutiveWeeksStalled) week\(plateau.consecutiveWeeksStalled == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(STColors.textSecondary)

                        Text(plateau.recommendation)
                            .font(.system(size: 11))
                            .foregroundStyle(STColors.textTertiary)
                    }

                    Spacer()
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func recommendationsSection(_ recommendations: [ExerciseRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recommendations")

            ForEach(recommendations) { rec in
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.exerciseName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)

                        Text(rec.reason.displayText(targetMuscleGroup: rec.targetMuscleGroup))
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

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(STColors.textSecondary)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return STColors.success
        case 60..<80: return STColors.primary
        case 40..<60: return .orange
        default: return STColors.danger
        }
    }

    private func barColor(for muscleGroup: String, imbalances: [MuscleImbalance]) -> Color {
        if imbalances.contains(where: { $0.primaryGroup == muscleGroup }) {
            return .orange
        }
        return STColors.primary.opacity(0.8)
    }

    private func severityColor(_ severity: ImbalanceSeverity) -> Color {
        switch severity {
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return STColors.danger
        }
    }
}

#endif
