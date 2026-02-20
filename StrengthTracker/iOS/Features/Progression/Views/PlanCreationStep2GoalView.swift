#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PlanCreationStep2GoalView: View {
    @Bindable var viewModel: ProgressionPlanViewModel

    private let goalColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 2 of 4")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(STColors.primary)

                    Text("Goal & Program")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(STColors.textPrimary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Training Goal
                VStack(alignment: .leading, spacing: 10) {
                    Text("TRAINING GOAL")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(STColors.textSecondary)

                    LazyVGrid(columns: goalColumns, spacing: 10) {
                        ForEach(TrainingGoal.allCases, id: \.self) { goal in
                            goalCard(goal)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Program Type
                VStack(alignment: .leading, spacing: 10) {
                    Text("PROGRAM TYPE")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(STColors.textSecondary)

                    VStack(spacing: 8) {
                        ForEach(ProgramType.allCases, id: \.self) { program in
                            programRow(program)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Frequency
                VStack(alignment: .leading, spacing: 10) {
                    Text("WEEKLY FREQUENCY")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(STColors.textSecondary)

                    HStack {
                        Text("\(viewModel.draftFrequency) days per week")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(STColors.textPrimary)

                        Spacer()

                        Stepper("", value: $viewModel.draftFrequency, in: 2...6)
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .safeAreaInset(edge: .bottom) {
            navigationButtons
        }
    }

    // MARK: - Goal Card

    private func goalCard(_ goal: TrainingGoal) -> some View {
        Button {
            viewModel.draftGoal = goal
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(goalDisplayName(goal))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(viewModel.draftGoal == goal ? STColors.primary : STColors.textPrimary)

                Text("\(goal.repRange.lowerBound)-\(goal.repRange.upperBound) reps")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(viewModel.draftGoal == goal ? STColors.primary.opacity(0.08) : STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(viewModel.draftGoal == goal ? STColors.primary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Program Row

    private func programRow(_ program: ProgramType) -> some View {
        let isRecommended = program == viewModel.draftStatus.recommendedProgramType

        return Button {
            viewModel.draftProgramType = program
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(viewModel.draftProgramType == program ? STColors.primary : Color.clear)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(viewModel.draftProgramType == program ? STColors.primary : STColors.textTertiary, lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(program.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)

                        if isRecommended {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(STColors.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(STColors.primary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(program.shortDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(12)
            .background(viewModel.draftProgramType == program ? STColors.primary.opacity(0.08) : STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(viewModel.draftProgramType == program ? STColors.primary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.draftStep = 1
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
                viewModel.draftStep = 3
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(STColors.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(STColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
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
