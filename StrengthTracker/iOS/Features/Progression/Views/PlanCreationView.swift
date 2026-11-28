#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// The plan wizard: basics, workouts, progression, then a preview of the real plan.
struct PlanCreationView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let templateViewModel: TemplateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.draftStep {
                case 1:
                    PlanBasicsStepView(viewModel: viewModel)
                case 2:
                    PlanWorkoutsStepView(viewModel: viewModel, exerciseListViewModel: exerciseListViewModel,
                        templateViewModel: templateViewModel)
                case 3:
                    PlanProgressionStepView(viewModel: viewModel)
                default:
                    PlanPreviewStepView(viewModel: viewModel) {
                        viewModel.resetDraft()
                        dismiss()
                    }
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(STColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.resetDraft()
                        dismiss()
                    }
                    .foregroundStyle(STColors.textSecondary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { _ = AppKeyboardDismissal.commitAndDismiss() }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSavingPlan)
    }
}

// MARK: - Shared wizard pieces

enum PlanWizard {
    static let stepCount = 4
    static let dayNames: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    static func goalName(_ goal: TrainingGoal) -> String {
        switch goal {
        case .strength: return "Strength"
        case .hypertrophy: return "Muscle"
        case .muscularEndurance: return "Endurance"
        case .powerlifting: return "Powerlifting"
        case .generalFitness: return "General fitness"
        }
    }

    /// "80 kg × 8", in the user's unit.
    static func target(_ weightKg: Double, _ reps: Int, unit: WeightUnit) -> String {
        "\(unit.format(weightKg)) × \(reps)"
    }
}

struct PlanStepHeader: View {
    let step: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(step) of \(PlanWizard.stepCount)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(STColors.primary)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(STColors.textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(STColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

struct PlanSectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(STColors.textSecondary)
    }
}

/// Back and forward buttons under a step. `hint` says what is still missing when
/// the forward button is disabled.
struct PlanStepButtons: View {
    var back: (() -> Void)?
    var forwardTitle = "Continue"
    var forwardEnabled = true
    var hint: String?
    let forward: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let hint, !forwardEnabled {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                if let back {
                    Button(action: back) {
                        Text("Back")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(STColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(STColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Button(action: forward) {
                    Text(forwardTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(STColors.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(STColors.primary.opacity(forwardEnabled ? 1 : 0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!forwardEnabled)
                .accessibilityIdentifier("plan-step-forward")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 6)
        .background(STColors.background)
    }
}
#endif
