#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Edits one exercise's progression rule and shows what it will ask for. Used by
/// the wizard and by a running plan.
struct ProgressionRuleEditor: View {
    private enum Mode: Hashable { case repsThenWeight, fixedSteps, wave }

    let title: String
    let unit: WeightUnit
    /// False where the percentage wave is not on offer (a running plan).
    let allowsWave: Bool
    /// False for an exercise that can only follow the wave (not logged as weight × reps).
    let allowsRule: Bool
    /// True for a band: the rule may run on reps alone, without any weight.
    let weightIsOptional: Bool
    let onSave: (ProgressionRule?) -> Void
    /// The sets and reps chosen for the percentage wave; nil for both leaves them to the wave.
    let onSaveWave: ((Int?, Int?) -> Void)?

    @State private var mode: Mode
    @State private var rule: ProgressionRule
    @State private var choosesWaveTargets: Bool
    @State private var waveSets: Int
    @State private var waveReps: Int
    @Environment(\.dismiss) private var dismiss

    /// `rule` nil means the exercise is on the percentage wave; `fallback` is what the
    /// editor starts from when the user switches it to a rule.
    init(title: String, rule: ProgressionRule?, fallback: ProgressionRule, unit: WeightUnit, allowsWave: Bool,
         allowsRule: Bool = true, weightIsOptional: Bool = false, waveSets: Int? = nil, waveReps: Int? = nil,
         onSaveWave: ((Int?, Int?) -> Void)? = nil, onSave: @escaping (ProgressionRule?) -> Void) {
        self.title = title
        self.unit = unit
        self.allowsWave = allowsWave
        self.allowsRule = allowsRule
        self.weightIsOptional = weightIsOptional
        self.onSave = onSave
        self.onSaveWave = onSaveWave
        _rule = State(initialValue: (rule ?? fallback).normalized)
        _mode = State(initialValue: allowsRule ? (rule.map { $0.kind == .fixedSteps ? .fixedSteps : .repsThenWeight } ?? .wave) : .wave)
        _choosesWaveTargets = State(initialValue: waveSets != nil || waveReps != nil)
        _waveSets = State(initialValue: waveSets ?? fallback.sets)
        _waveReps = State(initialValue: waveReps ?? (fallback.minReps + fallback.maxReps) / 2)
    }

    private var edited: ProgressionRule {
        var value = rule
        value.kind = mode == .fixedSteps ? .fixedSteps : .repsThenWeight
        if value.kind == .fixedSteps { value.minReps = value.maxReps }
        if value.maxReps < value.minReps { value.maxReps = value.minReps }
        return value.normalized
    }

    private var problem: String? {
        guard mode != .wave else { return nil }
        if edited.startWeightKg <= 0, !weightIsOptional { return "Enter a start weight." }
        do { try edited.validate(); return nil } catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            Form {
                if allowsRule {
                    Section("How it progresses") {
                        Picker("Rule", selection: $mode) {
                            Text("Reps, then weight").tag(Mode.repsThenWeight)
                            Text("Weight steps").tag(Mode.fixedSteps)
                            if allowsWave { Text("Percentage wave").tag(Mode.wave) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                if mode == .wave {
                    Section {
                        Text("Weights follow a percentage of your estimated 1RM, rising and falling with the plan's wave. The estimate moves when you beat it.")
                            .font(.footnote)
                            .foregroundStyle(STColors.textSecondary)
                    }
                    Section {
                        Toggle("Choose sets and reps", isOn: $choosesWaveTargets)
                        if choosesWaveTargets {
                            Stepper("\(waveSets) sets", value: $waveSets, in: 1...10)
                            Stepper("\(waveReps) reps", value: $waveReps, in: 1...30)
                        }
                    } header: {
                        Text("Sets and reps")
                    } footer: {
                        Text(choosesWaveTargets
                            ? "Every session asks for \(waveSets) × \(waveReps). The weight is worked out from your 1RM for that many reps and still follows the wave."
                            : "The wave decides the sets and reps of each session.")
                    }
                } else {
                    Section("Sets and reps") {
                        Stepper("\(rule.sets) sets", value: $rule.sets, in: 1...10)
                        if mode == .fixedSteps {
                            Stepper("\(rule.maxReps) reps", value: $rule.maxReps, in: 1...30)
                        } else {
                            Stepper("From \(rule.minReps) reps", value: $rule.minReps, in: 1...30)
                            Stepper("To \(max(rule.maxReps, rule.minReps)) reps", value: $rule.maxReps, in: rule.minReps...40)
                        }
                    }
                    Section {
                        weightField("Start at", value: $rule.startWeightKg)
                        weightField(mode == .fixedSteps ? "Add each step" : "Add at the top of the range", value: $rule.incrementKg)
                    } header: {
                        Text("Weight")
                    } footer: {
                        if weightIsOptional {
                            Text("A band has no set weight. Leave both empty and it progresses on reps alone.")
                        }
                    }
                    Section {
                        Stepper(rule.sessionsPerStep == 1 ? "Move on after every successful session"
                            : "Move on after \(rule.sessionsPerStep) successful sessions", value: $rule.sessionsPerStep, in: 1...6)
                        Stepper(rule.missesBeforeBackoff == 0 ? "Never back off after misses"
                            : "Back off after \(rule.missesBeforeBackoff) misses in a row", value: $rule.missesBeforeBackoff, in: 0...6)
                        if rule.missesBeforeBackoff > 0 {
                            Stepper("Drop the weight by \(rule.backoffPercent)%", value: $rule.backoffPercent, in: 5...30, step: 5)
                        }
                        Stepper("Rest \(rule.restSeconds) s", value: $rule.restSeconds, in: 30...600, step: 15)
                    } header: {
                        Text("Pace")
                    } footer: {
                        Text("A session is successful when every set reaches the rep target.")
                    }
                    Section("What it asks for") {
                        Text(edited.summary(unit: unit))
                            .font(.subheadline)
                            .foregroundStyle(STColors.textPrimary)
                        if let problem {
                            Text(problem).font(.footnote).foregroundStyle(STColors.danger)
                        } else {
                            Text(ladder)
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(STColors.textSecondary)
                                .accessibilityLabel("The first eight sessions if every target is hit: \(ladder)")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(STColors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(mode == .wave ? nil : edited)
                        if mode == .wave { onSaveWave?(choosesWaveTargets ? waveSets : nil, choosesWaveTargets ? waveReps : nil) }
                        dismiss()
                    }
                    .disabled(problem != nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { _ = AppKeyboardDismissal.commitAndDismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(STColors.primary)
    }

    /// The first eight sessions if every target is hit.
    private var ladder: String {
        ProgressionRuleEngine.projection(from: ProgressionRuleEngine.initialState(edited), rule: edited, count: 8)
            .map { $0.weightKg > 0 ? "\(unit.formatValue($0.weightKg))×\($0.reps)" : "\($0.reps) reps" }.joined(separator: "  ")
    }

    private func weightField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: Binding<Double?>(
                get: { value.wrappedValue == 0 ? nil : unit.fromKg(value.wrappedValue) },
                set: { value.wrappedValue = unit.toKg(max(0, $0 ?? 0)) }), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityLabel(label)
            Text(unit.symbol).foregroundStyle(STColors.textSecondary)
        }
    }
}
#endif
