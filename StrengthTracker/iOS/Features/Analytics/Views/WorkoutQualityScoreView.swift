#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Per-workout quality score breakdown shown inline in WorkoutDetailView.
struct WorkoutQualityScoreView: View {
    let viewModel: WorkoutAnalyticsViewModel
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.isQualityScoreLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(STColors.primary)
                    Text("Computing quality score...")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                }
            } else if let score = viewModel.qualityScore {
                HStack(spacing: 16) {
                    // Score circle
                    ZStack {
                        Circle()
                            .stroke(STColors.background, lineWidth: 4)
                            .frame(width: 52, height: 52)

                        Circle()
                            .trim(from: 0, to: score.overallScore / 100)
                            .stroke(scoreColor(score.overallScore), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 52, height: 52)

                        Text(String(format: "%.0f", score.overallScore))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(STColors.textPrimary)
                    }

                    // 3-dimension mini bars (balance excluded — it reflects
                    // 12-week program balance, not this single session)
                    VStack(spacing: 6) {
                        miniScoreBar("Volume", score: score.volumeScore)
                        miniScoreBar("Intensity", score: score.intensityScore)
                        miniScoreBar("Rest Rhythm", score: score.consistencyScore)
                    }
                }
            }
        }
        .task {
            if viewModel.qualityScore == nil || viewModel.qualityScore?.workoutId != workout.id {
                await viewModel.loadQualityScore(for: workout)
            }
        }
    }

    private func miniScoreBar(_ label: String, score: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(STColors.textTertiary)
                .frame(width: 56, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(STColors.background)
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(score / 100.0), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return STColors.success
        case 60..<80: return STColors.primary
        case 40..<60: return .orange
        default: return STColors.danger
        }
    }
}

#endif
