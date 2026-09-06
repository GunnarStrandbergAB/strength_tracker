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
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    var onIntensityChange: ((Double?) -> Void)? = nil
    let onToggleComplete: () -> Void
    var onSetTypeChange: (SetType) -> Void = { _ in }
    var onAddDropEntry: (() -> Void)? = nil
    var onToggleFailure: (() -> Void)? = nil

    private var hasDropEntries: Bool { !exerciseSet.dropSets.isEmpty }
    private var isFailureOn: Bool { exerciseSet.isFailure || exerciseSet.setType == .failure }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                setBadgeMenu
                VStack(alignment: .leading, spacing: 2) {
                    if let previousText { Text("Previous: \(previousText)").foregroundStyle(STColors.textSecondary) }
                    if let suggestion = weightSuggestion, !exerciseSet.isCompleted {
                        Text("Try \(weightUnit.format(suggestion.weight))").foregroundStyle(STColors.primary)
                    }
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                STCheckbox(isChecked: exerciseSet.isCompleted) {
                    guard STNumericTextField.commitActiveInput() else { return }
                    onToggleComplete()
                }.accessibilityLabel("\(exerciseSet.isCompleted ? "Uncomplete" : "Complete") set \(setNumber)")
            }
            if hasDropEntries {
                Text("\(exerciseSet.dropSets.count) drop segments").font(.caption).foregroundStyle(.purple)
            } else {
                STSetValuesEditor(weight: exerciseSet.weight, reps: exerciseSet.reps,
                    intensity: exerciseSet.intensityValue(for: intensityMetric), showIntensity: showRPE,
                    intensityMetric: intensityMetric, weightUnit: weightUnit, weightLabel: weightLabel, context: "Set \(setNumber)",
                    onWeightChange: onWeightChange, onRepsChange: onRepsChange, onIntensityChange: { onIntensityChange?($0) })
            }
        }
        .padding(.horizontal, STSpacing.setRowHorizontal)
        .padding(.vertical, STSpacing.setRowVertical)
        .background(setRowBackground)
    }

    private var setBadgeMenu: some View {
        Menu {
            ForEach([SetType.normal, SetType.warmup, SetType.restPause], id: \.self) { type in
                Button {
                    guard STNumericTextField.commitActiveInput() else { return }
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
                    guard STNumericTextField.commitActiveInput() else { return }
                    onAddDropEntry()
                } label: {
                    Label(hasDropEntries ? "Add Drop" : "Make Drop Set", systemImage: "arrow.down.right")
                }
            }

            // For grouped drop sets, failure lives on each segment row instead.
            if let onToggleFailure, !hasDropEntries {
                Toggle(isOn: Binding(get: { isFailureOn }, set: { _ in if STNumericTextField.commitActiveInput() { onToggleFailure() } })) {
                    Label("To Failure", systemImage: "flame")
                }
            }
        } label: {
            Text("Set \(setTypeLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(setTypeLabelColor)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
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
