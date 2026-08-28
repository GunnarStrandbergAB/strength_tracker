import Foundation

public enum ExerciseValidationError: Error, Equatable, LocalizedError {
    case emptyName

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Exercise name must not be empty."
        }
    }
}

/// Builds custom exercises with the validation rules previously inlined in
/// AddExerciseView — the single rulebook shared by the UI and the AI tools:
/// - equipment brand applies only to machine/cable/smith-machine exercises
/// - loading type applies only to machines
/// - bodyweight factor applies only to bodyweight-rep exercises, clamped 0.1…1.5
public enum ExerciseFactory {

    public static func makeCustom(
        id: UUID = UUID(),
        name: String,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup] = [],
        category: ExerciseCategory,
        exerciseType: ExerciseType,
        instructions: String? = nil,
        bodyweightPercent: Double? = nil,
        equipmentBrand: String? = nil,
        loadingType: LoadingType? = nil,
        isArchived: Bool = false
    ) throws -> Exercise {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { throw ExerciseValidationError.emptyName }

        let trimmedInstructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Exercise(
            id: id,
            name: trimmedName,
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: secondaryMuscleGroups.filter { $0 != primaryMuscleGroup },
            category: category,
            exerciseType: exerciseType,
            instructions: (trimmedInstructions?.isEmpty ?? true) ? nil : trimmedInstructions,
            isCustom: true,
            isArchived: isArchived,
            bodyweightFactor: resolvedBodyweightFactor(bodyweightPercent, exerciseType: exerciseType),
            equipmentBrand: resolvedBrand(equipmentBrand, category: category),
            loadingType: resolvedLoadingType(loadingType, category: category)
        )
    }

    public static func resolvedBodyweightFactor(_ percent: Double?, exerciseType: ExerciseType) -> Double? {
        guard exerciseType == .bodyweightReps else { return nil }
        guard let percent, percent > 0 else { return nil }
        return min(max(percent / 100.0, 0.1), 1.5)
    }

    public static func showsBrandField(for category: ExerciseCategory) -> Bool {
        [.machine, .cable, .smithMachine].contains(category)
    }

    public static func showsLoadingPicker(for category: ExerciseCategory) -> Bool {
        category == .machine
    }

    // Gated on category (like the bodyweight factor on type) so a category
    // switched away from machine-like resolves nil, not a stale value.
    public static func resolvedBrand(_ brand: String?, category: ExerciseCategory) -> String? {
        guard showsBrandField(for: category) else { return nil }
        let trimmed = brand?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func resolvedLoadingType(_ loadingType: LoadingType?, category: ExerciseCategory) -> LoadingType? {
        showsLoadingPicker(for: category) ? loadingType : nil
    }
}

/// Builds template exercises with the per-type defaults previously inlined in
/// TemplateEditorView.addExercise: 3 sets; default reps for rep-based types;
/// 0 kg starting weight for weighted reps; 60 s for timed work; 1000 m for cardio.
public enum TemplateExerciseFactory {

    public static func make(
        exercise: Exercise,
        order: Int,
        defaultReps: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetWeightKg: Double? = nil,
        restSeconds: Int? = nil,
        supersetGroup: Int? = nil,
        isWarmUp: Bool = false
    ) -> TemplateExercise {
        let isRepBased = exercise.exerciseType == .weightedReps || exercise.exerciseType == .bodyweightReps
        let isCardio = exercise.exerciseType == .cardio || exercise.exerciseType == .weightedCardio

        return TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: order,
            supersetGroup: supersetGroup,
            notes: nil,
            restTimerSeconds: restSeconds,
            targetSets: max(1, targetSets ?? 3),
            targetReps: targetReps ?? (isRepBased ? defaultReps : nil),
            targetWeight: targetWeightKg ?? (exercise.exerciseType == .weightedReps ? 0 : nil),
            targetDurationSeconds: exercise.exerciseType == .duration ? 60 : nil,
            targetDistanceMeters: isCardio ? 1000 : nil,
            setTargets: [],
            isWarmUp: isWarmUp
        )
    }
}
