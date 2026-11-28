#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Step 2: a workout for each training day, and which of its lifts the plan progresses.
struct PlanWorkoutsStepView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let templateViewModel: TemplateViewModel
    @State private var pickerDay: Int?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PlanStepHeader(step: 2, title: "Workouts",
                    subtitle: "Pick a workout for each day. Ticked lifts get targets from the plan; the rest of a template stays as it is.")

                if let notice {
                    Text(notice)
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.danger)
                        .padding(.horizontal, 20)
                }

                ForEach(viewModel.orderedDraftDays, id: \.self) { day in dayCard(day) }

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .safeAreaInset(edge: .bottom) {
            PlanStepButtons(back: { viewModel.draftStep = 1 }, forwardEnabled: canContinue, hint: hint) {
                viewModel.draftStep = 3
            }
        }
        .sheet(item: Binding(get: { pickerDay.map(DayID.init) }, set: { pickerDay = $0?.day })) { target in
            ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                guard ProgressionPlanViewModel.isTrackable(exercise) else {
                    notice = "\(exercise.name) is not logged as reps, so the plan cannot set targets for it. Add it to a template instead."
                    return
                }
                notice = nil
                if viewModel.draftDaySchedule[target.day]?.exerciseIds.contains(exercise.id) != true {
                    viewModel.toggleDraftLift(exercise, forDay: target.day)
                }
            }
        }
    }

    private struct DayID: Identifiable {
        let day: Int
        var id: Int { day }
    }

    private var canContinue: Bool {
        viewModel.draftEmptyDays.isEmpty && !viewModel.draftSelectedExercises.isEmpty
    }

    private var hint: String? {
        if let day = viewModel.draftEmptyDays.first {
            return "\(PlanWizard.dayNames[day] ?? "A day") has no workout or lift yet."
        }
        return viewModel.draftSelectedExercises.isEmpty ? "Tick at least one lift for the plan to progress." : nil
    }

    private func template(for day: Int) -> WorkoutTemplate? {
        guard let id = viewModel.draftDaySchedule[day]?.templateId else { return nil }
        return templateViewModel.userTemplates.first { $0.id == id }
    }

    /// The template's lifts in order, then lifts added by hand for this day.
    private func candidates(for day: Int) -> [Exercise] {
        let fromTemplate = (template(for: day)?.exercises ?? []).sorted { $0.order < $1.order }
            .map(\.exercise).filter(ProgressionPlanViewModel.isTrackable)
        let known = Set(fromTemplate.map(\.id))
        let selected = viewModel.draftDaySchedule[day]?.exerciseIds ?? []
        let added = viewModel.draftSelectedExercises.map(\.exercise).filter { selected.contains($0.id) && !known.contains($0.id) }
        return fromTemplate + added
    }

    private func dayCard(_ day: Int) -> some View {
        let entry = viewModel.draftDaySchedule[day]
        let lifts = candidates(for: day)
        return VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: PlanWizard.dayNames[day] ?? "Day")

            Menu {
                Button("No template") { viewModel.setDraftWorkout(nil, forDay: day) }
                ForEach(templateViewModel.userTemplates) { template in
                    Button(template.name) { viewModel.setDraftWorkout(template, forDay: day) }
                }
            } label: {
                HStack {
                    Text(entry?.templateName ?? "Choose a template")
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
            .accessibilityLabel("Template for \(PlanWizard.dayNames[day] ?? "day")")

            ForEach(lifts) { exercise in
                let isTicked = entry?.exerciseIds.contains(exercise.id) ?? false
                Button {
                    viewModel.toggleDraftLift(exercise, forDay: day)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isTicked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(isTicked ? STColors.primary : STColors.textTertiary)
                        Text(exercise.name)
                            .font(.system(size: 14))
                            .foregroundStyle(STColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isTicked ? .isSelected : [])
            }

            Button {
                pickerDay = day
            } label: {
                Label("Add a lift", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(STColors.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(14)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .padding(.horizontal, 20)
    }
}
#endif
