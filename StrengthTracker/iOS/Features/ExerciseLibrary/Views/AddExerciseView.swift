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
            if let factor = source.bodyweightFactor {
                _bodyweightPercent = State(initialValue: String(format: "%g", factor * 100))
            }
            _equipmentBrand = State(initialValue: source.equipmentBrand ?? "")
            _loadingType = State(initialValue: source.loadingType)
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

                if exerciseType == .bodyweightReps {
                    Section {
                        HStack {
                            TextField("e.g. 65", text: $bodyweightPercent)
                                .keyboardType(.decimalPad)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("% of Body Weight Lifted (optional)")
                    } footer: {
                        Text("How much of your body weight this movement loads — e.g. push-ups ≈ 65%, pull-ups = 100%. Used for volume and strength estimates. Defaults to 100%.")
                    }
                }

                if personalRecordService != nil && !mode.isEdit {
                    Section("Known 1RM (optional)") {
                        HStack {
                            TextField("e.g. 100", text: $known1RM)
                                .keyboardType(.decimalPad)
                            Text(weightUnit.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onChange(of: primaryMuscleGroup) { _, newValue in
                secondaryMuscleGroups.remove(newValue)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Edit keeps the same identity (PRs/history stay attached);
                        // create/duplicate mint a new independent exercise.
                        let existing = mode.isEdit ? mode.sourceExercise : nil
                        let exercise = Exercise(
                            id: existing?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            primaryMuscleGroup: primaryMuscleGroup,
                            secondaryMuscleGroups: Array(secondaryMuscleGroups),
                            category: category,
                            exerciseType: exerciseType,
                            instructions: instructions.isEmpty ? nil : instructions,
                            isCustom: true,
                            isArchived: existing?.isArchived ?? false,
                            bodyweightFactor: resolvedBodyweightFactor,
                            equipmentBrand: resolvedBrand,
                            loadingType: resolvedLoadingType
                        )
                        Task {
                            await viewModel.saveExercise(exercise)
                            if !mode.isEdit, let value = Double(known1RM), value > 0, let prService = personalRecordService {
                                let record = PersonalRecord(
                                    id: UUID(),
                                    exerciseId: exercise.id,
                                    recordType: .estimatedOneRepMax,
                                    value: weightUnit.toKg(value),
                                    setId: nil,
                                    achievedAt: Date()
                                )
                                _ = try? await prService.saveManualRecord(record)
                            }
                            onExerciseCreated?(exercise)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private var resolvedBodyweightFactor: Double? {
        guard exerciseType == .bodyweightReps else { return nil }
        guard let pct = Double(bodyweightPercent), pct > 0 else { return nil }
        return min(max(pct / 100.0, 0.1), 1.5)
    }

    private var showsBrandField: Bool {
        [.machine, .cable, .smithMachine].contains(category)
    }

    private var showsLoadingPicker: Bool {
        category == .machine
    }

    // Gated on category (like resolvedBodyweightFactor on type) so switching the
    // category away from machine-like saves nil, not a stale value.
    private var resolvedBrand: String? {
        guard showsBrandField else { return nil }
        let trimmed = equipmentBrand.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var resolvedLoadingType: LoadingType? {
        showsLoadingPicker ? loadingType : nil
    }
}
#endif
