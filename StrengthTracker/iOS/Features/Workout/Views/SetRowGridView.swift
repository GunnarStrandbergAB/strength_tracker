#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct SetRowGridView: View {
    let setNumber: Int
    let exerciseSet: ExerciseSet
    let previousText: String?
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    let onToggleComplete: () -> Void

    @State private var weightText: String
    @State private var repsText: String
    @FocusState private var focusedField: Field?
    @State private var weightDebounceTask: Task<Void, Never>?
    @State private var repsDebounceTask: Task<Void, Never>?

    private enum Field: Hashable {
        case weight
        case reps
    }

    init(
        setNumber: Int,
        exerciseSet: ExerciseSet,
        previousText: String? = nil,
        onWeightChange: @escaping (Double?) -> Void,
        onRepsChange: @escaping (Int?) -> Void,
        onToggleComplete: @escaping () -> Void
    ) {
        self.setNumber = setNumber
        self.exerciseSet = exerciseSet
        self.previousText = previousText
        self.onWeightChange = onWeightChange
        self.onRepsChange = onRepsChange
        self.onToggleComplete = onToggleComplete

        _weightText = State(
            initialValue: exerciseSet.weight.map { String(format: "%g", $0) } ?? ""
        )
        _repsText = State(
            initialValue: exerciseSet.reps.map { String($0) } ?? ""
        )
    }

    // 12-column grid: SET(1) PREVIOUS(4) KG(3) REPS(2) DONE(2)
    var body: some View {
        HStack(spacing: 8) {
            // SET column (1fr)
            Text("\(setNumber)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    exerciseSet.isCompleted ? STColors.primary : STColors.textSecondary
                )
                .frame(width: 28, alignment: .center)

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
            .frame(width: 52)

            // DONE column (2fr)
            STCheckbox(isChecked: exerciseSet.isCompleted) {
                onToggleComplete()
            }
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, STSpacing.setRowHorizontal)
        .padding(.vertical, STSpacing.setRowVertical)
        .background(
            exerciseSet.isCompleted
                ? STColors.primary.opacity(0.05)
                : Color.clear
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .fontWeight(.semibold)
            }
        }
    }
}

#endif
