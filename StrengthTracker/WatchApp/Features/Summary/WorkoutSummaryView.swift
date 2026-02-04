import SwiftUI
import StrengthTrackerShared

struct WorkoutSummaryView: View {
    let workout: Workout

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)

                Text("Workout Complete")
                    .font(.headline)

                Text(workout.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(spacing: 8) {
                    if let duration = workout.duration {
                        Label(formatDuration(duration), systemImage: "clock")
                    }

                    Label(
                        "\(workout.exercises.count) exercises",
                        systemImage: "figure.strengthtraining.traditional"
                    )

                    let totalSets = workout.exercises.reduce(0) { $0 + $1.sets.count }
                    Label("\(totalSets) sets", systemImage: "repeat")

                    if workout.totalVolume > 0 {
                        Label(
                            String(format: "%.0f kg", workout.totalVolume),
                            systemImage: "scalemass"
                        )
                    }
                }
                .font(.caption)
            }
            .padding()
        }
        .navigationTitle("Summary")
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
