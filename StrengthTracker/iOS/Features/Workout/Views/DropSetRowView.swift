#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct DropSetRowView: View {
    let label: String
    let entry: DropSetEntry
    var showIntensity = false
    var intensityMetric: IntensityMetric = .rpe
    var weightUnit: WeightUnit = .kg
    var weightLabel: String? = nil
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    let onIntensityChange: (Double?) -> Void
    let onToggleFailure: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Drop \(label)").font(.subheadline.bold()).foregroundStyle(.purple)
                Button {
                    guard STNumericTextField.commitActiveInput() else { return }
                    onToggleFailure()
                } label: {
                    Label(entry.isFailure ? "Failure" : "Mark failure", systemImage: entry.isFailure ? "flame.fill" : "flame")
                        .font(.caption).frame(minHeight: 44)
                }.foregroundStyle(entry.isFailure ? STColors.danger : STColors.textSecondary)
                Spacer()
                Button {
                    guard STNumericTextField.commitActiveInput() else { return }
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("Remove drop \(label)").foregroundStyle(STColors.textSecondary)
            }.buttonStyle(.plain)
            STSetValuesEditor(weight: entry.weight, reps: entry.reps, intensity: entry.intensityValue(for: intensityMetric),
                showIntensity: showIntensity, intensityMetric: intensityMetric, weightUnit: weightUnit,
                weightLabel: weightLabel, context: "Drop \(label)", onWeightChange: onWeightChange,
                onRepsChange: onRepsChange, onIntensityChange: onIntensityChange)
        }.padding(.horizontal, STSpacing.setRowHorizontal).padding(.vertical, STSpacing.setRowVertical)
    }
}
#endif
