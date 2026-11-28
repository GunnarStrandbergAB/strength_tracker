#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Step 1: what the plan is for, which days, how long, and when it starts.
struct PlanBasicsStepView: View {
    @Bindable var viewModel: ProgressionPlanViewModel

    private let goalColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private let days: [(weekday: Int, letter: String)] = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PlanStepHeader(step: 1, title: "Goal and schedule",
                    subtitle: "The goal sets the rep ranges the plan starts from. Everything can be changed later.")

                VStack(alignment: .leading, spacing: 10) {
                    PlanSectionTitle(text: "Goal")
                    LazyVGrid(columns: goalColumns, spacing: 10) {
                        ForEach(TrainingGoal.allCases, id: \.self) { goal in goalCard(goal) }
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    PlanSectionTitle(text: "Training days")
                    HStack(spacing: 8) {
                        ForEach(days, id: \.weekday) { day in
                            let isSelected = viewModel.draftTrainingDays.contains(day.weekday)
                            Button {
                                viewModel.toggleTrainingDay(day.weekday)
                            } label: {
                                Text(day.letter)
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(isSelected ? STColors.background : STColors.textSecondary)
                                    .background(isSelected ? STColors.primary : STColors.surface)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(PlanWizard.dayNames[day.weekday] ?? "Day")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Text("\(viewModel.draftTrainingDays.count) days a week")
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    PlanSectionTitle(text: "Length")
                    Stepper("\(viewModel.resolvedDraftDurationWeeks) weeks", value: Binding(
                        get: { viewModel.resolvedDraftDurationWeeks },
                        set: { viewModel.draftDurationWeeks = $0 }), in: 4...52)
                        .foregroundStyle(STColors.textPrimary)
                    Text("You can extend or shorten a running plan.")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    PlanSectionTitle(text: "Start")
                    DatePicker("First session", selection: Binding(
                        get: { viewModel.draftStartDate },
                        set: { viewModel.draftStartDate = $0; viewModel.draftStartDateManuallySet = true }),
                        in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .foregroundStyle(STColors.textPrimary)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .onAppear {
            if viewModel.draftTrainingDays.isEmpty {
                viewModel.draftTrainingDays = Set(ProgressionPlanViewModel.defaultDaySpread[3] ?? [2, 4, 6])
                viewModel.draftFrequency = viewModel.draftTrainingDays.count
            }
            if !viewModel.draftStartDateManuallySet { viewModel.draftStartDate = viewModel.defaultStartDate() }
        }
        .safeAreaInset(edge: .bottom) {
            PlanStepButtons { viewModel.draftStep = 2 }
        }
    }

    private func goalCard(_ goal: TrainingGoal) -> some View {
        let isSelected = viewModel.draftGoal == goal
        let range = ProgressionRuleEngine.defaultRepRange(goal: goal, isCompound: true)
        return Button {
            viewModel.draftGoal = goal
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(PlanWizard.goalName(goal))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? STColors.primary : STColors.textPrimary)
                Text("\(range.lowerBound)–\(range.upperBound) reps on main lifts")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isSelected ? STColors.primary.opacity(0.08) : STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(RoundedRectangle(cornerRadius: STRadius.card)
                .stroke(isSelected ? STColors.primary.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
