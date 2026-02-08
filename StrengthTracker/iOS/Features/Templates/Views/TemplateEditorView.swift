#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct TemplateEditorView: View {
    @State private var viewModel: TemplateViewModel
    let exerciseListViewModel: ExerciseListViewModel
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate?

    @State private var name: String
    @State private var notes: String
    @State private var exercises: [TemplateExercise]
    @State private var showingExercisePicker = false
    @State private var editingExerciseIndex: Int? = nil

    init(viewModel: TemplateViewModel, exerciseListViewModel: ExerciseListViewModel, template: WorkoutTemplate?) {
        self._viewModel = State(initialValue: viewModel)
        self.exerciseListViewModel = exerciseListViewModel
        self.template = template
        self._name = State(initialValue: template?.name ?? "")
        self._notes = State(initialValue: template?.notes ?? "")
        self._exercises = State(initialValue: template?.exercises ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Info") {
                    TextField("Name", text: $name)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section {
                    ForEach(exercises.indices, id: \.self) { index in
                        Button {
                            editingExerciseIndex = index
                        } label: {
                            TemplateExerciseEditorRowView(templateExercise: exercises[index])
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { indexSet in
                        exercises.remove(atOffsets: indexSet)
                        reorderExercises()
                    }
                    .onMove { source, destination in
                        exercises.move(fromOffsets: source, toOffset: destination)
                        reorderExercises()
                    }

                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    if exercises.isEmpty {
                        Text("Add exercises to this template")
                    }
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveTemplate()
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || exercises.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                    addExercise(exercise)
                    showingExercisePicker = false
                }
            }
            .sheet(item: $editingExerciseIndex) { index in
                if exercises.indices.contains(index) {
                    TemplateExerciseConfigView(
                        templateExercise: exercises[index],
                        onSave: { updated in
                            exercises[index] = updated
                            editingExerciseIndex = nil
                        },
                        onCancel: {
                            editingExerciseIndex = nil
                        }
                    )
                }
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let templateExercise = TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: exercises.count,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            targetSets: 3,
            targetReps: exercise.exerciseType == .weightedReps || exercise.exerciseType == .bodyweightReps ? 10 : nil,
            targetWeight: exercise.exerciseType == .weightedReps ? 0 : nil,
            targetDurationSeconds: exercise.exerciseType == .duration ? 60 : nil,
            targetDistanceMeters: exercise.exerciseType == .cardio || exercise.exerciseType == .weightedCardio ? 1000 : nil
        )
        exercises.append(templateExercise)
    }

    private func reorderExercises() {
        for (index, _) in exercises.enumerated() {
            exercises[index] = TemplateExercise(
                id: exercises[index].id,
                exercise: exercises[index].exercise,
                order: index,
                supersetGroup: exercises[index].supersetGroup,
                notes: exercises[index].notes,
                restTimerSeconds: exercises[index].restTimerSeconds,
                targetSets: exercises[index].targetSets,
                targetReps: exercises[index].targetReps,
                targetWeight: exercises[index].targetWeight,
                targetDurationSeconds: exercises[index].targetDurationSeconds,
                targetDistanceMeters: exercises[index].targetDistanceMeters
            )
        }
    }

    private func saveTemplate() async {
        let updatedTemplate = WorkoutTemplate(
            id: template?.id ?? UUID(),
            name: name,
            notes: notes.isEmpty ? nil : notes,
            sortOrder: template?.sortOrder ?? viewModel.templates.count,
            lastUsedAt: template?.lastUsedAt,
            timesUsed: template?.timesUsed ?? 0,
            exercises: exercises
        )
        await viewModel.saveTemplate(updatedTemplate)
    }
}

private struct TemplateExerciseEditorRowView: View {
    let templateExercise: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(templateExercise.exercise.name)
                .font(.body)

            HStack(spacing: 8) {
                Text("\(templateExercise.targetSets) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reps = templateExercise.targetReps {
                    Text("\(reps) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let weight = templateExercise.targetWeight {
                    Text("\(weight, specifier: "%.1f") kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TemplateExerciseConfigView: View {
    let templateExercise: TemplateExercise
    let onSave: (TemplateExercise) -> Void
    let onCancel: () -> Void

    @State private var targetSets: Int
    @State private var targetReps: Int?
    @State private var targetWeight: Double?
    @State private var targetDurationSeconds: Int?
    @State private var targetDistanceMeters: Double?
    @State private var notes: String
    @State private var restTimerSeconds: Int?
    @State private var supersetGroup: Int?

    init(templateExercise: TemplateExercise, onSave: @escaping (TemplateExercise) -> Void, onCancel: @escaping () -> Void) {
        self.templateExercise = templateExercise
        self.onSave = onSave
        self.onCancel = onCancel

        self._targetSets = State(initialValue: templateExercise.targetSets)
        self._targetReps = State(initialValue: templateExercise.targetReps)
        self._targetWeight = State(initialValue: templateExercise.targetWeight)
        self._targetDurationSeconds = State(initialValue: templateExercise.targetDurationSeconds)
        self._targetDistanceMeters = State(initialValue: templateExercise.targetDistanceMeters)
        self._notes = State(initialValue: templateExercise.notes ?? "")
        self._restTimerSeconds = State(initialValue: templateExercise.restTimerSeconds)
        self._supersetGroup = State(initialValue: templateExercise.supersetGroup)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Text(templateExercise.exercise.name)
                        .font(.headline)
                }

                Section("Targets") {
                    Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...20)

                    if templateExercise.exercise.exerciseType == .weightedReps || templateExercise.exercise.exerciseType == .bodyweightReps {
                        HStack {
                            Text("Reps")
                            Spacer()
                            TextField("Reps", value: $targetReps, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    if templateExercise.exercise.exerciseType == .weightedReps {
                        HStack {
                            Text("Weight (kg)")
                            Spacer()
                            TextField("Weight", value: $targetWeight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    if templateExercise.exercise.exerciseType == .duration {
                        HStack {
                            Text("Duration (seconds)")
                            Spacer()
                            TextField("Duration", value: $targetDurationSeconds, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    if templateExercise.exercise.exerciseType == .cardio || templateExercise.exercise.exerciseType == .weightedCardio {
                        HStack {
                            Text("Distance (meters)")
                            Spacer()
                            TextField("Distance", value: $targetDistanceMeters, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                Section("Optional") {
                    HStack {
                        Text("Rest Timer (seconds)")
                        Spacer()
                        TextField("Rest", value: $restTimerSeconds, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Superset Group")
                        Spacer()
                        TextField("Group", value: $supersetGroup, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("Configure Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = TemplateExercise(
                            id: templateExercise.id,
                            exercise: templateExercise.exercise,
                            order: templateExercise.order,
                            supersetGroup: supersetGroup,
                            notes: notes.isEmpty ? nil : notes,
                            restTimerSeconds: restTimerSeconds,
                            targetSets: targetSets,
                            targetReps: targetReps,
                            targetWeight: targetWeight,
                            targetDurationSeconds: targetDurationSeconds,
                            targetDistanceMeters: targetDistanceMeters
                        )
                        onSave(updated)
                    }
                }
            }
        }
    }
}

// Extension to make Int identifiable for sheet presentation
extension Int: Identifiable {
    public var id: Int { self }
}
#endif
