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

    private let weightUnit: WeightUnit
    private var weightStep: Double { weightUnit == .kg ? 1.25 : 2.5 }
    private var weightLabel: String { weightUnit == .kg ? "KG" : "LBS" }

    init(viewModel: WatchWorkoutViewModel, targetWeight: Double? = nil, targetReps: Int? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self._weight = State(initialValue: targetWeight ?? 20.0)
        self._reps = State(initialValue: Double(targetReps ?? 10))
        self.weightUnit = UserPreferencesService().weightUnit
    }

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)
    private let cardBackground = Color.white.opacity(0.1)
    private let labelColor = Color.white.opacity(0.4)
    private let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        VStack(spacing: 6) {
            // Weight / Reps grid
            HStack(spacing: 8) {
                // Weight card
                inputCard(
                    label: weightLabel,
                    value: String(format: "%g", weight),
                    isFocused: focusedField == .weight,
                    onTap: { focusedField = .weight },
                    onDecrement: { weight = max(0, weight - weightStep) },
                    onIncrement: { weight += weightStep }
                )
                .focusable(focusedField == .weight)
                .digitalCrownRotation($weight, from: 0, through: 500, by: weightStep)

                // Reps card
                inputCard(
                    label: "REPS",
                    value: "\(Int(reps))",
                    isFocused: focusedField == .reps,
                    onTap: { focusedField = .reps },
                    onDecrement: { reps = max(1, reps - 1) },
                    onIncrement: { reps += 1 }
                )
                .focusable(focusedField == .reps)
                .digitalCrownRotation($reps, from: 1, through: 100, by: 1)
            }

            // Rest timer indicator (shows when resting)
            if viewModel.isResting {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                        .foregroundStyle(primaryYellow)
                    Text("REST: \(viewModel.restTimerText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .tracking(2)
                        .textCase(.uppercase)
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            // Finish Set button
            Button {
                Task {
                    try? await viewModel.logSet(weight: weight, reps: Int(reps))
                }
            } label: {
                HStack(spacing: 6) {
                    Text("FINISH SET")
                        .font(.system(size: 14, weight: .black))
                        .tracking(-0.5)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(primaryYellow)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func inputCard(
        label: String,
        value: String,
        isFocused: Bool,
        onTap: @escaping () -> Void,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(labelColor)
                .tracking(1.5)

            HStack(spacing: 0) {
                // Minus button
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Value display
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isFocused ? primaryYellow : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)

                // Plus button
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(cardBackground)
        .cornerRadius(16)
        .onTapGesture(perform: onTap)
    }
}
