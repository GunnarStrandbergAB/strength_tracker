#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct SetRowGridView: View {
    let setNumber: Int
    let exerciseSet: ExerciseSet
    let previousText: String?
    let showRPE: Bool
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    let onRPEChange: ((Double?) -> Void)?
    let onToggleComplete: () -> Void
    let onSetTypeChange: (SetType) -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var rpeText: String
    @FocusState private var focusedField: Field?
    @State private var weightDebounceTask: Task<Void, Never>?
    @State private var repsDebounceTask: Task<Void, Never>?
    @State private var rpeDebounceTask: Task<Void, Never>?

    private enum Field: Hashable {
        case weight
        case reps
        case rpe
    }

    init(
        setNumber: Int,
        exerciseSet: ExerciseSet,
        previousText: String? = nil,
        showRPE: Bool = false,
        onWeightChange: @escaping (Double?) -> Void,
        onRepsChange: @escaping (Int?) -> Void,
        onRPEChange: ((Double?) -> Void)? = nil,
        onToggleComplete: @escaping () -> Void,
        onSetTypeChange: @escaping (SetType) -> Void = { _ in }
    ) {
        self.setNumber = setNumber
        self.exerciseSet = exerciseSet
        self.previousText = previousText
        self.showRPE = showRPE
        self.onWeightChange = onWeightChange
        self.onRepsChange = onRepsChange
        self.onRPEChange = onRPEChange
        self.onToggleComplete = onToggleComplete
        self.onSetTypeChange = onSetTypeChange

        _weightText = State(
            initialValue: exerciseSet.weight.map { String(format: "%g", $0) } ?? ""
        )
        _repsText = State(
            initialValue: exerciseSet.reps.map { String($0) } ?? ""
        )
        _rpeText = State(
            initialValue: exerciseSet.rpe.map { String(format: "%g", $0) } ?? ""
        )
    }

    // 12-column grid: SET(1) PREVIOUS(4) KG(3) REPS(2) DONE(2)
    var body: some View {
        HStack(spacing: 8) {
            // SET column (1fr) — tappable to cycle set type
            Button {
                let next = exerciseSet.setType.nextType
                onSetTypeChange(next)
            } label: {
                Text(setTypeLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(setTypeLabelColor)
                    .frame(width: 28, alignment: .center)
            }
            .buttonStyle(.plain)

            // PREVIOUS column (4fr)
            Text(previousText ?? "--")
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(STColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            // KG column (3fr)
            STNumberField(
                placeholder: exerciseSet.weight.map { String(format: "%g", $0) } ?? "0",
                text: $weightText,
                keyboardType: .decimalPad
            )
            .focused($focusedField, equals: .weight)
            .onChange(of: weightText) { _, newValue in
                weightDebounceTask?.cancel()
                weightDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    onWeightChange(Double(newValue))
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
                    onRepsChange(Int(newValue))
                }
            }
            .frame(width: 60)

            // RPE column (optional)
            if showRPE {
                STNumberField(
                    placeholder: "RPE",
                    text: $rpeText,
                    keyboardType: .numberPad
                )
                .focused($focusedField, equals: .rpe)
                .onChange(of: rpeText) { _, newValue in
                    rpeDebounceTask?.cancel()
                    rpeDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        if let val = Double(newValue) {
                            onRPEChange?(min(max(val, 1), 10))
                        } else {
                            onRPEChange?(nil)
                        }
                    }
                }
                .frame(width: 44)
            }

            // DONE column (2fr)
            STCheckbox(isChecked: exerciseSet.isCompleted) {
                onToggleComplete()
            }
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, STSpacing.setRowHorizontal)
        .padding(.vertical, STSpacing.setRowVertical)
        .background(setRowBackground)
    }

    // MARK: - Set Type Helpers

    private var setTypeLabel: String {
        switch exerciseSet.setType {
        case .normal: return "\(setNumber)"
        case .warmup: return "W"
        case .dropset: return "D"
        case .failure: return "F"
        case .restPause: return "R"
        }
    }

    private var setTypeLabelColor: Color {
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
