import SwiftUI
import StrengthTrackerShared

struct WorkoutListView: View {
    @State private var workoutViewModel: WatchWorkoutViewModel
    @State private var listViewModel: WatchWorkoutListViewModel

    init(workoutViewModel: WatchWorkoutViewModel, listViewModel: WatchWorkoutListViewModel) {
        self._workoutViewModel = State(initialValue: workoutViewModel)
        self._listViewModel = State(initialValue: listViewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                // Quick Start section - always available
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

                // Templates section - synced from iPhone
                if !listViewModel.templates.isEmpty {
                    Section("Templates") {
                        ForEach(listViewModel.templates) { template in
                            Button {
                                Task {
                                    await startFromTemplate(template)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.headline)
                                    Text("\(template.exercises.count) exercises")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                }

                // Recent workouts section
                if !listViewModel.recentWorkouts.isEmpty {
                    Section("Recent") {
                        ForEach(listViewModel.recentWorkouts.prefix(3)) { workout in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .font(.headline)
                                HStack {
                                    Text(workout.startedAt, style: .date)
                                    Text("·")
                                    Text("\(workout.exercises.count) exercises")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Blank workout option
                Section {
                    Button {
                        Task {
                            await workoutViewModel.startWorkout(name: "Empty Workout", exercises: [])
                        }
                    } label: {
                        Label("Blank Workout", systemImage: "plus.circle")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(isPresented: Binding(
                get: { workoutViewModel.isActive },
                set: { _ in }
            )) {
                WatchActiveWorkoutView(viewModel: workoutViewModel)
            }
            .task {
                await listViewModel.loadData()
            }
            .refreshable {
                await listViewModel.loadData()
            }
        }
    }

    private func quickStartButton(name: String, icon: String, exercises: [Exercise]) -> some View {
        Button {
            Task {
                await workoutViewModel.startWorkout(name: name, exercises: exercises)
            }
        } label: {
            Label(name, systemImage: icon)
        }
        .foregroundStyle(.green)
    }

    private func startFromTemplate(_ template: WorkoutTemplate) async {
        // Convert template exercises to regular exercises
        let exercises = template.exercises
            .sorted { $0.order < $1.order }
            .map { $0.exercise }
        await workoutViewModel.startWorkout(name: template.name, exercises: exercises)
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
