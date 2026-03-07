#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PlanCreationStep5ReviewView: View {
    @Bindable var viewModel: ProgressionPlanViewModel
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 5 of 5")
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

                    TextField("", text: $viewModel.draftPlanName, prompt:
                        Text("Training Plan").foregroundStyle(STColors.textSecondary)
                    )
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
                        summaryRow(label: "Frequency", value: trainingDaysSummary)
                        Divider().overlay(STColors.border)
                        summaryRow(label: "Level", value: viewModel.draftStatus.rawValue.capitalized)
                        Divider().overlay(STColors.border)
                        summaryRow(label: "Duration", value: "12 weeks")
                    }
                    .background(STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                }
                .padding(.horizontal, 20)

                // Training schedule (only if user assigned templates/exercises)
                if !viewModel.draftDaySchedule.isEmpty {
                    scheduleSummarySection
                }

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

    // MARK: - Schedule Summary

    private var scheduleSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAINING SCHEDULE")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(STColors.textSecondary)

            VStack(spacing: 0) {
                let sortedDays = Self.dayDisplayOrder.filter { viewModel.draftDaySchedule[$0] != nil }
                ForEach(Array(sortedDays.enumerated()), id: \.element) { index, day in
                    if index > 0 {
                        Divider().overlay(STColors.border)
                    }
                    if let entry = viewModel.draftDaySchedule[day] {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Self.fullDayNames[day] ?? "Day")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(STColors.textPrimary)
                                Spacer()
                                if let name = entry.templateName {
                                    Text(name)
                                        .font(.system(size: 12))
                                        .foregroundStyle(STColors.primary)
                                }
                            }
                            if !entry.exerciseIds.isEmpty {
                                let names = viewModel.draftSelectedExercises
                                    .filter { entry.exerciseIds.contains($0.id) }
                                    .map(\.exercise.name)
                                Text(names.joined(separator: ", "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(STColors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        }
        .padding(.horizontal, 20)
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
                viewModel.draftStep = 4
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

    private static let shortDayNames: [Int: String] = [
        1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed",
        5: "Thu", 6: "Fri", 7: "Sat"
    ]

    private static let fullDayNames: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    /// ISO weekday order: Mon(2)..Sat(7), Sun(1)
    private static let dayDisplayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    private var trainingDaysSummary: String {
        let days = viewModel.draftTrainingDays
        guard !days.isEmpty else { return "\(viewModel.draftFrequency) days/week" }
        let sorted = Self.dayDisplayOrder.filter { days.contains($0) }
        let names = sorted.compactMap { Self.shortDayNames[$0] }
        return names.joined(separator: ", ")
    }

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
