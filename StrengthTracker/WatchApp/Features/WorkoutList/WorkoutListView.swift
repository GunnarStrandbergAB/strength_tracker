import SwiftUI
import StrengthTrackerShared

struct WorkoutListView: View {
    @State private var workoutViewModel: WatchWorkoutViewModel
    @State private var listViewModel: WatchWorkoutListViewModel
    @State private var exerciseListViewModel: ExerciseListViewModel
    @State private var showExercisePicker = false
    @State private var pendingQuickStartExercises: [Exercise]? = nil

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)

    init(
        workoutViewModel: WatchWorkoutViewModel,
        listViewModel: WatchWorkoutListViewModel,
        exerciseListViewModel: ExerciseListViewModel
    ) {
        self._workoutViewModel = State(initialValue: workoutViewModel)
        self._listViewModel = State(initialValue: listViewModel)
        self._exerciseListViewModel = State(initialValue: exerciseListViewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                // Quick Start section
                Section {
                    Button {
                        showExercisePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(primaryYellow)
                            Text("Quick Start")
                                .font(.headline)
                        }
                    }
                }

                // Templates section
                if !listViewModel.templates.isEmpty {
                    Section("Templates") {
                        ForEach(listViewModel.templates) { template in
                            Button {
                                Task {
                                    await workoutViewModel.startWorkout(name: template.name, from: template)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.headline)
                                    Text("\(template.exercises.count) exercises")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(isPresented: Binding(
                get: { workoutViewModel.isActive },
                set: { _ in }
            )) {
                WatchActiveWorkoutView(viewModel: workoutViewModel)
            }
            .sheet(isPresented: $showExercisePicker, onDismiss: {
                if let exercises = pendingQuickStartExercises {
                    pendingQuickStartExercises = nil
                    Task {
                        await workoutViewModel.startWorkout(name: "Quick Start", exercises: exercises)
                    }
                }
            }) {
                WatchExercisePickerView(exerciseListViewModel: exerciseListViewModel) { exercises in
                    pendingQuickStartExercises = exercises
                    showExercisePicker = false
                }
            }
            .task {
                await listViewModel.loadData()
            }
            .refreshable {
                await listViewModel.loadData()
            }
        }
    }
}
