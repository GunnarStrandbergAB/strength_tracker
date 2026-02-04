import SwiftUI
import StrengthTrackerShared

struct WorkoutHistoryView: View {
    @State private var viewModel: HistoryViewModel

    init(viewModel: HistoryViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutHistoryRow(workout: workout)
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout)
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
