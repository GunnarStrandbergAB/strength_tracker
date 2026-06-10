#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct RecentWorkoutsWidget: View {
    let workouts: [Workout]
    let viewModel: DashboardViewModel
    let historyViewModel: HistoryViewModel
    let analyticsViewModel: WorkoutAnalyticsViewModel
    let recentWorkoutScores: [UUID: WorkoutQualityScore]
    let onHistoryTapped: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Text("Recent Workouts")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onHistoryTapped) {
                    Text("HISTORY")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(STColors.primary)
                        .tracking(0.5)
                }
            }
            .padding(.horizontal, 20)

            // Workout cards
            if workouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 28))
                        .foregroundStyle(STColors.textTertiary)

                    Text("No completed workouts yet")
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(workouts) { workout in
                        NavigationLink(value: workout) {
                            RecentWorkoutCard(
                                workout: workout,
                                viewModel: viewModel,
                                historyViewModel: historyViewModel,
                                qualityScore: recentWorkoutScores[workout.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Recent Workout Card

private struct RecentWorkoutCard: View {
    let workout: Workout
    let viewModel: DashboardViewModel
    let historyViewModel: HistoryViewModel
    let qualityScore: WorkoutQualityScore?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: name, date, menu
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text(viewModel.formatWorkoutDate(workout))
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)
                }

                Spacer()

                if let score = qualityScore {
                    Text("Quality \(Int(score.overallScore))/100")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(scoreColor(score.overallScore))
                }

                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(STColors.textTertiary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .padding(.bottom, 14)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
                .padding(.bottom, 14)

            // Stats row: Duration, Sets, Volume
            HStack(spacing: 0) {
                WorkoutStatItem(
                    label: "DURATION",
                    value: viewModel.formatWorkoutDuration(workout)
                )

                WorkoutStatItem(
                    label: "SETS",
                    value: "\(viewModel.totalSetsCount(for: workout))"
                )

                WorkoutStatItem(
                    label: "VOLUME",
                    value: "\(viewModel.formattedWorkoutVolume(workout)) \(viewModel.weightUnit.symbol)"
                )
            }
        }
        .padding(16)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .confirmationDialog(
            "Delete Workout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await historyViewModel.deleteWorkout(workout) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the workout and all its data.")
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

// MARK: - Workout Stat Item

private struct WorkoutStatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(STColors.textTertiary)
                .tracking(0.3)

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.8, green: 0.85, blue: 0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
