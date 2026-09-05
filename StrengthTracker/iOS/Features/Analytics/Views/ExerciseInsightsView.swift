#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Per-exercise insights showing plateau status and recommendations.
/// Embedded as a section in ExerciseDetailView.
struct ExerciseInsightsView: View {
    let exercise: Exercise
    let viewModel: WorkoutAnalyticsViewModel
    @Environment(DataRevision.self) private var dataRevision: DataRevision?

    private var plateau: PlateauAnalysis? {
        viewModel.insights.plateaus.first { $0.exerciseId == exercise.id }
    }

    private var recommendations: [ExerciseRecommendation] {
        viewModel.insights.recommendations.filter { $0.exerciseId == exercise.id }
    }

    var body: some View {
        Group {
            if viewModel.isInsightsLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(STColors.primary)
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                }
            } else if !viewModel.isFeatureUnlocked(.plateauDetection) {
                Label("Unlock plateau detection with \(viewModel.nextFeatureUnlock?.workoutsNeeded ?? 0) more workouts",
                      systemImage: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textTertiary)
            } else if let plateau = plateau {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("Plateau Detected")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)
                    }

                    Text("No progress for \(plateau.consecutiveWeeksStalled) week\(plateau.consecutiveWeeksStalled == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)

                    Text(plateau.recommendation)
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.success)
                    Text("Progressing well - no plateau detected")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                }
            }

            if !recommendations.isEmpty {
                ForEach(recommendations) { rec in
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(STColors.primary)
                        Text(rec.reason.displayText(targetMuscleGroup: rec.targetMuscleGroup))
                            .font(.system(size: 12))
                            .foregroundStyle(STColors.textSecondary)
                    }
                }
            }
        }
        .task(id: dataRevision?.value ?? 0) {
            await viewModel.loadDashboardInsights()
        }
    }
}

#endif
