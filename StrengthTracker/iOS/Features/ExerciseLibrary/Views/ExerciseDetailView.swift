import SwiftUI
import StrengthTrackerShared

struct ExerciseDetailView: View {
    let exercise: Exercise
    var progressViewModel: ProgressViewModel? = nil
    var analyticsViewModel: WorkoutAnalyticsViewModel? = nil

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

            if let progressVM = progressViewModel {
                Section("Progress") {
                    NavigationLink {
                        ExerciseProgressView(viewModel: progressVM, exercise: exercise)
                    } label: {
                        Label("View Progress Chart", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }

            if let analyticsVM = analyticsViewModel {
                Section("Insights") {
                    ExerciseInsightsView(exercise: exercise, viewModel: analyticsVM)
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}
