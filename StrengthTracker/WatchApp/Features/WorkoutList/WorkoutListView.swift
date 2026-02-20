import SwiftUI
import StrengthTrackerShared

struct WorkoutListView: View {
    @State private var workoutViewModel: WatchWorkoutViewModel
    @State private var listViewModel: WatchWorkoutListViewModel
    @State private var exerciseListViewModel: ExerciseListViewModel
    @State private var showExercisePicker = false

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

                // Planned sessions section (from active progression plan)
                if !listViewModel.plannedSessions.isEmpty {
                    Section("Today's Plan") {
                        ForEach(listViewModel.plannedSessions) { session in
                            Button {
                                Task {
                                    await workoutViewModel.startPlannedSession(session)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.sessionLabel)
                                        .font(.headline)
                                    Text("\(session.weekLabel) \u{00B7} \(session.template.exercises.count) exercises")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
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
                set: { newValue in workoutViewModel.isActive = newValue }
            )) {
                WatchActiveWorkoutView(viewModel: workoutViewModel)
            }
            .sheet(isPresented: $showExercisePicker) {
                WatchExercisePickerView(exerciseListViewModel: exerciseListViewModel) { exercises in
                    workoutViewModel.prepareQuickStart(name: "Quick Start", exercises: exercises)
                    // Skip sheet dismiss animation so navigation push isn't queued
                    // behind it — otherwise watchOS serializes dismiss then push.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showExercisePicker = false
                    }
                    Task {
                        await workoutViewModel.persistAndStartSession()
                    }
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
