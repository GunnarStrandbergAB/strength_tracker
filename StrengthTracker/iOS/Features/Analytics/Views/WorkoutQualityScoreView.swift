#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Per-workout quality score breakdown shown inline in WorkoutDetailView.
struct WorkoutQualityScoreView: View {
    @Environment(DataRevision.self) private var dataRevision: DataRevision?
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
            } else if let score = viewModel.qualityScore, score.workoutId == workout.id {
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

                    // Every component contributing to the headline is visible.
                    VStack(spacing: 6) {
                        miniScoreBar("Volume", score: score.volumeScore)
                        miniScoreBar("Intensity", score: score.intensityScore)
                        miniScoreBar("Rest Rhythm", score: score.consistencyScore)
                        miniScoreBar("Program balance", score: score.balanceScore)
                    }
                }
                Text("Four equal components · program balance covers the prior 12 weeks")
                    .font(.caption).foregroundStyle(STColors.textSecondary)
                DisclosureGroup("Score and baseline details") {
                    ForEach(score.baselineNotes ?? [], id: \.self) { Text($0).font(.caption) }
                    Text("Each component contributes 25%. Volume reaches 100 at 80% of baseline and earns no extra points above that. Rest Rhythm uses 15–600-second completion gaps within an exercise; these include lifting time. Model version \(score.scoredModelVersion ?? 1).").font(.caption)
                }
                if score.isProvisional {
                    Text("Provisional: " + (score.provisionalReasons ?? []).joined(separator: "; "))
                        .font(.caption).foregroundStyle(STColors.textSecondary)
                }
            }
        }
        // Keyed on the workout VALUE so edits to its sets re-trigger the load
        // (the service cache keeps unchanged reloads cheap).
        .task(id: workout) {
            await viewModel.loadQualityScore(for: workout)
        }
        // Baselines are history-relative: any completed mutation rescored it.
        .task(id: dataRevision?.value ?? 0) {
            await viewModel.loadQualityScore(for: workout)
        }
    }

    private func miniScoreBar(_ label: String, score: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(STColors.textTertiary)
                .frame(width: 100, alignment: .leading)

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
        AnalyticsColors.score(score)
    }
}

#endif
