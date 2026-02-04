import SwiftUI
import StrengthTrackerShared

struct WorkoutListView: View {
    @State private var viewModel: WatchWorkoutViewModel

    init(viewModel: WatchWorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await viewModel.startWorkout(name: "Quick Workout", exercises: [])
                        }
                    } label: {
                        Label("Quick Start", systemImage: "bolt.fill")
                    }
                    .foregroundStyle(.green)
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(isPresented: Binding(
                get: { viewModel.isActive },
                set: { _ in }
            )) {
                WatchActiveWorkoutView(viewModel: viewModel)
            }
        }
    }
}
