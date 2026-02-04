import SwiftUI
import StrengthTrackerShared

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Category", value: exercise.category.rawValue.capitalized)
                LabeledContent("Type", value: exercise.exerciseType.rawValue.capitalized)
            }

            Section("Muscle Groups") {
                LabeledContent("Primary", value: exercise.primaryMuscleGroup.rawValue.capitalized)
                if !exercise.secondaryMuscleGroups.isEmpty {
                    LabeledContent("Secondary") {
                        Text(
                            exercise.secondaryMuscleGroups
                                .map { $0.rawValue.capitalized }
                                .joined(separator: ", ")
                        )
                    }
                }
            }

            if let instructions = exercise.instructions {
                Section("Instructions") {
                    Text(instructions)
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}
