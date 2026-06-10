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
    let workoutViewModel: WorkoutViewModel?
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate?

    @State private var name: String
    @State private var notes: String
    @State private var exercises: [TemplateExercise]
    @State private var activeSheet: EditorSheet? = nil
    @State private var showingUpdateActiveWorkout = false
    @State private var savedTemplate: WorkoutTemplate? = nil

    init(viewModel: TemplateViewModel, exerciseListViewModel: ExerciseListViewModel, template: WorkoutTemplate?, workoutViewModel: WorkoutViewModel? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.exerciseListViewModel = exerciseListViewModel
        self.workoutViewModel = workoutViewModel
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
                            TemplateExerciseEditorRowView(templateExercise: exercises[index], weightUnit: viewModel.weightUnit)
                        }
                        .buttonStyle(.plain)
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
                            let built = buildTemplate()
                            await viewModel.saveTemplate(built)
                            if let tid = template?.id, workoutViewModel?.activeWorkoutUsesTemplate(tid) == true {
                                savedTemplate = built
                                showingUpdateActiveWorkout = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.isEmpty || exercises.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(exercises.isEmpty)
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
            .alert("Update Active Workout?", isPresented: $showingUpdateActiveWorkout) {
                Button("Update Remaining Sets") {
                    Task {
                        if let t = savedTemplate { await workoutViewModel?.updateUncompletedSetsFromTemplate(t) }
                        dismiss()
                    }
                }
                Button("Keep Current Values", role: .cancel) { dismiss() }
            } message: {
                Text("Update uncompleted sets to match the new template values?")
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
                            weightUnit: viewModel.weightUnit,
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
            targetReps: exercise.exerciseType == .weightedReps || exercise.exerciseType == .bodyweightReps ? UserPreferencesService().defaultReps : nil,
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

    private func buildTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            id: template?.id ?? UUID(),
            name: name,
            notes: notes.isEmpty ? nil : notes,
            sortOrder: template?.sortOrder ?? viewModel.templates.count,
            lastUsedAt: template?.lastUsedAt,
            timesUsed: template?.timesUsed ?? 0,
            exercises: exercises
        )
    }
}

// MARK: - Row View

private struct TemplateExerciseEditorRowView: View {
    let templateExercise: TemplateExercise
    var weightUnit: WeightUnit = .kg

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(templateExercise.exercise.name)
                    .font(.body)
                    .foregroundStyle(.primary)

                if templateExercise.isWarmUp {
                    Text("Warm-up")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                }
            }

            Text(targetsSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var targetsSummary: String {
        compactTargetSummary(for: templateExercise, weightUnit: weightUnit)
    }
}

// MARK: - Config View (Fix 2d: per-set targets, Fix 3: keyboard dismiss)

private struct TemplateExerciseConfigView: View {
    let templateExercise: TemplateExercise
    let weightUnit: WeightUnit
    let onSave: (TemplateExercise) -> Void
    let onCancel: () -> Void

    @State private var targetSets: Int
    @State private var setTargets: [TemplateSetTarget]
    @State private var notes: String
    @State private var restTimerSeconds: Int?
    @State private var supersetGroup: Int?
    @State private var isWarmUp: Bool

    private var exerciseType: ExerciseType { templateExercise.exercise.exerciseType }
    private var showsReps: Bool { exerciseType == .weightedReps || exerciseType == .bodyweightReps }
    private var showsWeight: Bool { exerciseType == .weightedReps || exerciseType == .bodyweightReps }
    private var showsDuration: Bool { exerciseType == .duration }
    private var showsDistance: Bool { exerciseType == .cardio || exerciseType == .weightedCardio }

