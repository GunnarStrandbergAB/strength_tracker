import SwiftUI
import StrengthTrackerShared

struct ExerciseListView: View {
    @State private var viewModel: ExerciseListViewModel
    let progressViewModel: ProgressViewModel
    var analyticsViewModel: WorkoutAnalyticsViewModel? = nil
    var personalRecordService: PersonalRecordService? = nil
    @State private var showAddExercise = false

    private let filterGroups: [MuscleGroup] = [
        .chest, .back, .shoulders, .biceps, .triceps, .quadriceps, .hamstrings, .glutes, .core
    ]

    init(viewModel: ExerciseListViewModel, progressViewModel: ProgressViewModel, analyticsViewModel: WorkoutAnalyticsViewModel? = nil, personalRecordService: PersonalRecordService? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.progressViewModel = progressViewModel
        self.analyticsViewModel = analyticsViewModel
        self.personalRecordService = personalRecordService
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Muscle group filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill(title: "All", isSelected: viewModel.selectedMuscleGroup == nil) {
                            viewModel.selectedMuscleGroup = nil
                        }
                        ForEach(filterGroups, id: \.self) { group in
                            filterPill(
                                title: group.pillLabel,
                                isSelected: viewModel.selectedMuscleGroup == group
                            ) {
                                viewModel.selectedMuscleGroup = group
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(.bar)

                List {
                    ForEach(viewModel.filteredExercises) { exercise in
                        NavigationLink(value: exercise) {
                            ExerciseRowView(exercise: exercise)
                        }
                    }
                }
            }
            .navigationTitle("Exercises")
            .searchable(text: $viewModel.searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showAddExercise = true } label: {
                            Image(systemName: "plus")
                        }
                        Menu {
                            Picker("Category", selection: $viewModel.selectedCategory) {
                                Text("All Categories").tag(ExerciseCategory?.none)
                                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                                    Text(category.rawValue.capitalized)
                                        .tag(ExerciseCategory?.some(category))
                                }
                            }
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseView(viewModel: viewModel, personalRecordService: personalRecordService)
            }
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise, progressViewModel: progressViewModel, analyticsViewModel: analyticsViewModel, personalRecordService: personalRecordService)
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
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? STColors.primary : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
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

// MARK: - Pill Labels

private extension MuscleGroup {
    var pillLabel: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .quadriceps: return "Quads"
        case .hamstrings: return "Hams"
        case .glutes: return "Glutes"
        case .core: return "Core"
        default: return rawValue.capitalized
        }
    }
}
