#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ExercisePickerView: View {
    @State private var viewModel: ExerciseListViewModel
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddExercise = false

    init(viewModel: ExerciseListViewModel, onSelect: @escaping (Exercise) -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Error Loading Exercises",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if viewModel.filteredExercises.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView.search
                        Button {
                            showingAddExercise = true
                        } label: {
                            Label("Create Custom Exercise", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    exerciseList
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddExercise = true
                    } label: {
                        Image(systemName: "plus.square")
                    }
                    .accessibilityLabel("Create Custom Exercise")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Muscle Group", selection: $viewModel.selectedMuscleGroup) {
                            Text("All").tag(nil as MuscleGroup?)
                            ForEach(MuscleGroup.allCases, id: \.self) { group in
                                if group != .other && group != .fullBody && group != .cardio {
                                    Text(group.rawValue.capitalized).tag(group as MuscleGroup?)
                                }
                            }
                        }

                        Picker("Category", selection: $viewModel.selectedCategory) {
                            Text("All").tag(nil as ExerciseCategory?)
                            ForEach(ExerciseCategory.allCases, id: \.self) { category in
                                if category != .other {
                                    Text(category.rawValue.capitalized).tag(category as ExerciseCategory?)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                AddExerciseView(viewModel: viewModel) { exercise in
                    onSelect(exercise)
                    dismiss()
                }
            }
            .task {
                if viewModel.exercises.isEmpty {
                    await viewModel.loadExercises()
                }
            }
        }
    }

    private var exerciseList: some View {
        List {
            if viewModel.selectedMuscleGroup == nil && viewModel.searchText.isEmpty {
                ForEach(groupedExercises, id: \.key) { group, exercises in
                    Section(group.rawValue.capitalized) {
                        ForEach(exercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            } else {
                ForEach(viewModel.filteredExercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        Button {
            onSelect(exercise)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text(exercise.category.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(exercise.primaryMuscleGroup.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
    }

    private var groupedExercises: [(key: MuscleGroup, value: [Exercise])] {
        let grouped = Dictionary(grouping: viewModel.filteredExercises) { $0.primaryMuscleGroup }
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }
}
#endif
