#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PlanCreationStep4ReviewView: View {
    @Bindable var viewModel: ProgressionPlanViewModel
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 4 of 4")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(STColors.primary)

                    Text("Review & Generate")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(STColors.textPrimary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Plan name
                VStack(alignment: .leading, spacing: 8) {
                    Text("PLAN NAME")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(STColors.textSecondary)

                    TextField("Training Plan", text: $viewModel.draftPlanName)
                        .font(.system(size: 15))
                        .foregroundStyle(STColors.textPrimary)
                        .padding(12)
                        .background(STColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
                }
                .padding(.horizontal, 20)

                // Summary card
                VStack(alignment: .leading, spacing: 10) {
                    Text("SUMMARY")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(STColors.textSecondary)

                    VStack(spacing: 0) {
                        summaryRow(label: "Goal", value: goalDisplayName(viewModel.draftGoal))
                        Divider().overlay(STColors.border)
                        summaryRow(label: "Program", value: viewModel.draftProgramType.displayName)
                        Divider().overlay(STColors.border)
                        summaryRow(label: "Frequency", value: "\(viewModel.draftFrequency) days/week")
                        Divider().overlay(STColors.border)
                        summaryRow(label: "Level", value: viewModel.draftStatus.rawValue.capitalized)
                        Divider().overlay(STColors.border)
                        summaryRow(label: "Duration", value: "12 weeks")
                    }
                    .background(STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                }
                .padding(.horizontal, 20)

                // Exercises list
                VStack(alignment: .leading, spacing: 10) {
                    Text("EXERCISES (\(viewModel.draftSelectedExercises.count))")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(STColors.textSecondary)

                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.draftSelectedExercises.enumerated()), id: \.element.id) { index, draft in
                            if index > 0 {
                                Divider().overlay(STColors.border)
                            }
                            HStack {
                                Text(draft.exercise.name)
                                    .font(.system(size: 14))
                                    .foregroundStyle(STColors.textPrimary)
                                Spacer()
                                if draft.oneRM > 0 {
                                    Text("\(Int(draft.oneRM)) kg")
                                        .font(.system(size: 13))
                                        .foregroundStyle(STColors.textSecondary)
                                } else {
                                    Text("No 1RM")
                                        .font(.system(size: 13))
                                        .foregroundStyle(STColors.textTertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .background(STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                }
                .padding(.horizontal, 20)

                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.danger)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .safeAreaInset(edge: .bottom) {
            navigationButtons
        }
    }

    // MARK: - Summary Row

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(STColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(STColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.draftStep = 3
            } label: {
                Text("Back")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(STColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                Task {
                    await viewModel.generateAndSavePlan()
                    if viewModel.errorMessage == nil {
                        onComplete()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSavingPlan {
                        ProgressView()
                            .tint(STColors.background)
                    }
                    Text(viewModel.isSavingPlan ? "Generating..." : "Generate Plan")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(STColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(STColors.success)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isSavingPlan)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(STColors.background)
    }

    // MARK: - Helpers

    private func goalDisplayName(_ goal: TrainingGoal) -> String {
        switch goal {
        case .strength: return "Strength"
        case .hypertrophy: return "Hypertrophy"
        case .muscularEndurance: return "Endurance"
        case .powerlifting: return "Powerlifting"
        case .generalFitness: return "General Fitness"
        }
    }
}
#endif
