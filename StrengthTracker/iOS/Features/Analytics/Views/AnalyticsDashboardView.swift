#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Full analytics dashboard pushed from the InsightsCard.
struct AnalyticsDashboardView: View {
    let viewModel: WorkoutAnalyticsViewModel

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

                    // Feature roadmap (shows locked features)
                    featureRoadmap

                    // Quality Score overview
                    if viewModel.isFeatureUnlocked(.qualityScore),
                       let score = viewModel.qualityScore {
                        qualityOverviewSection(score)
                    }

                    // Muscle Balance
                    if viewModel.isFeatureUnlocked(.muscleBalance),
                       let balance = viewModel.insights.muscleBalance {
                        muscleBalanceSection(balance)
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
        .task {
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

    private func qualityOverviewSection(_ score: WorkoutQualityScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Overall Quality")

            HStack(spacing: 20) {
                // Large score number
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", score.overallScore))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(score.overallScore))

                    Text("/ 100")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)
                }
                .frame(width: 80)

                // Dimension breakdown
                VStack(spacing: 8) {
                    scoreDimensionRow("Volume", score: score.volumeScore)
                    scoreDimensionRow("Intensity", score: score.intensityScore)
                    scoreDimensionRow("Balance", score: score.balanceScore)
                    scoreDimensionRow("Consistency", score: score.consistencyScore)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func scoreDimensionRow(_ label: String, score: Double) -> some View {
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
                        .fill(scoreColor(score))
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

                        Text(rec.reason.displayText)
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
