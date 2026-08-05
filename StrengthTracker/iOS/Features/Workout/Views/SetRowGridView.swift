#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct SetRowGridView: View {
    let setNumber: Int
    let exerciseSet: ExerciseSet
    let previousText: String?
    let weightSuggestion: WeightSuggestion?
    /// Shows the intensity column (RPE or RIR depending on `intensityMetric`).
    let showRPE: Bool
    let intensityMetric: IntensityMetric
    /// Display/input unit. Stored weights are always kg; text fields show and accept this unit.
    let weightUnit: WeightUnit
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    /// Value is in the selected metric's scale (RPE 1–10 / RIR 0–9).
    let onIntensityChange: ((Double?) -> Void)?
    let onToggleComplete: () -> Void
    /// Only ever invoked with .normal/.warmup/.restPause — drop set and failure are
    /// managed through `onAddDropEntry`/`onToggleFailure`.
    let onSetTypeChange: (SetType) -> Void
    let onAddDropEntry: (() -> Void)?
    let onToggleFailure: (() -> Void)?

    @State private var weightText: String
    @State private var repsText: String
    @State private var intensityText: String
    // Seed snapshots captured once per row identity — flushes only fire for fields
    // the user actually edited, so stale @State text can never overwrite the model.
    @State private var seededWeightText: String
    @State private var seededRepsText: String
    @State private var seededIntensityText: String
    @FocusState private var focusedField: Field?
    @State private var weightDebounceTask: Task<Void, Never>?
    @State private var repsDebounceTask: Task<Void, Never>?
    @State private var intensityDebounceTask: Task<Void, Never>?

    private enum Field: Hashable {
        case weight
        case reps
        case intensity
    }

    init(
        setNumber: Int,
        exerciseSet: ExerciseSet,
        previousText: String? = nil,
        weightSuggestion: WeightSuggestion? = nil,
        showRPE: Bool = false,
        intensityMetric: IntensityMetric = .rpe,
        weightUnit: WeightUnit = .kg,
        onWeightChange: @escaping (Double?) -> Void,
        onRepsChange: @escaping (Int?) -> Void,
        onIntensityChange: ((Double?) -> Void)? = nil,
        onToggleComplete: @escaping () -> Void,
        onSetTypeChange: @escaping (SetType) -> Void = { _ in },
        onAddDropEntry: (() -> Void)? = nil,
        onToggleFailure: (() -> Void)? = nil
    ) {
        self.setNumber = setNumber
        self.exerciseSet = exerciseSet
        self.previousText = previousText
        self.weightSuggestion = weightSuggestion
        self.showRPE = showRPE
        self.intensityMetric = intensityMetric
        self.weightUnit = weightUnit
        self.onWeightChange = onWeightChange
        self.onRepsChange = onRepsChange
        self.onIntensityChange = onIntensityChange
        self.onToggleComplete = onToggleComplete
        self.onSetTypeChange = onSetTypeChange
        self.onAddDropEntry = onAddDropEntry
        self.onToggleFailure = onToggleFailure

        let weight = exerciseSet.weight.map { weightUnit.formatValue($0) } ?? ""
        let reps = exerciseSet.reps.map { String($0) } ?? ""
        let intensity = exerciseSet.intensityValue(for: intensityMetric).map { String(format: "%g", $0) } ?? ""
        _weightText = State(initialValue: weight)
        _repsText = State(initialValue: reps)
        _intensityText = State(initialValue: intensity)
        _seededWeightText = State(initialValue: weight)
        _seededRepsText = State(initialValue: reps)
        _seededIntensityText = State(initialValue: intensity)
    }

    /// Grouped drop set with real segments. Legacy single-row `.dropset` history
    /// (empty `dropSets`) keeps the plain editable row.
    private var hasDropEntries: Bool { !exerciseSet.dropSets.isEmpty }

    private var isFailureOn: Bool { exerciseSet.isFailure || exerciseSet.setType == .failure }

    // 12-column grid: SET(1) PREVIOUS(4) KG(3) REPS(2) DONE(2)
    var body: some View {
        HStack(spacing: 8) {
            // SET column (1fr) — menu for set type / drop set / failure
            setBadgeMenu

            // PREVIOUS column (4fr)
            VStack(alignment: .leading, spacing: 1) {
                Text(previousText ?? "--")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(STColors.textTertiary)
                    .lineLimit(1)

                if let suggestion = weightSuggestion,
                   !exerciseSet.isCompleted {
                    Text("Try \(weightUnit.format(suggestion.weight))")
                        .font(.system(size: 10))
                        .foregroundStyle(STColors.primary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasDropEntries {
                // The segments own weight/reps/intensity — the parent just summarizes.
                Text("\(exerciseSet.dropSets.count) drops")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: fieldsWidth, alignment: .center)
            } else {
                // KG column (3fr)
                STNumberField(
                    placeholder: exerciseSet.weight.map { weightUnit.formatValue($0) } ?? "0",
                    text: $weightText,
                    keyboardType: .decimalPad
                )
                .focused($focusedField, equals: .weight)
                .onChange(of: weightText) { _, newValue in
                    weightDebounceTask?.cancel()
                    weightDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            onWeightChange(nil)
                        } else if let value = Self.parseDouble(trimmed) {
                            onWeightChange(weightUnit.toKg(value))
                        }
                    }
                }
                .frame(width: 72)

                // REPS column (2fr)
                STNumberField(
                    placeholder: exerciseSet.reps.map { String($0) } ?? "0",
                    text: $repsText,
                    keyboardType: .numberPad
                )
                .focused($focusedField, equals: .reps)
                .onChange(of: repsText) { _, newValue in
                    repsDebounceTask?.cancel()
                    repsDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            onRepsChange(nil)
                        } else if let value = Int(trimmed) {
                            onRepsChange(value)
                        }
                    }
                }
                .frame(width: 60)

                // Intensity column (optional; RPE or RIR)
                if showRPE {
                    STNumberField(
                        placeholder: intensityMetric.displayName,
                        text: $intensityText,
                        keyboardType: .decimalPad
                    )
                    .focused($focusedField, equals: .intensity)
                    .onChange(of: intensityText) { _, newValue in
                        intensityDebounceTask?.cancel()
                        intensityDebounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            guard !Task.isCancelled else { return }
                            if let val = Self.parseDouble(newValue) {
                                onIntensityChange?(clampIntensity(val))
                            } else {
                                onIntensityChange?(nil)
                            }
                        }
                    }
                    .frame(width: 44)
                }
            }

            // DONE column (2fr) — the single completion control for the whole set,
            // drop segments included.
            STCheckbox(isChecked: exerciseSet.isCompleted) {
                // Flush pending edits so the toggle save includes latest values
                flushPendingEdits()
                onToggleComplete()
            }
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, STSpacing.setRowHorizontal)
        .padding(.vertical, STSpacing.setRowVertical)
        .background(setRowBackground)
        .onDisappear {
            flushPendingEdits()
        }
    }

    // MARK: - Set Badge Menu

    private var setBadgeMenu: some View {
        Menu {
            ForEach([SetType.normal, SetType.warmup, SetType.restPause], id: \.self) { type in
                Button {
                    onSetTypeChange(type)
                } label: {
                    if exerciseSet.setType == type {
                        Label(type.displayName, systemImage: "checkmark")
                    } else {
                        Text(type.displayName)
                    }
                }
                // A grouped drop set can't be retyped without discarding its segments.
                .disabled(hasDropEntries)
            }

            if onAddDropEntry != nil || onToggleFailure != nil {
                Divider()
            }

            if let onAddDropEntry {
                Button {
                    onAddDropEntry()
                } label: {
                    Label(hasDropEntries ? "Add Drop" : "Make Drop Set", systemImage: "arrow.down.right")
                }
            }

            // For grouped drop sets, failure lives on each segment row instead.
            if let onToggleFailure, !hasDropEntries {
                Toggle(isOn: Binding(get: { isFailureOn }, set: { _ in onToggleFailure() })) {
                    Label("To Failure", systemImage: "flame")
                }
            }
        } label: {
            Text(setTypeLabel)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(setTypeLabelColor)
                .frame(width: 28, alignment: .center)
                .overlay(alignment: .topTrailing) {
                    if isFailureOn && !hasDropEntries {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(STColors.danger)
                            .offset(x: 5, y: -4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var fieldsWidth: CGFloat {
        // weight(72) + spacing(8) + reps(60) [+ spacing(8) + intensity(44)]
        showRPE ? 192 : 140
    }

    private func clampIntensity(_ value: Double) -> Double {
        switch intensityMetric {
        case .rpe: return min(max(value, 1), 10)
        case .rir: return min(max(value, 0), 9)
        }
    }

    /// Push any user-edited field values through the callbacks. Fields the user never
    /// touched are skipped (dirty check against the seed snapshot) so stale text can't
    /// overwrite model changes — critical when a set converts to/from a drop set.
    private func flushPendingEdits() {
        weightDebounceTask?.cancel()
        repsDebounceTask?.cancel()
        intensityDebounceTask?.cancel()

        // A drop-set parent mirrors its top segment; its own fields are hidden and
        // must never be written from this row.
        guard !hasDropEntries else { return }

        if weightText != seededWeightText {
            let tw = weightText.trimmingCharacters(in: .whitespaces)
            if tw.isEmpty { onWeightChange(nil) }
            else if let w = Self.parseDouble(tw) { onWeightChange(weightUnit.toKg(w)) }
        }

        if repsText != seededRepsText {
            let tr = repsText.trimmingCharacters(in: .whitespaces)
            if tr.isEmpty { onRepsChange(nil) }
            else if let r = Int(tr) { onRepsChange(r) }
        }

        if intensityText != seededIntensityText {
            let tp = intensityText.trimmingCharacters(in: .whitespaces)
            if tp.isEmpty { onIntensityChange?(nil) }
            else if let val = Self.parseDouble(tp) { onIntensityChange?(clampIntensity(val)) }
        }
    }

    // MARK: - Set Type Helpers

    private var setTypeLabel: String {
        if hasDropEntries { return "\(setNumber)" }
        switch exerciseSet.setType {
        case .normal: return "\(setNumber)"
        case .warmup: return "W"
        case .dropset: return "D"
        case .failure: return "F"
        case .restPause: return "R"
        }
    }

    private var setTypeLabelColor: Color {
        if hasDropEntries { return .purple }
        switch exerciseSet.setType {
        case .normal:
            return exerciseSet.isCompleted ? STColors.primary : STColors.textSecondary
        case .warmup: return .orange
        case .dropset: return .purple
        case .failure: return STColors.danger
        case .restPause: return .blue
        }
    }

    private static func parseDouble(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var setRowBackground: Color {
        if exerciseSet.isCompleted {
            return STColors.primary.opacity(0.05)
        }
        if exerciseSet.setType == .warmup {
            return Color.orange.opacity(0.06)
        }
        return Color.clear
    }
}

#endif
