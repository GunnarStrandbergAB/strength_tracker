#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Step 2: the exercises of each training day, and which of them the plan progresses.
/// A template only fills a day in; the exercises are the plan's own from then on.
struct PlanWorkoutsStepView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let templateViewModel: TemplateViewModel
    @State private var pickerDay: Int?
    @State private var editingRow: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PlanStepHeader(step: 2, title: "Workouts",
                    subtitle: "Build each day from exercises. A template fills a day in, and you can then add, remove and reorder. "
                        + "Ticked exercises get their targets from the plan; the others keep the targets shown.")

                ForEach(viewModel.orderedDraftDays, id: \.self) { day in dayCard(day) }

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        // The template list is shared with the Templates tab and is empty until someone
        // loads it; without this the menu below has nothing to show and does not open.
        .task { await templateViewModel.loadTemplates() }
        .safeAreaInset(edge: .bottom) {
            PlanStepButtons(back: { viewModel.draftStep = 1 }, forwardEnabled: canContinue, hint: hint) {
                viewModel.draftStep = 3
            }
        }
        .sheet(item: Binding(get: { pickerDay.map(DayID.init) }, set: { pickerDay = $0?.day })) { target in
            ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                viewModel.addDraftExercise(exercise, forDay: target.day)
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
            return "\(PlanWizard.dayNames[day] ?? "A day") has no exercises yet."
        }
        return viewModel.draftSelectedExercises.isEmpty ? "Tick at least one exercise for the plan to progress." : nil
    }

    private func dayCard(_ day: Int) -> some View {
        let entry = viewModel.draftDaySchedule[day]
        let rows = entry?.exercises ?? []
        return VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: PlanWizard.dayNames[day] ?? "Day")

            Menu {
                if templateViewModel.userTemplates.isEmpty { Text("No templates yet") }
                ForEach(templateViewModel.userTemplates) { template in
                    Button(template.name) {
                        editingRow = nil
                        viewModel.setDraftWorkout(template, forDay: day)
                    }
                }
                if !rows.isEmpty {
                    Button("Clear the day", role: .destructive) {
                        editingRow = nil
                        viewModel.setDraftWorkout(nil, forDay: day)
                    }
                }
            } label: {
                HStack {
                    Text(entry?.templateName ?? "Fill from a template")
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

            ForEach(rows) { row in
                exerciseRow(row, day: day, isFirst: row.id == rows.first?.id, isLast: row.id == rows.last?.id,
                    isTicked: entry?.exerciseIds.contains(row.exercise.id) ?? false)
            }

            Button {
                pickerDay = day
            } label: {
                Label("Add exercise", systemImage: "plus")
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

    private func exerciseRow(_ row: TemplateExercise, day: Int, isFirst: Bool, isLast: Bool, isTicked: Bool) -> some View {
        let canTick = ProgressionPlanViewModel.isTrackable(row.exercise)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    viewModel.toggleDraftLift(row.exercise, forDay: day)
                    if editingRow == row.id { editingRow = nil }
                } label: {
                    Image(systemName: isTicked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(isTicked ? STColors.primary : STColors.textTertiary)
                        .opacity(canTick ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .disabled(!canTick)
                .accessibilityLabel(canTick ? "Plan sets the targets for \(row.exercise.name)" : "\(row.exercise.name) keeps its own targets")
                .accessibilityAddTraits(isTicked ? .isSelected : [])

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.exercise.name)
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.textPrimary)
                    if !isTicked {
                        Button {
                            editingRow = editingRow == row.id ? nil : row.id
                        } label: {
                            Text(targets(row))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(STColors.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Targets for \(row.exercise.name): \(targets(row))")
                    }
                }

                Spacer()

                Menu {
                    Button("Move up") { viewModel.moveDraftExercise(row.id, by: -1, forDay: day) }.disabled(isFirst)
                    Button("Move down") { viewModel.moveDraftExercise(row.id, by: 1, forDay: day) }.disabled(isLast)
                    Button("Remove", role: .destructive) { viewModel.removeDraftExercise(row.id, forDay: day) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15))
                        .foregroundStyle(STColors.textSecondary)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(row.exercise.name)")
            }

            if editingRow == row.id, !isTicked { targetFields(row, day: day) }
        }
        .padding(.vertical, 3)
    }

    private var unit: WeightUnit { viewModel.weightUnit }

    /// "3 × 10 · 20 kg" or "3 × 60 s": what an exercise the plan does not progress asks for.
    private func targets(_ row: TemplateExercise) -> String {
        var text = "\(row.targetSets) ×"
        if let reps = row.targetReps { text += " \(reps)" }
        else if let seconds = row.targetDurationSeconds { text += " \(seconds) s" }
        else if let meters = row.targetDistanceMeters { text += " \(meters.formatted(.number.precision(.fractionLength(0...1)))) m" }
        if let weight = row.targetWeight, weight > 0 { text += " · \(unit.format(weight))" }
        return text
    }

    private func targetFields(_ row: TemplateExercise, day: Int) -> some View {
        let type = row.exercise.exerciseType
        func change(_ edit: @escaping (inout TemplateExercise) -> Void) { viewModel.updateDraftExercise(row.id, forDay: day, edit) }
        return HStack(spacing: 10) {
            number("Sets", value: Binding(get: { Double(row.targetSets) }, set: { value in change { $0.targetSets = Int(value ?? 1) } }), label: "sets")
            if type == .weightedReps || type == .bodyweightReps {
                number("Reps", value: Binding(get: { row.targetReps.map(Double.init) },
                    set: { value in change { $0.targetReps = min(max(Int(value ?? 1), 1), 100) } }), label: "reps")
            }
            if type == .weightedReps || type == .bodyweightReps || type == .weightedCardio {
                number("Weight", value: Binding(get: { row.targetWeight.map(unit.fromKg) },
                    set: { value in change { $0.targetWeight = min(max(unit.toKg(value ?? 0), 0), 999) } }), label: unit.symbol)
            }
            if [.duration, .distance, .cardio, .weightedCardio].contains(type) {
                number("Seconds", value: Binding(get: { row.targetDurationSeconds.map(Double.init) },
                    // A timed exercise always needs a time; one with a distance may go without.
                    set: { value in change { $0.targetDurationSeconds = value.map { min(max(Int($0), 1), 86400) } ?? ($0.targetDistanceMeters == nil ? 60 : nil) } }),
                    label: "s")
            }
        }
        .padding(.leading, 28)
    }

    private func number(_ title: String, value: Binding<Double?>, label: String) -> some View {
        HStack(spacing: 4) {
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14))
                .foregroundStyle(STColors.textPrimary)
                .frame(width: 50)
                .padding(.vertical, 6).padding(.horizontal, 6)
                .background(STColors.background)
                .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
                .accessibilityLabel(title)
            Text(label).font(.system(size: 12)).foregroundStyle(STColors.textSecondary)
        }
    }
}
#endif
