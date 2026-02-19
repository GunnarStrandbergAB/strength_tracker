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
    @State private var secondaryMuscleGroups: Set<MuscleGroup> = []
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

                Section("Secondary Muscle Groups (optional)") {
                    ForEach(MuscleGroup.allCases.filter { $0 != primaryMuscleGroup }, id: \.self) { group in
                        Button {
                            if secondaryMuscleGroups.contains(group) {
                                secondaryMuscleGroups.remove(group)
                            } else {
                                secondaryMuscleGroups.insert(group)
                            }
                        } label: {
                            HStack {
                                Text(group.rawValue.localizedCapitalized)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if secondaryMuscleGroups.contains(group) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Instructions (optional)") {
                    TextField("How to perform this exercise", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .onChange(of: primaryMuscleGroup) { _, newValue in
                secondaryMuscleGroups.remove(newValue)
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
                            secondaryMuscleGroups: Array(secondaryMuscleGroups),
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
