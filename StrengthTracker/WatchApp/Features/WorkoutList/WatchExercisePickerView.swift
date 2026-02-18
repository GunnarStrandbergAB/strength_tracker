import SwiftUI
import StrengthTrackerShared

struct WatchExercisePickerView: View {
    @State private var exerciseListViewModel: ExerciseListViewModel
    @State private var selectedExercises: [Exercise] = []

    let onStartWorkout: ([Exercise]) -> Void

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)

    init(exerciseListViewModel: ExerciseListViewModel, onStartWorkout: @escaping ([Exercise]) -> Void) {
        self._exerciseListViewModel = State(initialValue: exerciseListViewModel)
        self.onStartWorkout = onStartWorkout
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Muscle group filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterPill(title: "All", isSelected: exerciseListViewModel.selectedMuscleGroup == nil) {
                            exerciseListViewModel.selectedMuscleGroup = nil
                        }

                        ForEach(mainMuscleGroups, id: \.self) { group in
                            filterPill(
                                title: group.displayName,
                                isSelected: exerciseListViewModel.selectedMuscleGroup == group
                            ) {
                                exerciseListViewModel.selectedMuscleGroup = group
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                // Exercise list
                List {
                    ForEach(exerciseListViewModel.filteredExercises) { exercise in
                        Button {
                            toggleExercise(exercise)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(exercise.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .lineLimit(1)
                                    Text(exercise.primaryMuscleGroup.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedExercises.contains(where: { $0.id == exercise.id }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(primaryYellow)
                                        .font(.system(size: 18))
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 18))
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.plain)

                // Start button
                if !selectedExercises.isEmpty {
                    Button {
                        onStartWorkout(selectedExercises)
                    } label: {
                        Text("START (\(selectedExercises.count))")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(primaryYellow)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await exerciseListViewModel.loadExercises()
            }
        }
    }

    private func toggleExercise(_ exercise: Exercise) {
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
        }
    }

    @ViewBuilder
    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? primaryYellow : Color.white.opacity(0.12))
                .foregroundStyle(isSelected ? .black : .white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // Show the most common muscle groups for quick filtering
    private var mainMuscleGroups: [MuscleGroup] {
        [.chest, .back, .shoulders, .biceps, .triceps, .quadriceps, .hamstrings, .glutes, .core]
    }
}

// MARK: - MuscleGroup Display Name
extension MuscleGroup {
    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .core: return "Core"
        case .quadriceps: return "Quads"
        case .hamstrings: return "Hams"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .adductors: return "Adductors"
        case .abductors: return "Abductors"
        case .traps: return "Traps"
        case .lats: return "Lats"
        case .hipFlexors: return "Hip Flexors"
        case .lowerBack: return "Lower Back"
        case .obliques: return "Obliques"
        case .fullBody: return "Full Body"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }
}
