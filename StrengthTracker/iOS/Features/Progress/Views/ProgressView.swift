#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ExerciseProgressView: View {
    @Environment(DataRevision.self) private var dataRevision: DataRevision?
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
                    ExerciseProgressChart(data: viewModel.progressionData, weightUnit: viewModel.weightUnit)
                } header: {
                    Text("Weight Progression")
                }

                Section {
                    if let best = viewModel.bestWeight {
                        LabeledContent("Best Weight") {
                            Text(viewModel.weightUnit.format(best, decimals: 1))
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
                            Text(viewModel.weightUnit.format(e1rm, decimals: 1))
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                    }
                    LabeledContent("Total Volume") {
                        Text(viewModel.weightUnit.format(viewModel.totalVolume, decimals: 0))
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
        .task(id: dataRevision?.value ?? 0) {
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
