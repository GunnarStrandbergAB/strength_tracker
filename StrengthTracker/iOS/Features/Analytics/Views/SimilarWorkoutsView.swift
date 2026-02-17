#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// List of workouts similar to a given workout, shown as a sheet or pushed view.
struct SimilarWorkoutsView: View {
    let viewModel: WorkoutAnalyticsViewModel
    let workout: Workout

    var body: some View {
        Group {
            if viewModel.isSimilarWorkoutsLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(STColors.primary)
                    Text("Finding similar workouts...")
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.similarWorkouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(STColors.textTertiary)
                    Text("No similar workouts found")
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.textSecondary)
                    Text("Complete more workouts to find matches")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.similarWorkouts) { similar in
                            similarWorkoutCard(similar)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(STColors.background)
        .navigationTitle("Similar Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .stNavigationBarStyle()
        .task {
            await viewModel.loadSimilarWorkouts(to: workout)
        }
    }

    private func similarWorkoutCard(_ similar: SimilarWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(similar.workoutName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(STColors.textPrimary)

                    Text(similar.workoutDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                }

                Spacer()

                // Similarity badge
                Text(viewModel.formatSimilarity(similar.similarityScore))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(STColors.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(STColors.primary)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label(viewModel.formatVolume(similar.totalVolume) + " kg", systemImage: "scalemass")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textSecondary)

                if !similar.matchedFeatures.isEmpty {
                    Text(similar.matchedFeatures.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }
}

#endif
