import SwiftUI
import StrengthTrackerShared

struct WatchActiveWorkoutView: View {
    @State private var viewModel: WatchWorkoutViewModel

    init(viewModel: WatchWorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let workout = viewModel.activeWorkout {
            TabView {
                if !workout.exercises.isEmpty {
                    exerciseView(workout)
                }

                summaryTab(workout)
            }
            .tabViewStyle(.verticalPage)
            .navigationBarBackButtonHidden()
        }
    }

    private func exerciseView(_ workout: Workout) -> some View {
        VStack(spacing: 8) {
            if viewModel.currentExerciseIndex < workout.exercises.count {
                let current = workout.exercises[viewModel.currentExerciseIndex]
                Text(current.exercise.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text("Sets: \(current.sets.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                WatchSetInputView(viewModel: viewModel)

                HStack {
                    Button {
                        viewModel.previousExercise()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentExerciseIndex == 0)

                    Text("\(viewModel.currentExerciseIndex + 1)/\(workout.exercises.count)")
                        .font(.caption2)

                    Button {
                        viewModel.nextExercise()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentExerciseIndex >= workout.exercises.count - 1)
                }
            }
        }
        .padding()
    }

    private func summaryTab(_ workout: Workout) -> some View {
        VStack(spacing: 8) {
            Text("Finish?")
                .font(.headline)

            Text(String(format: "Volume: %.0f", workout.totalVolume))
                .font(.caption)

            Button("Complete") {
                Task {
                    try? await viewModel.completeWorkout()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}
