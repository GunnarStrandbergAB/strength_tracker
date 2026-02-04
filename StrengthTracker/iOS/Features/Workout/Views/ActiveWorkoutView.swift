import SwiftUI
import StrengthTrackerShared

struct ActiveWorkoutView: View {
    @State private var viewModel: WorkoutViewModel
    @State private var exerciseListViewModel: ExerciseListViewModel
    @State private var showingExercisePicker = false

    init(viewModel: WorkoutViewModel, exerciseListViewModel: ExerciseListViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self._exerciseListViewModel = State(initialValue: exerciseListViewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = viewModel.currentWorkout, viewModel.isActive {
                    workoutContent(workout)
                } else {
                    startView
                }
            }
            .navigationTitle(viewModel.currentWorkout?.name ?? "Workout")
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                    viewModel.addExercise(exercise)
                }
            }
        }
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Active Workout")
                .font(.title2)
            Button("Start Workout") {
                Task {
                    await viewModel.startWorkout(name: "Quick Workout", from: nil)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func workoutContent(_ workout: Workout) -> some View {
        List {
            ForEach(workout.exercises) { workoutExercise in
                Section(workoutExercise.exercise.name) {
                    ForEach(workoutExercise.sets) { exerciseSet in
                        SetRowView(exerciseSet: exerciseSet)
                    }
                    Button("Add Set") {
                        Task {
                            try? await viewModel.logSet(
                                exerciseId: workoutExercise.exercise.id,
                                weight: nil,
                                reps: nil,
                                setType: .normal
                            )
                        }
                    }
                }
            }

            Section {
                LabeledContent("Total Volume") {
                    Text(String(format: "%.0f kg", workout.totalVolume))
                        .fontWeight(.semibold)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Complete") {
                    Task {
                        try? await viewModel.completeWorkout()
                    }
                }
                .fontWeight(.bold)
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                }
            }
        }
    }
}
