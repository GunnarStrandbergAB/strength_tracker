import SwiftUI
import StrengthTrackerShared

struct WorkoutDetailView: View {
    let workout: Workout
    var historyViewModel: HistoryViewModel? = nil
    var analyticsViewModel: WorkoutAnalyticsViewModel? = nil
    var exerciseListViewModel: ExerciseListViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var showingExercisePicker = false
    @State private var exerciseToRemove: WorkoutExercise? = nil

    /// The displayed workout: use historyViewModel's selectedWorkout (live edits) if available.
    private var displayedWorkout: Workout {
        historyViewModel?.selectedWorkout ?? workout
    }

    private var weightUnit: WeightUnit {
        historyViewModel?.userPreferencesService?.weightUnit ?? .kg
    }

    private var intensityMetric: IntensityMetric {
        historyViewModel?.userPreferencesService?.intensityMetric ?? .rpe
    }

    // Extracted from `body` — the callback bundle is too much for the SwiftUI
    // type-checker inline.
    @ViewBuilder
    private func editableSetRows(for workoutExercise: WorkoutExercise, hvm: HistoryViewModel) -> some View {
        let showIntensity = workoutExercise.sets.contains { set in
            set.rpe != nil || set.rir != nil || set.dropSets.contains { $0.rpe != nil || $0.rir != nil }
        }
        ForEach(Array(workoutExercise.sets.enumerated()), id: \.element.id) { index, exerciseSet in
            editableSetRow(
                index: index,
                exerciseSet: exerciseSet,
                workoutExercise: workoutExercise,
                showIntensity: showIntensity,
                hvm: hvm
            )
        }
    }

    private func editableSetRow(
        index: Int,
        exerciseSet: ExerciseSet,
        workoutExercise: WorkoutExercise,
        showIntensity: Bool,
        hvm: HistoryViewModel
    ) -> some View {
        let exerciseId = workoutExercise.id
        let setId = exerciseSet.id
        let metric = intensityMetric
        return SetRowGroupView(
            setNumber: index + 1,
            exerciseSet: exerciseSet,
            showIntensity: showIntensity,
            intensityMetric: metric,
            weightUnit: hvm.userPreferencesService?.weightUnit ?? .kg,
            onWeightChange: { weight in
                Task { await hvm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: weight) }
            },
            onRepsChange: { reps in
                Task { await hvm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: reps) }
            },
            onIntensityChange: { value in
                Task { await hvm.updateSetIntensity(exerciseId: exerciseId, setId: setId, value: value, metric: metric) }
            },
            onToggleComplete: {
                Task { await hvm.toggleSetCompletion(exerciseId: exerciseId, setId: setId) }
            },
            onSetTypeChange: { setType in
                Task { await hvm.updateSetType(exerciseId: exerciseId, setId: setId, setType: setType) }
            },
            onAddDropEntry: {
                Task { await hvm.addDropEntry(exerciseId: exerciseId, setId: setId) }
            },
            onToggleFailure: {
                Task { await hvm.toggleSetFailure(exerciseId: exerciseId, setId: setId) }
            },
            onDropEntryWeightChange: { entryId, weight in
                Task { await hvm.updateDropEntryWeight(exerciseId: exerciseId, setId: setId, entryId: entryId, weight: weight) }
            },
            onDropEntryRepsChange: { entryId, reps in
                Task { await hvm.updateDropEntryReps(exerciseId: exerciseId, setId: setId, entryId: entryId, reps: reps) }
            },
            onDropEntryIntensityChange: { entryId, value in
                Task { await hvm.updateDropEntryIntensity(exerciseId: exerciseId, setId: setId, entryId: entryId, value: value, metric: metric) }
            },
            onDropEntryToggleFailure: { entryId in
                Task { await hvm.toggleDropEntryFailure(exerciseId: exerciseId, setId: setId, entryId: entryId) }
            },
            onRemoveDropEntry: { entryId in
                Task { await hvm.removeDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) }
            }
        )
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
                        editableSetRows(for: workoutExercise, hvm: hvm)

                        // Multiple buttons in one List row need explicit .borderless
                        // styles — otherwise the row is one tap target and a tap on
                        // "Add Set" also fires the destructive trash action.
                        HStack(spacing: 12) {
                            Button {
                                Task { await hvm.addEmptySet(exerciseId: workoutExercise.id) }
                            } label: {
                                Label("Add Set", systemImage: "plus.circle")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.borderless)

                            if !workoutExercise.sets.isEmpty {
                                Button(role: .destructive) {
                                    Task { await hvm.removeLastSet(exerciseId: workoutExercise.id) }
                                } label: {
                                    Label("Remove Last", systemImage: "minus.circle")
                                        .font(.system(size: 13))
                                }
                                .buttonStyle(.borderless)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                exerciseToRemove = workoutExercise
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        ForEach(Array(workoutExercise.sets.enumerated()), id: \.element.id) { index, exerciseSet in
                            SetRowView(
                                exerciseSet: exerciseSet,
                                weightUnit: historyViewModel?.userPreferencesService?.weightUnit ?? .kg,
                                intensityMetric: intensityMetric,
                                setNumber: index + 1
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

            if isEditing, let hvm = historyViewModel {
                Section {
                    if exerciseListViewModel != nil {
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle")
                        }
                    }

                    if hasIncompleteSets {
                        Button {
                            Task { await hvm.markAllSetsComplete() }
                        } label: {
                            Label("Mark All Sets Complete", systemImage: "checkmark.circle")
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
                            if hvm.isEditing {
                                Task { await hvm.endEditing() }
                            } else {
                                hvm.isEditing = true
                            }
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
        .sheet(isPresented: $showingExercisePicker) {
            if let exerciseListViewModel, let hvm = historyViewModel {
                ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                    Task { await hvm.addExercise(exercise) }
                }
            }
        }
        .confirmationDialog(
            "Remove Exercise",
            isPresented: .init(
                get: { exerciseToRemove != nil },
                set: { if !$0 { exerciseToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove \(exerciseToRemove?.exercise.name ?? "Exercise")", role: .destructive) {
                if let target = exerciseToRemove, let hvm = historyViewModel {
                    Task { await hvm.removeExercise(exerciseId: target.id) }
                }
                exerciseToRemove = nil
            }
            Button("Cancel", role: .cancel) { exerciseToRemove = nil }
        } message: {
            Text("This removes the exercise and all its sets from this workout.")
        }
        .onAppear {
            historyViewModel?.selectWorkout(workout)
        }
        .onDisappear {
            if let hvm = historyViewModel, hvm.isEditing {
                Task { await hvm.endEditing() }
            }
        }
    }

    private var hasIncompleteSets: Bool {
        displayedWorkout.exercises.contains { $0.sets.contains { !$0.isCompleted } }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
