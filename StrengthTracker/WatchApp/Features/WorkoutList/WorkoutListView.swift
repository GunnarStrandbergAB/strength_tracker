import SwiftUI
import StrengthTrackerShared

struct WorkoutListView: View {
    @State private var viewModel: WatchWorkoutViewModel

    init(viewModel: WatchWorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Start") {
                    quickStartButton(
                        name: "Upper Body",
                        icon: "figure.arms.open",
                        exercises: upperBodyExercises
                    )
                    quickStartButton(
                        name: "Lower Body",
                        icon: "figure.walk",
                        exercises: lowerBodyExercises
                    )
                    quickStartButton(
                        name: "Push",
                        icon: "arrow.up.circle.fill",
                        exercises: pushExercises
                    )
                    quickStartButton(
                        name: "Pull",
                        icon: "arrow.down.circle.fill",
                        exercises: pullExercises
                    )
                    quickStartButton(
                        name: "Full Body",
                        icon: "figure.strengthtraining.traditional",
                        exercises: fullBodyExercises
                    )
                }

                Section {
                    Button {
                        Task {
                            await viewModel.startWorkout(name: "Empty Workout", exercises: [])
                        }
                    } label: {
                        Label("Blank Workout", systemImage: "plus.circle")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(isPresented: Binding(
                get: { viewModel.isActive },
                set: { _ in }
            )) {
                WatchActiveWorkoutView(viewModel: viewModel)
            }
        }
    }

    private func quickStartButton(name: String, icon: String, exercises: [Exercise]) -> some View {
        Button {
            Task {
                await viewModel.startWorkout(name: name, exercises: exercises)
            }
        } label: {
            Label(name, systemImage: icon)
        }
        .foregroundStyle(.green)
    }

    // MARK: - Preset Exercise Lists

    private var upperBodyExercises: [Exercise] {
        let all = ExerciseSeedData.allExercises
        let targets: Set<MuscleGroup> = [.chest, .back, .shoulders, .biceps, .triceps, .lats, .traps]
        return Array(all.filter { targets.contains($0.primaryMuscleGroup) }.prefix(6))
    }

    private var lowerBodyExercises: [Exercise] {
        let all = ExerciseSeedData.allExercises
        let targets: Set<MuscleGroup> = [.quadriceps, .hamstrings, .glutes, .calves]
        return Array(all.filter { targets.contains($0.primaryMuscleGroup) }.prefix(5))
    }

    private var pushExercises: [Exercise] {
        let all = ExerciseSeedData.allExercises
        let targets: Set<MuscleGroup> = [.chest, .shoulders, .triceps]
        return Array(all.filter { targets.contains($0.primaryMuscleGroup) }.prefix(5))
    }

    private var pullExercises: [Exercise] {
        let all = ExerciseSeedData.allExercises
        let targets: Set<MuscleGroup> = [.back, .biceps, .lats]
        return Array(all.filter { targets.contains($0.primaryMuscleGroup) }.prefix(5))
    }

    private var fullBodyExercises: [Exercise] {
        let all = ExerciseSeedData.allExercises
        // Pick one from each major group for a balanced workout
        var selected: [Exercise] = []
        let groups: [MuscleGroup] = [.chest, .back, .shoulders, .quadriceps, .hamstrings, .core]
        for group in groups {
            if let exercise = all.first(where: { $0.primaryMuscleGroup == group }) {
                selected.append(exercise)
            }
        }
        return selected
    }
}
