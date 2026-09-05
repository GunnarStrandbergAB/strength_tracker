#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// One editable drop-set segment row ("1a", "1b", …) rendered under its parent set
/// row. Mirrors the parent grid geometry so the group reads as a single set.
/// Sub-rows have no PREVIOUS data and no completion checkbox — the parent's checkbox
/// completes the whole drop set.
struct DropSetRowView: View {
    let label: String
    let entry: DropSetEntry
    let showIntensity: Bool
    let intensityMetric: IntensityMetric
    /// Display/input unit. Stored weights are always kg; text fields show and accept this unit.
    let weightUnit: WeightUnit
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    /// Value is in the selected metric's scale (RPE 1–10 / RIR 0–9).
    let onIntensityChange: (Double?) -> Void
    let onToggleFailure: () -> Void
    let onRemove: () -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var intensityText: String
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
        label: String,
        entry: DropSetEntry,
        showIntensity: Bool = false,
        intensityMetric: IntensityMetric = .rpe,
        weightUnit: WeightUnit = .kg,
        onWeightChange: @escaping (Double?) -> Void,
        onRepsChange: @escaping (Int?) -> Void,
        onIntensityChange: @escaping (Double?) -> Void,
        onToggleFailure: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.label = label
        self.entry = entry
        self.showIntensity = showIntensity
        self.intensityMetric = intensityMetric
        self.weightUnit = weightUnit
        self.onWeightChange = onWeightChange
        self.onRepsChange = onRepsChange
        self.onIntensityChange = onIntensityChange
        self.onToggleFailure = onToggleFailure
        self.onRemove = onRemove

        let weight = Self.weightText(for: entry.weight, unit: weightUnit)
        let reps = Self.repsText(for: entry.reps)
        let intensity = Self.intensityText(for: entry.intensityValue(for: intensityMetric))
        _weightText = State(initialValue: weight)
        _repsText = State(initialValue: reps)
        _intensityText = State(initialValue: intensity)
        _seededWeightText = State(initialValue: weight)
        _seededRepsText = State(initialValue: reps)
        _seededIntensityText = State(initialValue: intensity)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Segment label, aligned under the SET badge
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 28, alignment: .center)

            // Failure toggle occupies the (empty for segments) PREVIOUS column
            Button {
                onToggleFailure()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: entry.isFailure ? "flame.fill" : "flame")
                        .font(.system(size: 12))
                    if entry.isFailure {
                        Text("Failure")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundStyle(entry.isFailure ? STColors.danger : STColors.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Weight
            STNumberField(
                placeholder: entry.weight.map { weightUnit.formatValue($0) } ?? "0",
                text: $weightText,
                keyboardType: .decimalPad
            )
            .focused($focusedField, equals: .weight)
            .onChange(of: weightText) { _, newValue in
                weightDebounceTask?.cancel()
                // Equal to the seed: either a model→text resync or the user typed
                // back the committed value. The model already holds it.
                guard newValue != seededWeightText else { return }
                weightDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        onWeightChange(nil)
                    } else if let value = Self.parseDouble(trimmed) {
                        onWeightChange(weightUnit.toKg(value))
                    }
                    seededWeightText = newValue
                }
            }
            .frame(width: 72)

            // Reps
            STNumberField(
                placeholder: entry.reps.map { String($0) } ?? "0",
                text: $repsText,
                keyboardType: .numberPad
            )
            .focused($focusedField, equals: .reps)
            .onChange(of: repsText) { _, newValue in
                repsDebounceTask?.cancel()
                guard newValue != seededRepsText else { return }
                repsDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        onRepsChange(nil)
                    } else if let value = Int(trimmed) {
                        onRepsChange(value)
                    }
                    seededRepsText = newValue
                }
            }
            .frame(width: 60)

            // Intensity (optional; RPE or RIR)
            if showIntensity {
                STNumberField(
                    placeholder: intensityMetric.displayName,
                    text: $intensityText,
                    keyboardType: .decimalPad
                )
                .focused($focusedField, equals: .intensity)
                .onChange(of: intensityText) { _, newValue in
                    intensityDebounceTask?.cancel()
                    guard newValue != seededIntensityText else { return }
                    intensityDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        if let val = Self.parseDouble(newValue) {
                            onIntensityChange(clampIntensity(val))
                        } else {
                            onIntensityChange(nil)
                        }
                        seededIntensityText = newValue
                    }
                }
                .frame(width: 44)
            }

            // Remove segment (checkbox column position — segments have no checkbox)
            Button {
                // Cancel instead of flush: this row is going away.
                weightDebounceTask?.cancel()
                repsDebounceTask?.cancel()
                intensityDebounceTask?.cancel()
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(STColors.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, STSpacing.setRowHorizontal)
        .padding(.vertical, STSpacing.setRowVertical)
        .onDisappear {
            flushPendingEdits()
        }
        // External writes (Grok log_set / update_set, Watch sync, …) change the
        // model without touching the text fields. Re-seed them, unless the user
        // is typing in that very field.
        .onChange(of: entry.weight) { _, _ in resync(.weight) }
        .onChange(of: entry.reps) { _, _ in resync(.reps) }
        .onChange(of: modelIntensity) { _, _ in resync(.intensity) }
    }

    private var modelIntensity: Double? { entry.intensityValue(for: intensityMetric) }

    // MARK: - Model → text sync

    static func weightText(for weightKg: Double?, unit: WeightUnit) -> String {
        weightKg.map { unit.formatValue($0) } ?? ""
    }

    static func repsText(for reps: Int?) -> String {
        reps.map { String($0) } ?? ""
    }

    static func intensityText(for value: Double?) -> String {
        value.map { String(format: "%g", $0) } ?? ""
    }

    /// Re-seed one field from the model. Skips the echo of the user's own commit
    /// (text already equals the model) and never interrupts a field being edited.
    private func resync(_ field: Field) {
        switch field {
        case .weight:
            let text = Self.weightText(for: entry.weight, unit: weightUnit)
            guard text != weightText, focusedField != .weight else { return }
            weightDebounceTask?.cancel()
            seededWeightText = text
            weightText = text
        case .reps:
            let text = Self.repsText(for: entry.reps)
            guard text != repsText, focusedField != .reps else { return }
            repsDebounceTask?.cancel()
            seededRepsText = text
            repsText = text
        case .intensity:
            let text = Self.intensityText(for: modelIntensity)
            guard text != intensityText, focusedField != .intensity else { return }
            intensityDebounceTask?.cancel()
            seededIntensityText = text
            intensityText = text
        }
    }

    // MARK: - Helpers

    private func clampIntensity(_ value: Double) -> Double {
        switch intensityMetric {
        case .rpe: return min(max(value, 1), 10)
        case .rir: return min(max(value, 0), 9)
        }
    }

    /// Dirty-checked flush (see SetRowGridView.flushPendingEdits). If this row was
    /// just removed, the callbacks resolve to no-ops in the view model.
    private func flushPendingEdits() {
        weightDebounceTask?.cancel()
        repsDebounceTask?.cancel()
        intensityDebounceTask?.cancel()

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
            if tp.isEmpty { onIntensityChange(nil) }
            else if let val = Self.parseDouble(tp) { onIntensityChange(clampIntensity(val)) }
        }
    }

    private static func parseDouble(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}

#endif
