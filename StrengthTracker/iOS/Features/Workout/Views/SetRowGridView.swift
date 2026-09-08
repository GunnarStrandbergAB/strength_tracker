#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct SetRowGridView: View {
    let setNumber: Int
    let exerciseSet: ExerciseSet
    var previousText: String? = nil
    var weightSuggestion: WeightSuggestion? = nil
    var showRPE = false
    var intensityMetric: IntensityMetric = .rpe
    var weightUnit: WeightUnit = .kg
    var weightLabel: String? = nil
    var repsLabel: String = "Reps"
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    var onIntensityChange: ((Double?) -> Void)? = nil
    let onToggleComplete: () -> Void
    var onSetTypeChange: (SetType) -> Void = { _ in }
    var onAddDropEntry: (() -> Void)? = nil
    var onToggleFailure: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasDropEntries: Bool { !exerciseSet.dropSets.isEmpty }
    private var isFailureOn: Bool { exerciseSet.isFailure || exerciseSet.setType == .failure }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize {
                setBadgeMenu
                HStack(spacing: 10) { failureButton; Spacer(minLength: 0); completionButton }
            } else {
                HStack(spacing: 10) {
                    setBadgeMenu
                    failureButton
                    Spacer(minLength: 0)
                    completionButton
                }
            }
            if previousText != nil || (weightSuggestion != nil && !exerciseSet.isCompleted) {
                VStack(alignment: .leading, spacing: 2) {
                    if let previousText { Text("Previous: \(previousText)").foregroundStyle(STColors.textSecondary) }
                    if let suggestion = weightSuggestion, !exerciseSet.isCompleted {
                        Text("Try \(weightUnit.format(suggestion.weight))").foregroundStyle(STColors.primary)
                    }
                }.font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if hasDropEntries {
                Text("\(exerciseSet.dropSets.count) drop segments").font(.caption).foregroundStyle(.purple)
            } else {
                STSetValuesEditor(weight: exerciseSet.weight, reps: exerciseSet.reps,
                    intensity: exerciseSet.intensityValue(for: intensityMetric), showIntensity: showRPE,
                    intensityMetric: intensityMetric, weightUnit: weightUnit, weightLabel: weightLabel, repsLabel: repsLabel, context: "Set \(setNumber)",
                    onWeightChange: onWeightChange, onRepsChange: onRepsChange, onIntensityChange: { onIntensityChange?($0) })
            }
        }
        .padding(.horizontal, STSpacing.setRowHorizontal)
        .padding(.vertical, STSpacing.setRowVertical)
        .background(setRowBackground)
    }

    private var completionButton: some View {
        STCheckbox(isChecked: exerciseSet.isCompleted) {
            guard STNumericTextField.commitActiveInput() else { return }
            onToggleComplete()
        }.accessibilityLabel("\(exerciseSet.isCompleted ? "Uncomplete" : "Complete") set \(setNumber)")
    }

    @ViewBuilder private var failureButton: some View {
        if onToggleFailure != nil, !hasDropEntries {
            Button(action: toggleFailure) {
                Image(systemName: isFailureOn ? "flame.fill" : "flame")
                    .font(.title3)
                    .foregroundStyle(isFailureOn ? STColors.danger : STColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(isFailureOn ? STColors.danger.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: STRadius.input))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isFailureOn ? "Unmark" : "Mark") set \(setNumber) as taken to failure")
            .accessibilityValue(isFailureOn ? "On" : "Off")
            .accessibilityIdentifier("set-failure-\(exerciseSet.id)")
        }
    }

    // Both the shortcut and menu must flush the draft before the parent can re-create this row.
    func toggleFailure() {
        guard !hasDropEntries, let onToggleFailure, STNumericTextField.commitActiveInput() else { return }
        onToggleFailure()
    }

    private var setBadgeMenu: some View {
        Menu {
            ForEach([SetType.normal, SetType.warmup, SetType.restPause], id: \.self) { type in
                Button {
                    guard STNumericTextField.commitActiveInput() else { return }
                    onSetTypeChange(type)
                } label: {
                    if exerciseSet.setType == type || (exerciseSet.setType == .failure && type == .normal) {
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
                    guard STNumericTextField.commitActiveInput() else { return }
                    onAddDropEntry()
                } label: {
                    Label(hasDropEntries ? "Add Drop" : "Make Drop Set", systemImage: "arrow.down.right")
                }
            }

            // For grouped drop sets, failure lives on each segment row instead.
            if onToggleFailure != nil, !hasDropEntries {
                Toggle(isOn: Binding(get: { isFailureOn }, set: { _ in toggleFailure() })) {
                    Label("To Failure", systemImage: "flame")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Set \(setNumber) · \(setTypeLabel)")
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(setTypeLabelColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .background(STColors.background.opacity(0.35), in: RoundedRectangle(cornerRadius: STRadius.input))
            .overlay(RoundedRectangle(cornerRadius: STRadius.input).stroke(STColors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(setNumber), \(setTypeLabel)")
        .accessibilityHint("Opens set type and options")
        .accessibilityIdentifier("set-type-\(exerciseSet.id)")
    }

    // MARK: - Set Type Helpers

    private var setTypeLabel: String {
        if hasDropEntries { return "Drop" }
        switch exerciseSet.setType {
        case .normal, .failure: return "Normal" // Legacy failure is presented by the independent flame.
        case .warmup: return "Warm-up"
        case .dropset: return "Drop"
        case .restPause: return "Rest-pause"
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
