import SwiftUI
import StrengthTrackerShared

struct WorkoutDetailView: View {
    let workout: Workout

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent(
                    "Started",
                    value: workout.startedAt.formatted(date: .abbreviated, time: .shortened)
                )
                if let completedAt = workout.completedAt {
                    LabeledContent(
                        "Completed",
                        value: completedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if let duration = workout.duration {
                    LabeledContent("Duration", value: formatDuration(duration))
                }
                LabeledContent("Total Volume", value: String(format: "%.0f kg", workout.totalVolume))
                LabeledContent("Exercises", value: "\(workout.exercises.count)")
            }

            ForEach(workout.exercises) { workoutExercise in
                Section(workoutExercise.exercise.name) {
                    ForEach(workoutExercise.sets) { exerciseSet in
                        SetRowView(exerciseSet: exerciseSet)
                    }
                    if workoutExercise.exerciseVolume > 0 {
                        LabeledContent("Exercise Volume") {
                            Text(String(format: "%.0f kg", workoutExercise.exerciseVolume))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            if let notes = workout.notes {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(workout.name)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
