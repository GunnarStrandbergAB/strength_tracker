import SwiftUI
import StrengthTrackerShared

struct WatchSetInputView: View {
    @State private var viewModel: WatchWorkoutViewModel
    @State private var weight: Double = 20.0
    @State private var reps: Double = 10.0
    @FocusState private var focusedField: Field?

    enum Field {
        case weight, reps
    }

    private let weightUnit: WeightUnit
    private var weightStep: Double { weightUnit == .kg ? 2.5 : 5.0 }
    private var weightLabel: String { weightUnit == .kg ? "KG" : "LBS" }

    init(viewModel: WatchWorkoutViewModel, targetWeight: Double? = nil, targetReps: Int? = nil) {
        let prefs = UserPreferencesService()
        self._viewModel = State(initialValue: viewModel)
        self._weight = State(initialValue: targetWeight ?? 20.0)
        self._reps = State(initialValue: Double(targetReps ?? prefs.defaultReps))
        self.weightUnit = prefs.weightUnit
    }

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)
    private let cardBackground = Color.white.opacity(0.1)
    private let labelColor = Color.white.opacity(0.4)
    private let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        VStack(spacing: 6) {
            // Weight / Reps grid
            HStack(spacing: 4) {
                // Weight card
                inputCard(
                    label: weightLabel,
                    value: String(format: "%g", weight),
                    isFocused: focusedField == .weight,
                    onTap: { focusedField = .weight },
                    onDecrement: { weight = max(0, weight - weightStep) },
                    onIncrement: { weight += weightStep }
                )
                .focused($focusedField, equals: .weight)
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
                .focused($focusedField, equals: .reps)
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

            // Action button row with set navigation
            HStack(spacing: 6) {
                // ◀ previous set
                Button {
                    viewModel.navigateToPreviousSet()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(viewModel.canNavigateToPreviousSet ? .white : .white.opacity(0.25))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canNavigateToPreviousSet)

                // FINISH SET / UPDATE
                Button {
                    if viewModel.isEditingCompletedSet {
                        viewModel.updateSet(weight: weight, reps: Int(reps))
                    } else {
                        Task {
                            try? await viewModel.logSet(weight: weight, reps: Int(reps))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.isEditingCompletedSet ? "UPDATE" : "FINISH SET")
                            .font(.system(size: 12, weight: .black))
                            .tracking(-0.5)
                        Image(systemName: viewModel.isEditingCompletedSet ? "pencil.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(primaryYellow)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // ▶ next set
                Button {
                    viewModel.navigateToNextSet()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(viewModel.canNavigateToNextSet ? .white : .white.opacity(0.25))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canNavigateToNextSet)
            }
        }
        .onAppear {
            focusedField = .weight
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
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(labelColor)
                .tracking(1.5)

            HStack(spacing: 0) {
                // Minus button
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                // Value display
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isFocused ? primaryYellow : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)

                // Plus button
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(cardBackground)
        .cornerRadius(16)
        .onTapGesture(perform: onTap)
    }
}
