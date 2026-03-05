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
                    Text("Step 2 of 5")
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

                // Training Days
                VStack(alignment: .leading, spacing: 10) {
                    Text("TRAINING DAYS")
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(STColors.textSecondary)

                    Text("\(viewModel.draftTrainingDays.count) days per week")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(STColors.textPrimary)

                    HStack(spacing: 8) {
                        ForEach(dayOptions, id: \.isoDay) { option in
                            let isSelected = viewModel.draftTrainingDays.contains(option.isoDay)
                            Button {
                                viewModel.toggleTrainingDay(option.isoDay)
                            } label: {
                                Text(option.letter)
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(isSelected ? STColors.background : STColors.textSecondary)
                                    .background(isSelected ? STColors.primary : STColors.surface)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .onAppear {
            if viewModel.draftTrainingDays.isEmpty {
                let defaults = ProgressionPlanViewModel.defaultDaySpread[viewModel.draftFrequency]
                    ?? ProgressionPlanViewModel.defaultDaySpread[3]!
                viewModel.draftTrainingDays = Set(defaults)
            }
        }
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

    // MARK: - Day Options

    private struct DayOption {
        let isoDay: Int   // ISO 8601: Sun=1, Mon=2..Sat=7
        let letter: String
    }

    private let dayOptions: [DayOption] = [
        DayOption(isoDay: 2, letter: "M"),
        DayOption(isoDay: 3, letter: "T"),
        DayOption(isoDay: 4, letter: "W"),
        DayOption(isoDay: 5, letter: "T"),
        DayOption(isoDay: 6, letter: "F"),
        DayOption(isoDay: 7, letter: "S"),
        DayOption(isoDay: 1, letter: "S"),
    ]

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
