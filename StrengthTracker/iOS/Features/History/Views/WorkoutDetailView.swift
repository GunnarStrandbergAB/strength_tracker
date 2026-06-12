import SwiftUI
import StrengthTrackerShared

struct WorkoutDetailView: View {
    let workout: Workout
    var historyViewModel: HistoryViewModel? = nil
    var analyticsViewModel: WorkoutAnalyticsViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    /// The displayed workout: use historyViewModel's selectedWorkout (live edits) if available.
    private var displayedWorkout: Workout {
        historyViewModel?.selectedWorkout ?? workout
    }

    private var weightUnit: WeightUnit {
        historyViewModel?.userPreferencesService?.weightUnit ?? .kg
    }

    var body: some View {
        let isEditing = historyViewModel?.isEditing ?? false

        List {
            Section("Summary") {
                LabeledContent(
                    "Started",
                    value: displayedWorkout.startedAt.formatted(date: .abbreviated, time: .shortened)
                )
                if let completedAt = displayedWorkout.completedAt {
                    LabeledContent(
                        "Completed",
                        value: completedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if let duration = displayedWorkout.duration {
                    LabeledContent("Duration", value: formatDuration(duration))
                }
                LabeledContent("Total Volume", value: weightUnit.format(displayedWorkout.totalVolume, decimals: 0))
                LabeledContent("Exercises", value: "\(displayedWorkout.exercises.count)")
            }

            // Quality Score section
            if let vm = analyticsViewModel, vm.isFeatureUnlocked(.qualityScore) {
                Section("Quality Score") {
                    WorkoutQualityScoreView(viewModel: vm, workout: displayedWorkout)
                }
            }

            ForEach(displayedWorkout.exercises) { workoutExercise in
                Section(workoutExercise.exercise.name) {
                    if isEditing, let hvm = historyViewModel {
                        ForEach(Array(workoutExercise.sets.enumerated()), id: \.element.id) { index, exerciseSet in
                            SetRowGridView(
                                setNumber: index + 1,
                                exerciseSet: exerciseSet,
                                showRPE: workoutExercise.sets.contains { $0.rpe != nil },
                                weightUnit: hvm.userPreferencesService?.weightUnit ?? .kg,
                                onWeightChange: { weight in
                                    Task { await hvm.updateSetWeight(exerciseId: workoutExercise.id, setId: exerciseSet.id, weight: weight) }
                                },
                                onRepsChange: { reps in
                                    Task { await hvm.updateSetReps(exerciseId: workoutExercise.id, setId: exerciseSet.id, reps: reps) }
                                },
                                onRPEChange: { rpe in
                                    Task { await hvm.updateSetRPE(exerciseId: workoutExercise.id, setId: exerciseSet.id, rpe: rpe) }
                                },
                                onToggleComplete: {
                                    Task { await hvm.toggleSetCompletion(exerciseId: workoutExercise.id, setId: exerciseSet.id) }
                                },
                                onSetTypeChange: { setType in
                                    Task { await hvm.updateSetType(exerciseId: workoutExercise.id, setId: exerciseSet.id, setType: setType) }
                                }
                            )
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task { await hvm.addEmptySet(exerciseId: workoutExercise.id) }
                            } label: {
                                Label("Add Set", systemImage: "plus.circle")
                                    .font(.system(size: 13))
                            }

                            if !workoutExercise.sets.isEmpty {
                                Button(role: .destructive) {
                                    Task { await hvm.removeLastSet(exerciseId: workoutExercise.id) }
                                } label: {
                                    Label("Remove Last", systemImage: "minus.circle")
                                        .font(.system(size: 13))
                                }
                            }
                        }
                    } else {
                        ForEach(workoutExercise.sets) { exerciseSet in
                            SetRowView(
                                exerciseSet: exerciseSet,
                                weightUnit: historyViewModel?.userPreferencesService?.weightUnit ?? .kg
                            )
                        }
                    }

                    if workoutExercise.exerciseVolume > 0 {
                        LabeledContent("Exercise Volume") {
                            Text(weightUnit.format(workoutExercise.exerciseVolume, decimals: 0))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            if let notes = displayedWorkout.notes {
                Section("Notes") {
                    Text(notes)
                }
            }

            // Similar Workouts link
            if let vm = analyticsViewModel, vm.isFeatureUnlocked(.similarWorkouts) {
                Section {
                    NavigationLink {
                        SimilarWorkoutsView(viewModel: vm, workout: displayedWorkout)
                    } label: {
                        Label("Similar Workouts", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle(displayedWorkout.name)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .fontWeight(.semibold)
            }
            if let hvm = historyViewModel {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button(hvm.isEditing ? "Done" : "Edit") {
                            hvm.isEditing.toggle()
                        }
                        Button {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Workout",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let hvm = historyViewModel {
                    Task {
                        await hvm.deleteWorkout(workout)
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the workout and all its data.")
        }
        .onAppear {
            historyViewModel?.selectWorkout(workout)
        }
        .onDisappear {
            historyViewModel?.isEditing = false
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
