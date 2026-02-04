import SwiftUI
import StrengthTrackerShared

struct ExerciseListView: View {
    @State private var viewModel: ExerciseListViewModel

    init(viewModel: ExerciseListViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.filteredExercises) { exercise in
                    NavigationLink(value: exercise) {
                        ExerciseRowView(exercise: exercise)
                    }
                }
            }
            .navigationTitle("Exercises")
            .searchable(text: $viewModel.searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Category", selection: $viewModel.selectedCategory) {
                            Text("All Categories").tag(ExerciseCategory?.none)
                            ForEach(ExerciseCategory.allCases, id: \.self) { category in
                                Text(category.rawValue.capitalized)
                                    .tag(ExerciseCategory?.some(category))
                            }
                        }
                        Picker("Muscle Group", selection: $viewModel.selectedMuscleGroup) {
                            Text("All Muscles").tag(MuscleGroup?.none)
                            ForEach(MuscleGroup.allCases, id: \.self) { group in
                                Text(group.rawValue.capitalized)
                                    .tag(MuscleGroup?.some(group))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.filteredExercises.isEmpty {
                    ContentUnavailableView(
                        "No Exercises",
                        systemImage: "dumbbell",
                        description: Text("No exercises match your filters.")
                    )
                }
            }
            .task {
                await viewModel.loadExercises()
            }
        }
    }
}

private struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.body)
                .fontWeight(.medium)
            HStack(spacing: 8) {
                Text(exercise.primaryMuscleGroup.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(exercise.category.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
