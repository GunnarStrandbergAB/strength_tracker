#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

// MARK: - Sheet Enum (Fix 1: single .sheet(item:) avoids nested-sheet bug)

private enum EditorSheet: Identifiable {
    case exercisePicker
    case exerciseConfig(Int)

    var id: String {
        switch self {
        case .exercisePicker: return "picker"
        case .exerciseConfig(let i): return "config-\(i)"
        }
    }
}

struct TemplateEditorView: View {
    @State private var viewModel: TemplateViewModel
    let exerciseListViewModel: ExerciseListViewModel
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate?

    @State private var name: String
    @State private var notes: String
    @State private var exercises: [TemplateExercise]
    @State private var activeSheet: EditorSheet? = nil

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
                            activeSheet = .exerciseConfig(index)
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
                        activeSheet = .exercisePicker
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .exercisePicker:
                    ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                        addExercise(exercise)
                        activeSheet = nil
                    }
                case .exerciseConfig(let index):
                    if exercises.indices.contains(index) {
                        TemplateExerciseConfigView(
                            templateExercise: exercises[index],
                            onSave: { updated in
                                exercises[index] = updated
                                activeSheet = nil
                            },
                            onCancel: {
                                activeSheet = nil
                            }
                        )
                    }
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
            targetWeight: exercise.exerciseType == .weightedReps || exercise.exerciseType == .bodyweightReps ? 0 : nil,
            targetDurationSeconds: exercise.exerciseType == .duration ? 60 : nil,
            targetDistanceMeters: exercise.exerciseType == .cardio || exercise.exerciseType == .weightedCardio ? 1000 : nil
        )
        exercises.append(templateExercise)
    }

    private func reorderExercises() {
        for index in exercises.indices {
            exercises[index].order = index
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

// MARK: - Row View

private struct TemplateExerciseEditorRowView: View {
    let templateExercise: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(templateExercise.exercise.name)
                .font(.body)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text("\(templateExercise.targetSets) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !templateExercise.setTargets.isEmpty {
                    Text("per-set targets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
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
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Config View (Fix 2d: per-set targets, Fix 3: keyboard dismiss)

private struct TemplateExerciseConfigView: View {
    let templateExercise: TemplateExercise
    let onSave: (TemplateExercise) -> Void
    let onCancel: () -> Void

    @State private var targetSets: Int
    @State private var setTargets: [TemplateSetTarget]
    @State private var notes: String
    @State private var restTimerSeconds: Int?
    @State private var supersetGroup: Int?

    private var exerciseType: ExerciseType { templateExercise.exercise.exerciseType }
    private var showsReps: Bool { exerciseType == .weightedReps || exerciseType == .bodyweightReps }
    private var showsWeight: Bool { exerciseType == .weightedReps || exerciseType == .bodyweightReps }
    private var showsDuration: Bool { exerciseType == .duration }
    private var showsDistance: Bool { exerciseType == .cardio || exerciseType == .weightedCardio }

    init(templateExercise: TemplateExercise, onSave: @escaping (TemplateExercise) -> Void, onCancel: @escaping () -> Void) {
        self.templateExercise = templateExercise
        self.onSave = onSave
        self.onCancel = onCancel

        let sets = templateExercise.targetSets
        self._targetSets = State(initialValue: sets)
        self._notes = State(initialValue: templateExercise.notes ?? "")
        self._restTimerSeconds = State(initialValue: templateExercise.restTimerSeconds)
        self._supersetGroup = State(initialValue: templateExercise.supersetGroup)

        // Build initial setTargets array: use existing per-set data or fill from flat values
        var targets: [TemplateSetTarget] = []
        for i in 0..<sets {
            if templateExercise.setTargets.indices.contains(i) {
                targets.append(templateExercise.setTargets[i])
            } else {
                targets.append(TemplateSetTarget(
                    order: i,
                    targetReps: templateExercise.targetReps,
                    targetWeight: templateExercise.targetWeight,
                    targetDurationSeconds: templateExercise.targetDurationSeconds,
                    targetDistanceMeters: templateExercise.targetDistanceMeters
                ))
            }
        }
        self._setTargets = State(initialValue: targets)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Text(templateExercise.exercise.name)
                        .font(.headline)
                }

                Section("Sets") {
                    Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...20)
                        .onChange(of: targetSets) { _, newCount in
                            adjustSetTargets(to: newCount)
                        }
                }

                Section("Per-Set Targets") {
                    ForEach(setTargets.indices, id: \.self) { i in
                        SetTargetRow(
                            index: i,
                            target: $setTargets[i],
                            showsReps: showsReps,
                            showsWeight: showsWeight,
                            showsDuration: showsDuration,
                            showsDistance: showsDistance
                        )
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
                        saveExercise()
                    }
                }
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
            }
        }
    }

    private func adjustSetTargets(to newCount: Int) {
        while setTargets.count < newCount {
            let last = setTargets.last
            setTargets.append(TemplateSetTarget(
                order: setTargets.count,
                targetReps: last?.targetReps,
                targetWeight: last?.targetWeight,
                targetDurationSeconds: last?.targetDurationSeconds,
                targetDistanceMeters: last?.targetDistanceMeters
            ))
        }
        while setTargets.count > newCount {
            setTargets.removeLast()
        }
    }

    private func saveExercise() {
        // Re-number orders
        var orderedTargets = setTargets
        for i in orderedTargets.indices {
            orderedTargets[i].order = i
        }

        // Derive flat fallback values from the first set target
        let first = orderedTargets.first

        let updated = TemplateExercise(
            id: templateExercise.id,
            exercise: templateExercise.exercise,
            order: templateExercise.order,
            supersetGroup: supersetGroup,
            notes: notes.isEmpty ? nil : notes,
            restTimerSeconds: restTimerSeconds,
            targetSets: targetSets,
            targetReps: first?.targetReps,
            targetWeight: first?.targetWeight,
            targetDurationSeconds: first?.targetDurationSeconds,
            targetDistanceMeters: first?.targetDistanceMeters,
            setTargets: orderedTargets
        )
        onSave(updated)
    }
}

// MARK: - Per-Set Target Row

private struct SetTargetRow: View {
    let index: Int
    @Binding var target: TemplateSetTarget
    let showsReps: Bool
    let showsWeight: Bool
    let showsDuration: Bool
    let showsDistance: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(index + 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            if showsReps {
                TextField("Reps", value: $target.targetReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsWeight {
                TextField("kg", value: $target.targetWeight, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsDuration {
                TextField("Sec", value: $target.targetDurationSeconds, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("sec")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsDistance {
                TextField("m", value: $target.targetDistanceMeters, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#endif
