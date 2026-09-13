#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// How the exercise form is being used: blank creation, a pre-filled copy that
/// becomes a new independent variant (own PRs/history — for "my gym's machine
/// is different"), or editing an existing custom exercise in place.
enum ExerciseFormMode {
    case create
    case duplicate(of: Exercise)
    case edit(Exercise)

    var sourceExercise: Exercise? {
        switch self {
        case .create: return nil
        case .duplicate(let exercise), .edit(let exercise): return exercise
        }
    }

    var isEdit: Bool {
        if case .edit = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .create: return "New Exercise"
        case .duplicate: return "New Variant"
        case .edit: return "Edit Exercise"
        }
    }
}

struct AddExerciseView: View {
    let viewModel: ExerciseListViewModel
    let mode: ExerciseFormMode
    var personalRecordService: PersonalRecordService? = nil
    var weightUnit: WeightUnit = .kg
    var onExerciseCreated: ((Exercise) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var name = ""
    @State private var primaryMuscleGroup: MuscleGroup = .chest
    @State private var category: ExerciseCategory = .barbell
    @State private var exerciseType: ExerciseType = .weightedReps
    @State private var secondaryMuscleGroups: Set<MuscleGroup> = []
    @State private var instructions = ""
    @State private var known1RM = ""
    @State private var bodyweightPercent = ""
    @State private var equipmentBrand = ""
    @State private var loadingType: LoadingType? = nil
    @State private var weightRecording = WeightRecording()
    @State private var recordingConfirmed = false

    init(
        viewModel: ExerciseListViewModel,
        mode: ExerciseFormMode = .create,
        personalRecordService: PersonalRecordService? = nil,
        weightUnit: WeightUnit = .kg,
        onExerciseCreated: ((Exercise) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.mode = mode
        self.personalRecordService = personalRecordService
        self.weightUnit = weightUnit
        self.onExerciseCreated = onExerciseCreated
        if let source = mode.sourceExercise {
            _name = State(initialValue: source.name)
            _primaryMuscleGroup = State(initialValue: source.primaryMuscleGroup)
            _category = State(initialValue: source.category)
            _exerciseType = State(initialValue: source.exerciseType)
            _secondaryMuscleGroups = State(initialValue: Set(source.secondaryMuscleGroups))
            _instructions = State(initialValue: source.instructions ?? "")
            if source.exerciseType == .bodyweightReps {
                let factor = source.resolvedBodyweightFactor
                _bodyweightPercent = State(initialValue: String(format: "%g", factor * 100))
            }
            _equipmentBrand = State(initialValue: source.equipmentBrand ?? "")
            _loadingType = State(initialValue: source.loadingType)
            _weightRecording = State(initialValue: source.weightRecording ?? DumbbellDefaults.recording(for: source.name) ?? WeightRecording())
            _recordingConfirmed = State(initialValue: source.weightRecording != nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Exercise name", text: $name)
                }

                Section("Details") {
                    Picker("Muscle Group", selection: $primaryMuscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { group in
                            Text(group.rawValue.localizedCapitalized)
                                .tag(group)
                        }
                    }

                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases, id: \.self) { cat in
                            Text(cat.displayName)
                                .tag(cat)
                        }
                    }

                    Picker("Type", selection: $exerciseType) {
                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            Text(type.rawValue.localizedCapitalized)
                                .tag(type)
                        }
                    }
                }

                if exerciseType == .bodyweightReps {
                    BodyweightPercentageFields(text: $bodyweightPercent)
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if category == .dumbbell {
                    Section("Weight logging") {
                        Toggle("Confirm how weights and reps are entered", isOn: $recordingConfirmed)
                        if recordingConfirmed { WeightRecordingFields(value: $weightRecording) }
                        Text("Applies to this exercise's future uses. Existing workouts and template targets retain their convention; review them in Settings → Weight logging.").font(.caption)
                    }
                }
                if showsBrandField {
                    Section {
                        TextField("Brand (e.g. Hammer Strength)", text: $equipmentBrand)
                        if showsLoadingPicker {
                            Picker("Loading", selection: $loadingType) {
                                Text("Not specified").tag(LoadingType?.none)
                                ForEach(LoadingType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(LoadingType?.some(type))
                                }
                            }
                        }
                    } header: {
                        Text("Equipment (optional)")
                    } footer: {
                        Text("The same movement on different machines can take very different weights — note the brand or loading style to tell your variants apart.")
                    }
                }

                Section("Secondary Muscle Groups (optional)") {
                    ForEach(MuscleGroup.allCases.filter { $0 != primaryMuscleGroup }, id: \.self) { group in
                        Button {
                            if secondaryMuscleGroups.contains(group) {
                                secondaryMuscleGroups.remove(group)
                            } else {
                                secondaryMuscleGroups.insert(group)
                            }
                        } label: {
                            HStack {
                                Text(group.rawValue.localizedCapitalized)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if secondaryMuscleGroups.contains(group) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Instructions (optional)") {
                    TextField("How to perform this exercise", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }

                if personalRecordService != nil && !mode.isEdit {
                    Section("Known 1RM (optional)") {
                        HStack {
                            TextField("e.g. 100", text: $known1RM)
                                .keyboardType(.decimalPad)
                            Text(category == .dumbbell && recordingConfirmed ? weightRecording.weightLabel(weightUnit) : weightUnit.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onChange(of: primaryMuscleGroup) { _, newValue in
                secondaryMuscleGroups.remove(newValue)
            }
            .interactiveDismissDisabled(isSaving)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Edit keeps the same identity (PRs/history stay attached);
                        // create/duplicate mint a new independent exercise.
                        let existing = mode.isEdit ? mode.sourceExercise : nil
                        guard let exercise = try? ExerciseFactory.makeCustom(
                            id: existing?.id ?? UUID(),
                            name: name,
                            primaryMuscleGroup: primaryMuscleGroup,
                            secondaryMuscleGroups: Array(secondaryMuscleGroups),
                            category: category,
                            exerciseType: exerciseType,
                            instructions: instructions.isEmpty ? nil : instructions,
                            bodyweightPercent: try? BodyweightPercentage.parse(bodyweightPercent),
                            equipmentBrand: equipmentBrand,
                            loadingType: loadingType,
                            weightRecording: recordingConfirmed && category == .dumbbell ? weightRecording : nil,
                            isArchived: existing?.isArchived ?? false
                        ) else { return }
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            guard await viewModel.saveExercise(exercise) else { return }
                            if !mode.isEdit, let value = Double(known1RM), value > 0, let prService = personalRecordService {
                                let record = PersonalRecord(
                                    id: UUID(),
                                    exerciseId: exercise.id,
                                    recordType: .estimatedOneRepMax,
                                    value: weightUnit.toKg(value),
                                    setId: nil,
                                    achievedAt: Date(),
                                    weightRecordingKey: exercise.personalRecordConvention
                                )
                                _ = try? await prService.saveManualRecord(record)
                            }
                            onExerciseCreated?(exercise)
                            dismiss()
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || (exerciseType == .bodyweightReps && !BodyweightPercentageFields.isValid(bodyweightPercent)))
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

    private var showsBrandField: Bool {
        ExerciseFactory.showsBrandField(for: category)
    }

    private var showsLoadingPicker: Bool {
        ExerciseFactory.showsLoadingPicker(for: category)
    }
}
/// Used in creation and the reviewed historical correction flow.
struct WeightRecordingFields: View {
    @Binding var value: WeightRecording
    var body: some View {
        choice("Dumbbells moving per repetition", selection: $value.equipment, options: WeightRecording.Equipment.allCases) { $0.title }
        choice("Weight entry", selection: $value.weightEntry, options: WeightRecording.WeightEntry.allCases) { $0.title }
        choice("Repetition entry", selection: $value.repetitions, options: WeightRecording.Repetitions.allCases) { $0.title }
        Text(value.explanation).font(.caption).foregroundStyle(.secondary)
        Text("For alternating curls, choose one dumbbell per repetition. For lunges holding two, choose two. Choose per-side reps only when one row covers both sides.")
            .font(.caption).foregroundStyle(.secondary)
    }
    private func choice<T: Hashable>(_ title: String, selection: Binding<T>, options: [T], label: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Menu {
                Picker(title, selection: selection) {
                    ForEach(options, id: \.self) { Text(label($0)).tag($0) }
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(label(selection.wrappedValue)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.tint(STColors.primary)
        }
    }
}

struct WeightRecordingEditorSheet: View {
    let exercise: Exercise
    let save: (WeightRecording) -> Void
    @State private var value: WeightRecording
    @Environment(\.dismiss) private var dismiss
    init(exercise: Exercise, save: @escaping (WeightRecording) -> Void) {
        self.exercise = exercise; self.save = save
        _value = State(initialValue: exercise.weightRecording ?? DumbbellDefaults.recording(for: exercise.name) ?? WeightRecording())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(exercise.name) { WeightRecordingFields(value: $value) }
                Section { Text("Applies to every set in this exercise entry, including drop segments. Entered numbers stay the same; this clarifies what they mean. Use Settings to review other workouts.") }
            }.navigationTitle("Weight logging").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { save(value); dismiss() } }
            }
        }.preferredColorScheme(.dark)
    }
}
/// Shared by custom creation/editing and the built-in exercise setting.
struct BodyweightPercentageFields: View {
    @Binding var text: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var placeholder = "100"
    var emptyValueDescription = "Leave blank to use 100%."
    static func isValid(_ text: String) -> Bool {
        do { _ = try BodyweightPercentage.parse(text); return true }
        catch { return false }
    }
    var body: some View {
        Section {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Percentage")
                    percentageInput
                }
            } else {
                HStack {
                    Text("Percentage")
                    percentageInput
                }
            }
            if !Self.isValid(text) {
                Text("Enter a percentage between 10 and 150.").foregroundStyle(.red)
            }
        } header: {
            Text("Bodyweight contribution")
        } footer: {
            Text("An estimate of the bodyweight moved per rep. Enter only additional weight when logging; the bodyweight contribution is added automatically. \(emptyValueDescription)")
        }
    }
    private var percentageInput: some View {
        HStack {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title2.monospacedDigit())
                .accessibilityLabel("Percentage of bodyweight")
                .accessibilityIdentifier("bodyweight-percentage-input")
            Text("%").foregroundStyle(.secondary)
        }.frame(minHeight: 44)
    }
}

struct BodyweightPercentageEditor: View {
    let exercise: Exercise
    let viewModel: ExerciseListViewModel
    let onSave: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @FocusState private var focused: Bool

    init(exercise: Exercise, viewModel: ExerciseListViewModel, onSave: @escaping (Exercise) -> Void) {
        self.exercise = exercise; self.viewModel = viewModel; self.onSave = onSave
        _text = State(initialValue: String(format: "%g", exercise.resolvedBodyweightFactor * 100))
    }

    private var defaultPercent: Double { exercise.isCustom ? 100 : (exercise.bodyweightFactor ?? 1) * 100 }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(exercise.name).font(.headline) }
                BodyweightPercentageFields(text: $text, placeholder: defaultPercent.formatted(), emptyValueDescription: "Leave blank to reset to \(defaultPercent.formatted())%.")
                    .focused($focused)
                Section {
                    Button(exercise.isCustom ? "Reset to 100%" : "Reset to library default (\(defaultPercent.formatted())%)") {
                        text = ""
                        focused = false
                    }
                    Text("Applies to workouts started after saving. Workouts already started and completed sessions keep their saved percentage. Strength comparisons stay separate when the percentage changes.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let error = viewModel.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        focused = false
                        saving = true
                        Task { @MainActor in
                            defer { saving = false }
                            let percent = try? BodyweightPercentage.parse(text)
                            if let saved = await viewModel.saveBodyweightPercentage(exerciseId: exercise.id, percent: percent) {
                                onSave(saved)
                                dismiss()
                            }
                        }
                    }.disabled(saving || !BodyweightPercentageFields.isValid(text))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
            .interactiveDismissDisabled(saving)
        }
        .preferredColorScheme(.dark)
        .tint(STColors.primary)
    }
}
#endif
