#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct PlanCreationStep4ScheduleView: View {
    let viewModel: ProgressionPlanViewModel
    let templateViewModel: TemplateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 4 of 5")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(STColors.primary)

                    Text("Training Schedule")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(STColors.textPrimary)

                    Text("Assign a template to each training day and pick which exercises to include. This step is optional.")
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Day cards
                let sortedDays = Self.dayDisplayOrder.filter { viewModel.draftTrainingDays.contains($0) }
                if sortedDays.isEmpty {
                    noTrainingDaysMessage
                } else {
                    ForEach(sortedDays, id: \.self) { day in
                        dayScheduleCard(day: day)
                    }
                }

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .safeAreaInset(edge: .bottom) {
            navigationButtons
        }
        .task {
            await templateViewModel.loadTemplates()
        }
    }

    // MARK: - Day Card

    private func dayScheduleCard(day: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.fullDayNames[day]?.uppercased() ?? "DAY")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(STColors.textSecondary)

            // Template picker
            templatePicker(forDay: day)

            // Exercise toggles
            ForEach(viewModel.draftSelectedExercises) { draft in
                exerciseToggleRow(draft: draft, day: day)
            }
        }
        .padding(14)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .padding(.horizontal, 20)
    }

    // MARK: - Template Picker

    private func templatePicker(forDay day: Int) -> some View {
        let entry = viewModel.draftDaySchedule[day]
        let templates = templateViewModel.userTemplates

        return Menu {
            Button("None") {
                viewModel.setDraftTemplate(nil, forDay: day)
            }
            ForEach(templates) { template in
                Button(template.name) {
                    viewModel.setDraftTemplate(template, forDay: day)
                }
            }
        } label: {
            HStack {
                Text(entry?.templateName ?? "Select Template")
                    .font(.system(size: 14))
                    .foregroundStyle(entry?.templateName != nil ? STColors.textPrimary : STColors.textTertiary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(STColors.background)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
        }
    }

    // MARK: - Exercise Toggle

    private func exerciseToggleRow(draft: DraftPlanExercise, day: Int) -> some View {
        let entry = viewModel.draftDaySchedule[day]
        let isSelected = entry?.exerciseIds.contains(draft.id) ?? false
        let isInTemplate = isExerciseInTemplate(exerciseId: draft.id, forDay: day)

        return Button {
            viewModel.toggleDraftExercise(draft.id, forDay: day)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? STColors.primary : STColors.textTertiary)

                Text(draft.exercise.name)
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textPrimary)

                if isInTemplate {
                    Text("in template")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(STColors.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(STColors.success.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var noTrainingDaysMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(STColors.textTertiary)
            Text("No training days selected")
                .font(.system(size: 14))
                .foregroundStyle(STColors.textSecondary)
            Text("Go back to step 2 to pick your training days.")
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Navigation

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
                viewModel.draftStep = 5
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

    private func isExerciseInTemplate(exerciseId: UUID, forDay day: Int) -> Bool {
        guard let entry = viewModel.draftDaySchedule[day],
              let templateId = entry.templateId else { return false }
        guard let template = templateViewModel.templates.first(where: { $0.id == templateId }) else { return false }
        return template.exercises.contains { $0.exercise.id == exerciseId }
    }

    private static let fullDayNames: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    /// ISO weekday order: Mon(2)..Sat(7), Sun(1)
    private static let dayDisplayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]
}
#endif
