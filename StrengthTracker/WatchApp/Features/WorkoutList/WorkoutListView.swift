import SwiftUI
import StrengthTrackerShared

struct WorkoutListView: View {
    @State private var workoutViewModel: WatchWorkoutViewModel
    @State private var listViewModel: WatchWorkoutListViewModel

    init(workoutViewModel: WatchWorkoutViewModel, listViewModel: WatchWorkoutListViewModel) {
        self._workoutViewModel = State(initialValue: workoutViewModel)
        self._listViewModel = State(initialValue: listViewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if listViewModel.templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "dumbbell",
                        description: Text("Create templates on your iPhone to start workouts here.")
                    )
                } else {
                    List {
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
            .task {
                await listViewModel.loadData()
            }
            .refreshable {
                await listViewModel.loadData()
            }
        }
    }
}
