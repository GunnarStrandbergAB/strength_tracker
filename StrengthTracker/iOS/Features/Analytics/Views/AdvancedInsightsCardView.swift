#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Compact summary card for advanced insights (50+ workouts).
/// Shows training load gauge, current phase, top highlight, recovery summary.
/// Tapping navigates to the full AdvancedInsightsView.
struct AdvancedInsightsCardView: View {
    let viewModel: WorkoutAnalyticsViewModel

    var body: some View {
        NavigationLink {
            AdvancedInsightsView(viewModel: viewModel)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ADVANCED INSIGHTS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(STColors.textSecondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(STColors.textTertiary)
                }

                HStack(spacing: 16) {
                    // Training load gauge
                    if let load = viewModel.insights.trainingLoad {
                        loadGauge(load)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        // Current phase
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.path")
                                .font(.system(size: 11))
                                .foregroundStyle(STColors.primary)
                            Text(viewModel.currentPhaseDisplayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(STColors.textPrimary)
                        }

                        // Top highlight
                        if let highlight = viewModel.topHighlight {
                            Text(highlight.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(STColors.textSecondary)
                                .lineLimit(2)
                        }

                        // Recovery summary
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(STColors.success)
                            Text("\(viewModel.readyMuscleCount) ready")
                                .font(.system(size: 11))
                                .foregroundStyle(STColors.textSecondary)

                            if viewModel.recoveringMuscleCount > 0 {
                                Text("·")
                                    .foregroundStyle(STColors.textTertiary)
                                Text("\(viewModel.recoveringMuscleCount) recovering")
                                    .font(.system(size: 11))
                                    .foregroundStyle(STColors.textTertiary)
                            }
                        }
                    }
                }
            }
            .padding(STSpacing.cardPadding)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load Gauge

    private func loadGauge(_ load: TrainingLoad) -> some View {
        ZStack {
            Circle()
                .stroke(STColors.background, lineWidth: 4)
                .frame(width: 52, height: 52)

            Circle()
                .trim(from: 0, to: min(load.acwr / 2.0, 1.0))
                .stroke(loadColor(load.loadZone), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(viewModel.formatACWR(load.acwr))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(STColors.textPrimary)
                Text("ACWR")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(STColors.textTertiary)
            }
        }
    }

    private func loadColor(_ zone: LoadZone) -> Color {
        switch zone {
        case .underTraining: return .blue
        case .optimal: return STColors.success
        case .caution: return .orange
        case .danger: return STColors.danger
        }
    }
}

#endif
