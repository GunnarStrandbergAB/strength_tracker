#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Step 3: how fast the plan asks for more. A pace presets every lift's rule; each
/// rule is shown in numbers and can be changed on its own.
struct PlanProgressionStepView: View {
    @Bindable var viewModel: ProgressionPlanViewModel
    @State private var editing: DraftPlanExercise?
    @State private var isReadingLog = true

    private let deloadChoices = [0, 4, 5, 6, 8]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PlanStepHeader(step: 3, title: "Progression",
                    subtitle: "Choose a pace. Each lift then shows exactly what it will ask for, and you can change any of them.")

                paceSection
                liftsSection
                if viewModel.draftSelectedExercises.contains(where: { $0.rule == nil }) { waveSection }
                deloadSection

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .task {
            // Training days may have changed since the deload days were picked.
            if viewModel.draftUseCustomDeloadDays, viewModel.draftDeloadDays.isEmpty { viewModel.applyDefaultDeloadDays() }
            await viewModel.prepareProgressionDraft()
            isReadingLog = false
        }
        .safeAreaInset(edge: .bottom) {
            PlanStepButtons(back: { viewModel.draftStep = 2 }, forwardTitle: "Preview plan",
                forwardEnabled: !isReadingLog && viewModel.draftProgressionIsComplete, hint: hint) {
                viewModel.draftStep = 4
            }
        }
        .sheet(item: $editing) { draft in
            ProgressionRuleEditor(title: draft.exercise.name, rule: draft.rule, fallback: fallbackRule(for: draft),
                unit: viewModel.weightUnit, allowsWave: true) { rule in
                viewModel.setDraftRule(rule, for: draft.id)
            }
        }
    }

    private var hint: String? {
        guard !isReadingLog else { return "Reading your training log…" }
        guard let missing = viewModel.draftSelectedExercises.first(where: { !$0.hasStart }) else { return nil }
        return missing.rule == nil ? "Enter a 1RM for \(missing.exercise.name)." : "Enter a start weight for \(missing.exercise.name)."
    }

    /// What the editor starts from when a wave lift is switched to a rule.
    private func fallbackRule(for draft: DraftPlanExercise) -> ProgressionRule {
        var rule = ProgressionRuleEngine.defaultRule(pace: viewModel.draftPace, goal: viewModel.draftGoal,
            category: draft.exercise.category, muscle: draft.exercise.primaryMuscleGroup, isCompound: draft.isCompound)
        if draft.oneRM > 0 {
            // Bottom of the range with two reps in reserve, from the 1RM.
            let weight = draft.oneRM / (1 + Double(rule.minReps + 2) / 30)
            rule.startWeightKg = rule.incrementKg > 0 ? (weight / rule.incrementKg).rounded(.down) * rule.incrementKg : weight
        }
        return rule
    }

    // MARK: - Pace

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: "Pace")
            ForEach(PlanPace.allCases, id: \.self) { pace in
                let isSelected = viewModel.draftPace == pace
                Button {
                    viewModel.applyDraftPace(pace)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(isSelected ? STColors.primary : Color.clear)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(isSelected ? STColors.primary : STColors.textTertiary, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(pace.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(STColors.textPrimary)
                                if viewModel.draftPaceRecommendation?.pace == pace, viewModel.draftPaceRecommendation?.weeklyGain != nil {
                                    Text("Suggested")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(STColors.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(STColors.primary.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(pace.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(STColors.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(isSelected ? STColors.primary.opacity(0.08) : STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: STRadius.card)
                        .stroke(isSelected ? STColors.primary.opacity(0.4) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Text(paceReason)
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)
        }
        .padding(.horizontal, 20)
    }

    private var paceReason: String {
        guard let recommendation = viewModel.draftPaceRecommendation else { return "Reading your training log…" }
        guard let gain = recommendation.weeklyGain else {
            return "There is not enough history to suggest a pace. Standard suits most lifters."
        }
        let lifts = recommendation.liftCount == 1 ? "1 lift" : "\(recommendation.liftCount) lifts"
        if gain <= 0 { return "Your estimated 1RM has not been rising over the last 12 weeks (\(lifts) measured)." }
        return "Your estimated 1RM rose about \(String(format: "%.1f", gain * 100))% a week over the last 12 weeks (\(lifts) measured)."
    }

    // MARK: - Lifts

    private var liftsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: "Lifts")
            ForEach(viewModel.draftSelectedExercises) { draft in liftRow(draft) }
        }
        .padding(.horizontal, 20)
    }

    private func liftRow(_ draft: DraftPlanExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(draft.exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)
                if draft.ruleIsCustom {
                    Text("Custom")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(STColors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(STColors.background)
                        .clipShape(Capsule())
                }
                Spacer()
                if draft.supportsRule {
                    Button("Change") { editing = draft }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(STColors.primary)
                        .accessibilityLabel("Change how \(draft.exercise.name) progresses")
                }
            }
            if let rule = draft.rule {
                HStack(spacing: 6) {
                    Text("Start")
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                    numberField(label: "Start weight for \(draft.exercise.name)", valueKg: rule.startWeightKg) {
                        viewModel.setDraftStart(weightKg: $0, for: draft.id)
                    }
                    Text("\(draft.exercise.weightEntryLabel(viewModel.weightUnit).lowercased()) × \(rule.startReps)")
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                    Spacer()
                }
                Text(rule.summary(unit: viewModel.weightUnit))
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)
            } else {
                HStack(spacing: 6) {
                    Text("1RM")
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                    numberField(label: "1RM for \(draft.exercise.name)", valueKg: draft.oneRM) {
                        viewModel.updateOneRM(for: draft.id, value: $0)
                    }
                    Text(draft.exercise.weightEntryLabel(viewModel.weightUnit).lowercased())
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                    Spacer()
                }
                Text(draft.supportsRule ? "Follows the percentage wave." : "Follows the percentage wave; rules cover weighted lifts.")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)
            }
        }
        .padding(14)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func numberField(label: String, valueKg: Double, onChange: @escaping (Double) -> Void) -> some View {
        TextField("0", value: Binding<Double?>(
            get: { valueKg == 0 ? nil : viewModel.weightUnit.fromKg(valueKg) },
            set: { onChange(viewModel.weightUnit.toKg(max(0, $0 ?? 0))) }), format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(STColors.textPrimary)
            .frame(width: 64)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(STColors.background)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
            .accessibilityLabel(label)
    }

    // MARK: - Wave and deloads

    private var waveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: "Percentage wave")
            Picker("Wave", selection: $viewModel.draftProgramType) {
                ForEach(ProgramType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(STColors.primary)
            Text(viewModel.draftProgramType.shortDescription)
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)
        }
        .padding(.horizontal, 20)
    }

    private var deloadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: "Deloads")
            Picker("Deloads", selection: $viewModel.draftDeloadEveryWeeks) {
                ForEach(deloadChoices, id: \.self) { weeks in
                    Text(weeks == 0 ? "When the coach suggests one" : "Every \(weeks)th week").tag(weeks)
                }
            }
            .pickerStyle(.menu)
            .tint(STColors.primary)
            Text("A deload week repeats your targets at the lighter weight from Settings, and does not move a lift up its ladder.")
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)

            if viewModel.draftTrainingDays.count > 1 {
                Toggle("Fewer sessions in a deload week", isOn: Binding(
                    get: { viewModel.draftUseCustomDeloadDays },
                    set: { isOn in
                        viewModel.draftUseCustomDeloadDays = isOn
                        if isOn, viewModel.draftDeloadDays.isEmpty { viewModel.applyDefaultDeloadDays() }
                    }))
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textPrimary)
                    .tint(STColors.primary)
                    .padding(.top, 4)
                if viewModel.draftUseCustomDeloadDays {
                    ForEach(viewModel.orderedDraftDays, id: \.self) { day in deloadDayRow(day) }
                    Text("\(viewModel.draftDeloadDays.count) of \(viewModel.draftTrainingDays.count) training days in a deload week. "
                        + "The other days are left out that week.")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// One training day, ticked when its session stays in a deload week.
    private func deloadDayRow(_ day: Int) -> some View {
        let isKept = viewModel.draftDeloadDays.contains(day)
        let dayName = PlanWizard.dayNames[day] ?? "Day"
        return Button {
            viewModel.toggleDeloadDay(day)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isKept ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isKept ? STColors.primary : STColors.textTertiary)
                Text(dayName)
                    .foregroundStyle(STColors.textPrimary)
                if let workout = viewModel.draftDaySchedule[day]?.templateName {
                    Text(workout)
                        .foregroundStyle(STColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .font(.system(size: 14))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dayName) in a deload week")
        .accessibilityAddTraits(isKept ? .isSelected : [])
    }
}
#endif
