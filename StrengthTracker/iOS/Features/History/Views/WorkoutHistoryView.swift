import SwiftUI
import StrengthTrackerShared

struct WorkoutHistoryView: View {
    @State private var viewModel: HistoryViewModel
    var analyticsViewModel: WorkoutAnalyticsViewModel? = nil

    init(viewModel: HistoryViewModel, analyticsViewModel: WorkoutAnalyticsViewModel? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.analyticsViewModel = analyticsViewModel
    }

    @State private var workoutToDelete: Workout? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutHistoryRow(workout: workout)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            workoutToDelete = workout
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(
                    workout: workout,
                    historyViewModel: viewModel,
                    analyticsViewModel: analyticsViewModel
                )
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "clock",
                        description: Text("Your completed workouts will appear here.")
                    )
                }
            }
            .task {
                await viewModel.loadHistory()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .confirmationDialog(
                "Delete Workout",
                isPresented: .init(
                    get: { workoutToDelete != nil },
                    set: { if !$0 { workoutToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let workout = workoutToDelete {
                        Task { await viewModel.deleteWorkout(workout) }
                        workoutToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    workoutToDelete = nil
                }
            } message: {
                Text("This will permanently delete the workout and all its data.")
            }
        }
    }
}

private struct WorkoutHistoryRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.name)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            HStack(spacing: 12) {
                Label(
                    workout.startedAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )
                if let duration = workout.duration {
                    Label(formatDuration(duration), systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if workout.totalVolume > 0 {
                Text("Volume: \(String(format: "%.0f", workout.totalVolume)) kg")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
