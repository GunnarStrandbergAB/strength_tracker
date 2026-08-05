import SwiftUI
import StrengthTrackerShared

struct SetRowView: View {
    let exerciseSet: ExerciseSet
    var weightUnit: WeightUnit = .kg
    var intensityMetric: IntensityMetric = .rpe
    /// Used to label drop segments ("1a", "1b", …); pass from an enumerated list.
    var setNumber: Int? = nil

    private var hasDropEntries: Bool { !exerciseSet.dropSets.isEmpty }
    private var isFailureOn: Bool { exerciseSet.isFailure || exerciseSet.setType == .failure }

    var body: some View {
        if hasDropEntries {
            dropSetBody
        } else {
            singleLineBody
        }
    }

    // MARK: - Plain Set (and legacy single-row drop/failure sets)

    private var singleLineBody: some View {
        HStack {
            if exerciseSet.setType != .normal {
                typeBadge(exerciseSet.setType.displayName, color: badgeColor)
            }

            // Failure flag (legacy .failure-typed rows already show it via the badge)
            if isFailureOn && exerciseSet.setType != .failure {
                flame
            }

            Spacer()

            if let weight = exerciseSet.weight {
                Text(weightUnit.formatValue(weight, decimals: 1))
                    .monospacedDigit()
                Text(weightUnit.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reps = exerciseSet.reps {
                Text("\u{00D7}")
                    .foregroundStyle(.secondary)
                Text("\(reps)")
                    .monospacedDigit()
                Text("reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            intensityPill(rpe: exerciseSet.rpe, rir: exerciseSet.rir)

            completionIcon
        }
    }

    // MARK: - Grouped Drop Set

    private var dropSetBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                typeBadge("Drop Set", color: .purple)
                Spacer()
                completionIcon
            }

            ForEach(Array(exerciseSet.dropSets.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 6) {
                    Text(segmentLabel(index))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)

                    if let weight = entry.weight {
                        Text("\(weightUnit.formatValue(weight, decimals: 1)) \(weightUnit.symbol)")
                            .font(.subheadline)
                            .monospacedDigit()
                    }

                    if let reps = entry.reps {
                        Text("\u{00D7} \(reps)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    intensityPill(rpe: entry.rpe, rir: entry.rir)

                    if entry.isFailure {
                        flame
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func intensityPill(rpe: Double?, rir: Double?) -> some View {
        // Show the user's preferred metric, deriving from the counterpart for
        // legacy RPE-only data.
        let value: Double? = {
            switch intensityMetric {
            case .rpe: return rpe ?? rir.map(IntensityMetric.rpe(fromRIR:))
            case .rir: return rir ?? rpe.map(IntensityMetric.rir(fromRPE:))
            }
        }()
        if let value {
            Text("\(intensityMetric.displayName) \(String(format: "%g", value))")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }

    private func typeBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private var flame: some View {
        Image(systemName: "flame.fill")
            .font(.caption2)
            .foregroundStyle(.red)
    }

    private var completionIcon: some View {
        Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(exerciseSet.isCompleted ? .green : .secondary)
    }

    private func segmentLabel(_ index: Int) -> String {
        let letter: String = {
            if let scalar = UnicodeScalar(97 + index), index < 26 {
                return String(Character(scalar))
            }
            return "\(index + 1)"
        }()
        if let setNumber {
            return "\(setNumber)\(letter)"
        }
        return letter
    }

    private var badgeColor: Color {
        switch exerciseSet.setType {
        case .warmup: .orange
        case .dropset: .purple
        case .failure: .red
        case .restPause: .blue
        case .normal: .gray
        }
    }
}
