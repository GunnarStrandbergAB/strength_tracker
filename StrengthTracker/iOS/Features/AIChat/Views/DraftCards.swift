#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Card presenting an AI proposal with Save/Discard, or its resolved status.
struct DraftCardView: View {
    let draft: AIDraft
    let status: DraftStatus
    let weightUnit: WeightUnit
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            footer
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .strokeBorder(status == .pending ? STColors.primary.opacity(0.5) : STColors.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(STColors.primary)
            Text(kindLabel)
                .font(.stLabel)
                .foregroundStyle(STColors.textSecondary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch draft {
        case .exercise(let exercise):
            ExerciseDraftContent(exercise: exercise)
        case .template(let template):
            TemplateDraftContent(template: template, weightUnit: weightUnit)
        case .plan(let parameters):
            PlanDraftContent(parameters: parameters, weightUnit: weightUnit)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch status {
        case .pending:
            HStack(spacing: 10) {
                Button(action: onSave) {
                    Text("Save")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(STColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
                }
                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(STColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(STColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
                }
            }
            .buttonStyle(.plain)
        case .accepted:
            statusPill(text: "Saved", icon: "checkmark.circle.fill", color: STColors.success)
        case .discarded:
            statusPill(text: "Discarded", icon: "xmark.circle.fill", color: STColors.textTertiary)
        }
    }

    private func statusPill(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.stCaption)
        }
        .foregroundStyle(color)
    }

    private var kindLabel: String {
        switch draft {
        case .exercise: return "Proposed Exercise"
        case .template: return "Proposed Template"
        case .plan: return "Proposed Training Plan"
        }
    }

    private var iconName: String {
        switch draft {
        case .exercise: return "dumbbell"
        case .template: return "list.clipboard"
        case .plan: return "calendar"
        }
    }
}

// MARK: - Content per draft kind

private struct ExerciseDraftContent: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.stTitle)
                .foregroundStyle(STColors.textPrimary)

            HStack(spacing: 6) {
                muscleChip(exercise.primaryMuscleGroup.rawValue, primary: true)
                ForEach(exercise.secondaryMuscleGroups.prefix(3), id: \.self) { muscle in
                    muscleChip(muscle.rawValue, primary: false)
                }
            }

            Text("\(exercise.category.rawValue.capitalized) · \(exercise.exerciseType.rawValue)")
                .font(.stCaption)
                .foregroundStyle(STColors.textSecondary)

            if let instructions = exercise.instructions, !instructions.isEmpty {
                Text(instructions)
                    .font(.stCaption)
                    .foregroundStyle(STColors.textTertiary)
                    .lineLimit(3)
            }
        }
    }

    private func muscleChip(_ text: String, primary: Bool) -> some View {
        Text(text.capitalized)
            .font(.stCaption)
            .foregroundStyle(primary ? .black : STColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(primary ? STColors.primary : STColors.background)
            .clipShape(Capsule())
    }
}

private struct TemplateDraftContent: View {
    let template: WorkoutTemplate
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                .font(.stTitle)
                .foregroundStyle(STColors.textPrimary)

            if let notes = template.notes, !notes.isEmpty {
                Text(notes)
                    .font(.stCaption)
                    .foregroundStyle(STColors.textSecondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(template.exercises.sorted(by: { $0.order < $1.order })) { exercise in
                    HStack {
                        Text(exercise.exercise.name)
                            .font(.stBody)
                            .foregroundStyle(STColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(targetSummary(exercise))
                            .font(.stCaption)
                            .foregroundStyle(STColors.textSecondary)
                    }
                }
            }
        }
    }

    private func targetSummary(_ exercise: TemplateExercise) -> String {
        var parts = "\(exercise.targetSets)"
        if let reps = exercise.targetReps {
            parts += "×\(reps)"
        }
        if let weight = exercise.targetWeight, weight > 0 {
            parts += " @ \(weightUnit.format(weight))"
        } else if let duration = exercise.targetDurationSeconds {
            parts += " · \(duration)s"
        }
        return parts
    }
}

private struct PlanDraftContent: View {
    let parameters: AIPlanParameters
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(parameters.name)
                .font(.stTitle)
                .foregroundStyle(STColors.textPrimary)

            Text("\(goalLabel) · \(parameters.weeklyFrequency)×/week")
                .font(.stCaption)
                .foregroundStyle(STColors.textSecondary)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(parameters.exercises, id: \.exerciseID) { selection in
                    HStack {
                        Text(selection.exerciseName)
                            .font(.stBody)
                            .foregroundStyle(STColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if let oneRM = selection.estimated1RMKg {
                            Text("1RM \(weightUnit.format(oneRM))")
                                .font(.stCaption)
                                .foregroundStyle(STColors.textSecondary)
                        }
                    }
                }
            }

            Text("A full periodized program is generated when you save.")
                .font(.stCaption)
                .foregroundStyle(STColors.textTertiary)
        }
    }

    private var goalLabel: String {
        parameters.primaryGoal.rawValue
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .capitalized
    }
}
#endif
