#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct AddExerciseView: View {
    let viewModel: ExerciseListViewModel
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
                            Text(cat.rawValue.localizedCapitalized)
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

                if personalRecordService != nil {
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
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let exercise = Exercise(
                            id: UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            primaryMuscleGroup: primaryMuscleGroup,
                            secondaryMuscleGroups: Array(secondaryMuscleGroups),
                            category: category,
                            exerciseType: exerciseType,
                            instructions: instructions.isEmpty ? nil : instructions,
                            isCustom: true,
                            isArchived: false,
                            bodyweightFactor: resolvedBodyweightFactor
                        )
                        Task {
                            await viewModel.saveExercise(exercise)
                            if let value = Double(known1RM), value > 0, let prService = personalRecordService {
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
}
#endif
