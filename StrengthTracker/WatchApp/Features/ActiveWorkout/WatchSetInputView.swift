import SwiftUI
import StrengthTrackerShared

struct WatchSetInputView: View {
    @State private var viewModel: WatchWorkoutViewModel
    @State private var weight: Double = 20.0
    @State private var reps: Double = 10.0
    @State private var focusedField: Field? = .weight

    enum Field {
        case weight, reps
    }

    init(viewModel: WatchWorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                VStack {
                    Text(String(format: "%.1f", weight))
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(focusedField == .weight ? .green : .primary)
                    Text("kg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .onTapGesture { focusedField = .weight }
                .focusable(focusedField == .weight)
                .digitalCrownRotation($weight, from: 0, through: 500, by: 2.5)

                Text("\u{00D7}")
                    .foregroundStyle(.secondary)

                VStack {
                    Text("\(Int(reps))")
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(focusedField == .reps ? .green : .primary)
                    Text("reps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .onTapGesture { focusedField = .reps }
                .focusable(focusedField == .reps)
                .digitalCrownRotation($reps, from: 1, through: 100, by: 1)
            }

            Button("Log Set") {
                Task {
                    try? await viewModel.logSet(weight: weight, reps: Int(reps))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }
}
