import SwiftUI
import StrengthTrackerShared

struct WorkoutDetailView: View {
    let workout: Workout
    var historyViewModel: HistoryViewModel? = nil
    var analyticsViewModel: WorkoutAnalyticsViewModel? = nil
    var exerciseListViewModel: ExerciseListViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var inputEdits = WorkoutInputQueue()
    @State private var showingExercisePicker = false
    @State private var exerciseToRemove: WorkoutExercise? = nil
    @State private var exerciseToReplace: WorkoutExercise? = nil
    /// Per-exercise intensity-column override keyed by WorkoutExercise.id.
    /// Absent = derive from setting/data; present = explicit user choice.
    @State private var intensityOverrides: [UUID: Bool] = [:]

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

    private var bodyWeightKg: Double {
        historyViewModel?.displayBodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    /// "Always show intensity" — kept under the historical name (same setting as the active workout).
    private var alwaysShowRPE: Bool {
        historyViewModel?.userPreferencesService?.alwaysShowRPE ?? false
    }

    /// Mirrors ExerciseCardView: an explicit per-exercise toggle wins, otherwise
    /// the column shows when the setting is on or any set/segment already has data.
    private func showsIntensity(for workoutExercise: WorkoutExercise) -> Bool {
        if let override = intensityOverrides[workoutExercise.id] { return override }
        return alwaysShowRPE || workoutExercise.sets.contains { set in
            set.rpe != nil || set.rir != nil || set.dropSets.contains { $0.rpe != nil || $0.rir != nil }
        }
    }

    // Extracted from `body` — the callback bundle is too much for the SwiftUI
    // type-checker inline.
    @ViewBuilder
    private func editableSetRows(for workoutExercise: WorkoutExercise, hvm: HistoryViewModel) -> some View {
        let showIntensity = showsIntensity(for: workoutExercise)
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
            weightLabel: workoutExercise.exercise.exerciseType == .bodyweightReps ? "+\(weightUnit.symbol)" : weightUnit.symbol,
            onWeightChange: { weight in
                inputEdits.enqueue { await hvm.updateSetWeight(exerciseId: exerciseId, setId: setId, weight: weight) }
            },
            onRepsChange: { reps in
                inputEdits.enqueue { await hvm.updateSetReps(exerciseId: exerciseId, setId: setId, reps: reps) }
            },
            onIntensityChange: { value in
                inputEdits.enqueue { await hvm.updateSetIntensity(exerciseId: exerciseId, setId: setId, value: value, metric: metric) }
            },
            onToggleComplete: {
                inputEdits.enqueue { await hvm.toggleSetCompletion(exerciseId: exerciseId, setId: setId) }
            },
            onSetTypeChange: { setType in
                inputEdits.enqueue { await hvm.updateSetType(exerciseId: exerciseId, setId: setId, setType: setType) }
            },
            onAddDropEntry: {
                inputEdits.enqueue { await hvm.addDropEntry(exerciseId: exerciseId, setId: setId) }
            },
            onToggleFailure: {
                inputEdits.enqueue { await hvm.toggleSetFailure(exerciseId: exerciseId, setId: setId) }
            },
            onDropEntryWeightChange: { entryId, weight in
                inputEdits.enqueue { await hvm.updateDropEntryWeight(exerciseId: exerciseId, setId: setId, entryId: entryId, weight: weight) }
            },
            onDropEntryRepsChange: { entryId, reps in
                inputEdits.enqueue { await hvm.updateDropEntryReps(exerciseId: exerciseId, setId: setId, entryId: entryId, reps: reps) }
            },
            onDropEntryIntensityChange: { entryId, value in
                inputEdits.enqueue { await hvm.updateDropEntryIntensity(exerciseId: exerciseId, setId: setId, entryId: entryId, value: value, metric: metric) }
            },
            onDropEntryToggleFailure: { entryId in
                inputEdits.enqueue { await hvm.toggleDropEntryFailure(exerciseId: exerciseId, setId: setId, entryId: entryId) }
            },
            onRemoveDropEntry: { entryId in
                inputEdits.enqueue { await hvm.removeDropEntry(exerciseId: exerciseId, setId: setId, entryId: entryId) }
            }
        )
    }

