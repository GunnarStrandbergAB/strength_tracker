import SwiftUI
import StrengthTrackerShared
#if os(watchOS)
import WatchKit
#endif

struct WorkoutSummaryView: View {
    let workout: Workout
    @State private var viewModel: WatchWorkoutViewModel
    @State private var showCheckmark = false
    @State private var showingCancelConfirmation = false

    init(workout: Workout, viewModel: WatchWorkoutViewModel) {
        self.workout = workout
        self._viewModel = State(initialValue: viewModel)
    }

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)
    private let cardBackground = Color.white.opacity(0.1)
    private let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Large checkmark with animation
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                        .scaleEffect(showCheckmark ? 1.0 : 0.5)
                        .opacity(showCheckmark ? 1.0 : 0.3)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        showCheckmark = true
                    }
                }

                Text("Finish Workout?")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)

                // Stats grid
                VStack(spacing: 6) {
                    // Duration
                    statRow(
                        icon: "clock.fill",
                        label: "Duration",
                        value: formatElapsedTime(viewModel.elapsedTime)
                    )

                    // Exercises
                    statRow(
                        icon: "figure.strengthtraining.traditional",
                        label: "Exercises",
                        value: "\(workout.exercises.count)"
                    )

                    // Total sets
                    let totalSets = workout.exercises.reduce(0) { $0 + $1.sets.count }
                    statRow(
                        icon: "repeat",
                        label: "Sets",
                        value: "\(totalSets)"
                    )

                    // Volume
                    if workout.totalVolume > 0 {
                        statRow(
                            icon: "scalemass.fill",
                            label: "Volume",
                            value: String(format: "%.0f kg", workout.totalVolume)
                        )
                    }
                }
                .padding(8)
                .background(cardBackground)
                .cornerRadius(12)

                // Notes indicator (Task 5.2)
                if let notes = workout.notes, !notes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundStyle(primaryYellow)
                        Text("Has notes")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }
                } else if !viewModel.workoutNotes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundStyle(primaryYellow)
                        Text("Notes added")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }
                }

                // Done button
                Button {
                    #if os(watchOS)
                    WKInterfaceDevice.current().play(.success)
                    #endif
                    Task {
                        do {
                            try await viewModel.completeWorkout()
                        } catch {
                            print("[WorkoutSummary] Complete workout failed: \(error)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isCompleting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("DONE")
                                .font(.system(size: 14, weight: .black))
                                .tracking(1)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(viewModel.isCompleting ? primaryYellow.opacity(0.5) : primaryYellow)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCompleting)

                // Cancel button — below DONE for intentional friction
                Button {
                    showingCancelConfirmation = true
                } label: {
                    Text("Cancel Workout")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCompleting)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .confirmationDialog("Cancel this workout?", isPresented: $showingCancelConfirmation, titleVisibility: .visible) {
            Button("Cancel Workout", role: .destructive) {
                Task {
                    await viewModel.cancelWorkout()
                }
            }
            Button("Keep Going", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(primaryYellow)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
