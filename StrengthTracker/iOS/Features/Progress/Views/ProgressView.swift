#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ExerciseProgressView: View {
    @State private var viewModel: ProgressViewModel

    init(viewModel: ProgressViewModel, exercise: Exercise? = nil) {
        self._viewModel = State(initialValue: viewModel)
        if let exercise = exercise {
            viewModel.selectedExercise = exercise
        }
    }

    var body: some View {
        List {
            Section {
                if viewModel.exercises.isEmpty && !viewModel.isLoading {
                    Text("No exercises available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Exercise", selection: $viewModel.selectedExercise) {
                        Text("Select an exercise")
                            .tag(Exercise?.none)
                        ForEach(viewModel.exercises) { exercise in
                            Text(exercise.name)
                                .tag(Exercise?.some(exercise))
                        }
                    }
                }
            } header: {
                Text("Exercise")
            }

            if viewModel.selectedExercise != nil {
                Section {
                    ExerciseProgressChart(data: viewModel.progressionData)
                } header: {
                    Text("Weight Progression")
                }

                Section {
                    if let best = viewModel.bestWeight {
                        LabeledContent("Best Weight") {
                            Text(String(format: "%.1f kg", best))
                                .fontWeight(.semibold)
                        }
                    }
                    if let bestReps = viewModel.bestReps {
                        LabeledContent("Best Reps") {
                            Text("\(bestReps)")
                                .fontWeight(.semibold)
                        }
                    }
                    if let e1rm = viewModel.estimated1RM {
                        LabeledContent("Est. 1RM") {
                            Text(String(format: "%.1f kg", e1rm))
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                    }
                    LabeledContent("Total Volume") {
                        Text(String(format: "%.0f kg", viewModel.totalVolume))
                            .fontWeight(.semibold)
                    }
                } header: {
                    Text("Summary")
                }
            }
        }
        .navigationTitle("Progress")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task {
            await viewModel.loadExercises()
            if let exercise = viewModel.selectedExercise {
                await viewModel.loadProgression(for: exercise.id)
            }
        }
        .onChange(of: viewModel.selectedExercise) { _, newExercise in
            if let exercise = newExercise {
                Task {
                    await viewModel.loadProgression(for: exercise.id)
                }
            }
        }
    }
}

#endif