    init(templateExercise: TemplateExercise, weightUnit: WeightUnit = .kg, onSave: @escaping (TemplateExercise) -> Void, onCancel: @escaping () -> Void) {
        self.templateExercise = templateExercise
        self.weightUnit = weightUnit
        self.onSave = onSave
        self.onCancel = onCancel

        let sets = templateExercise.targetSets
        self._targetSets = State(initialValue: sets)
        self._notes = State(initialValue: templateExercise.notes ?? "")
        self._restTimerSeconds = State(initialValue: templateExercise.restTimerSeconds)
        self._supersetGroup = State(initialValue: templateExercise.supersetGroup)
        self._isWarmUp = State(initialValue: templateExercise.isWarmUp)

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
                            showsDistance: showsDistance,
                            weightUnit: weightUnit
                        )
                    }
                }

                Section("Optional") {
                    Toggle("Warm-up Exercise", isOn: $isWarmUp)
                        .onChange(of: isWarmUp) { _, newValue in
                            let newType: SetType = newValue ? .warmup : .normal
                            for i in setTargets.indices {
                                setTargets[i].setType = newType
                            }
                        }

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
                targetDistanceMeters: last?.targetDistanceMeters,
                setType: last?.setType ?? .normal
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
            setTargets: orderedTargets,
            isWarmUp: isWarmUp
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
    let weightUnit: WeightUnit

    @State private var repsText: String
    @State private var weightText: String
    @State private var durationText: String
    @State private var distanceText: String

    init(index: Int, target: Binding<TemplateSetTarget>, showsReps: Bool, showsWeight: Bool, showsDuration: Bool, showsDistance: Bool, weightUnit: WeightUnit = .kg) {
        self.index = index
        self._target = target
        self.showsReps = showsReps
        self.showsWeight = showsWeight
        self.showsDuration = showsDuration
        self.showsDistance = showsDistance
        self.weightUnit = weightUnit
        let t = target.wrappedValue
        _repsText = State(initialValue: t.targetReps.map { String($0) } ?? "")
        _weightText = State(initialValue: t.targetWeight.map { weightUnit.formatValue($0) } ?? "")
        _durationText = State(initialValue: t.targetDurationSeconds.map { String($0) } ?? "")
        _distanceText = State(initialValue: t.targetDistanceMeters.map { String(format: "%g", $0) } ?? "")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(index + 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            if showsReps {
                TextField("Reps", text: $repsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onChange(of: repsText) { _, newValue in
                        target.targetReps = Int(newValue)
                    }
                Text("reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsWeight {
                TextField(weightUnit.symbol, text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onChange(of: weightText) { _, newValue in
                        target.targetWeight = Double(newValue).map { weightUnit.toKg($0) }
                    }
                Text(weightUnit.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsDuration {
                TextField("Sec", text: $durationText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onChange(of: durationText) { _, newValue in
                        target.targetDurationSeconds = Int(newValue)
                    }
                Text("sec")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showsDistance {
                TextField("m", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onChange(of: distanceText) { _, newValue in
                        target.targetDistanceMeters = Double(newValue)
                    }
                Text("m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(SetType.allCases, id: \.self) { type in
                    Button {
                        target.setType = type
                    } label: {
                        if target.setType == type {
                            Label(type.displayName, systemImage: "checkmark")
                        } else {
                            Text(type.displayName)
                        }
                    }
                }
            } label: {
                Text(setTypeBadge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(setTypeBadgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(setTypeBadgeColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var setTypeBadge: String {
        switch target.setType {
        case .normal: return "N"
        case .warmup: return "W"
        case .dropset: return "D"
        case .failure: return "F"
        case .restPause: return "R"
        }
    }

    private var setTypeBadgeColor: Color {
        switch target.setType {
        case .normal: return .secondary
        case .warmup: return .orange
        case .dropset: return .purple
        case .failure: return .red
        case .restPause: return .blue
        }
    }
}

// MARK: - Compact Target Summary

private func compactTargetSummary(for te: TemplateExercise, weightUnit: WeightUnit = .kg) -> String {
    let targets = te.setTargets
    let sets = te.targetSets

    // Use flat values when no per-set targets
    guard !targets.isEmpty else {
        var parts: [String] = ["\(sets) sets"]
        if let reps = te.targetReps { parts.append("\(reps) reps") }
        if let w = te.targetWeight { parts.append(weightUnit.format(w)) }
        if let d = te.targetDurationSeconds { parts.append("\(d)s") }
        if let dist = te.targetDistanceMeters { parts.append("\(Int(dist))m") }
        return parts.joined(separator: " \u{00B7} ")
    }

    let weights = targets.compactMap(\.targetWeight)
    let reps = targets.compactMap(\.targetReps)
    let durations = targets.compactMap(\.targetDurationSeconds)
    let distances = targets.compactMap(\.targetDistanceMeters)

    var result = "\(sets)"

    // Reps portion
    if !reps.isEmpty {
        let allSame = Set(reps).count == 1
        let repsStr = allSame ? "\(reps[0])" : reps.map { String($0) }.joined(separator: "/")
        result += "\u{00D7}\(repsStr)"
    }

    // Weight portion
    if !weights.isEmpty {
        let allSame = Set(weights).count == 1
        let wStr = allSame ? weightUnit.formatValue(weights[0]) : weights.map { weightUnit.formatValue($0) }.joined(separator: "/")
        result += " @ \(wStr) \(weightUnit.symbol)"
    }

    // Duration
    if !durations.isEmpty && weights.isEmpty {
        let allSame = Set(durations).count == 1
        let dStr = allSame ? "\(durations[0])" : durations.map { String($0) }.joined(separator: "/")
        result += " \u{00D7} \(dStr)s"
    }

    // Distance
    if !distances.isEmpty && weights.isEmpty {
        let allSame = Set(distances).count == 1
        let distStr = allSame ? "\(Int(distances[0]))" : distances.map { String(Int($0)) }.joined(separator: "/")
        result += " \u{00D7} \(distStr)m"
    }

    return result
}

#endif
