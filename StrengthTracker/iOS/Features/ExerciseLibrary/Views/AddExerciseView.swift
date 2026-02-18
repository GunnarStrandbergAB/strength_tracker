#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct AddExerciseView: View {
    let viewModel: ExerciseListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var primaryMuscleGroup: MuscleGroup = .chest
    @State private var category: ExerciseCategory = .barbell
    @State private var exerciseType: ExerciseType = .weightedReps
    @State private var instructions = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Exercise name", text: $name)
                }

                Section("Details") {
                    Picker("Muscle Group", selection: $primaryMuscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { group in
                            Text(group.rawValue.localizedCapitalized)
                                .tag(group)
                        }
                    }

                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue.localizedCapitalized)
                                .tag(cat)
                        }
                    }

                    Picker("Type", selection: $exerciseType) {
                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            Text(type.rawValue.localizedCapitalized)
                                .tag(type)
                        }
                    }
                }

                Section("Instructions (optional)") {
                    TextField("How to perform this exercise", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let exercise = Exercise(
                            id: UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            primaryMuscleGroup: primaryMuscleGroup,
                            secondaryMuscleGroups: [],
                            category: category,
                            exerciseType: exerciseType,
                            instructions: instructions.isEmpty ? nil : instructions,
                            isCustom: true,
                            isArchived: false
                        )
                        Task {
                            await viewModel.saveExercise(exercise)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
#endif