    /// Multiple buttons in one List row need explicit .borderless styles —
    /// otherwise the row is one tap target and a tap on "Add Set" also fires
    /// the destructive trash action.
    @ViewBuilder
    private func exerciseActionRow(for workoutExercise: WorkoutExercise, hvm: HistoryViewModel) -> some View {
        let intensityShown = showsIntensity(for: workoutExercise)
        HStack(spacing: 12) {
            Button {
                guard STNumericTextField.commitActiveInput() else { return }
                inputEdits.enqueue { await hvm.addEmptySet(exerciseId: workoutExercise.id) }
            } label: {
                Label("Add Set", systemImage: "plus.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)

            if !workoutExercise.sets.isEmpty {
                Button(role: .destructive) {
                    guard STNumericTextField.commitActiveInput() else { return }
                    inputEdits.enqueue { await hvm.removeLastSet(exerciseId: workoutExercise.id) }
                } label: {
                    Label("Remove Last", systemImage: "minus.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button {
                guard STNumericTextField.commitActiveInput() else { return }
                intensityOverrides[workoutExercise.id] = !intensityShown
            } label: {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 13))
                    .foregroundStyle(intensityShown ? Color.blue : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(intensityShown
                ? "Hide \(intensityMetric.displayName)"
                : "Show \(intensityMetric.displayName)")

            if exerciseListViewModel != nil {
                Button {
                    guard STNumericTextField.commitActiveInput() else { return }
                    exerciseToReplace = workoutExercise
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Change Exercise")
            }

            Button(role: .destructive) {
                guard STNumericTextField.commitActiveInput() else { return }
                exerciseToRemove = workoutExercise
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
        }
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
                LabeledContent("Total Volume", value: weightUnit.format(displayedWorkout.totalVolume(bodyWeightKg: bodyWeightKg), decimals: 0))
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
                        exerciseActionRow(for: workoutExercise, hvm: hvm)
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

                    if workoutExercise.exerciseVolume(bodyWeightKg: bodyWeightKg) > 0 {
                        LabeledContent("Exercise Volume") {
                            Text(weightUnit.format(workoutExercise.exerciseVolume(bodyWeightKg: bodyWeightKg), decimals: 0))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            if isEditing, let hvm = historyViewModel {
                Section {
                    if exerciseListViewModel != nil {
                        Button {
                            guard STNumericTextField.commitActiveInput() else { return }
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
            if let hvm = historyViewModel {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button(hvm.isEditing ? "Done" : "Edit") {
                            if hvm.isEditing {
                                guard STNumericTextField.commitActiveInput() else { return }
                                Task {
                                    await inputEdits.drain()
                                    await hvm.endEditing()
                                    // The finalizer bumped the data revision, which
                                    // reloads every analytics view; refresh this
                                    // workout's score for the section below.
                                    if let workout = hvm.selectedWorkout {
                                        await analyticsViewModel?.loadQualityScore(for: workout)
                                    }
                                }
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
                        STNumericTextField.commitActiveInput()
                        await inputEdits.drain()
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
                    inputEdits.enqueue { await hvm.addExercise(exercise) }
                }
            }
        }
        .sheet(item: $exerciseToReplace) { target in
            if let exerciseListViewModel, let hvm = historyViewModel {
                ExercisePickerView(viewModel: exerciseListViewModel, title: "Change Exercise") { exercise in
                    inputEdits.enqueue { await hvm.replaceExercise(exerciseId: target.id, with: exercise) }
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
                    inputEdits.enqueue { await hvm.removeExercise(exerciseId: target.id) }
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
                STNumericTextField.commitActiveInput()
                Task {
                    await inputEdits.drain()
                    await hvm.endEditing()
                }
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
