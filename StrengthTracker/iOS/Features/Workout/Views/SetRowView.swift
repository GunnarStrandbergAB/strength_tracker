import SwiftUI
import StrengthTrackerShared

struct SetRowView: View {
    let exerciseSet: ExerciseSet

    var body: some View {
        HStack {
            if exerciseSet.setType != .normal {
                Text(exerciseSet.setType.rawValue.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Spacer()

            if let weight = exerciseSet.weight {
                Text(String(format: "%.1f", weight))
                    .monospacedDigit()
                Text("kg")
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

            Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(exerciseSet.isCompleted ? .green : .secondary)
        }
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
