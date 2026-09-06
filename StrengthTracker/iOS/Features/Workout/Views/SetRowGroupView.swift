#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// A parent set row plus its editable drop-segment rows, visually grouped as one set.
/// Shared by active logging (ExerciseCardView) and history edit mode (WorkoutDetailView)
/// so both surfaces render and edit drop sets identically.
struct SetRowGroupView: View {
    let setNumber: Int
    let exerciseSet: ExerciseSet
    let previousText: String?
    let weightSuggestion: WeightSuggestion?
    let showIntensity: Bool
    let intensityMetric: IntensityMetric
    let weightUnit: WeightUnit
    let weightLabel: String?
    // Parent-row callbacks (threaded straight into SetRowGridView)
    let onWeightChange: (Double?) -> Void
    let onRepsChange: (Int?) -> Void
    let onIntensityChange: ((Double?) -> Void)?
    let onToggleComplete: () -> Void
    let onSetTypeChange: (SetType) -> Void
    let onAddDropEntry: (() -> Void)?
    let onToggleFailure: (() -> Void)?
    // Per-segment callbacks (entry-id keyed)
    let onDropEntryWeightChange: ((UUID, Double?) -> Void)?
    let onDropEntryRepsChange: ((UUID, Int?) -> Void)?
    let onDropEntryIntensityChange: ((UUID, Double?) -> Void)?
    let onDropEntryToggleFailure: ((UUID) -> Void)?
    let onRemoveDropEntry: ((UUID) -> Void)?

    init(
        setNumber: Int,
        exerciseSet: ExerciseSet,
        previousText: String? = nil,
        weightSuggestion: WeightSuggestion? = nil,
        showIntensity: Bool = false,
        intensityMetric: IntensityMetric = .rpe,
        weightUnit: WeightUnit = .kg,
        weightLabel: String? = nil,
        onWeightChange: @escaping (Double?) -> Void,
        onRepsChange: @escaping (Int?) -> Void,
        onIntensityChange: ((Double?) -> Void)? = nil,
        onToggleComplete: @escaping () -> Void,
        onSetTypeChange: @escaping (SetType) -> Void = { _ in },
        onAddDropEntry: (() -> Void)? = nil,
        onToggleFailure: (() -> Void)? = nil,
        onDropEntryWeightChange: ((UUID, Double?) -> Void)? = nil,
        onDropEntryRepsChange: ((UUID, Int?) -> Void)? = nil,
        onDropEntryIntensityChange: ((UUID, Double?) -> Void)? = nil,
        onDropEntryToggleFailure: ((UUID) -> Void)? = nil,
        onRemoveDropEntry: ((UUID) -> Void)? = nil
    ) {
        self.setNumber = setNumber
        self.exerciseSet = exerciseSet
        self.previousText = previousText
        self.weightSuggestion = weightSuggestion
        self.showIntensity = showIntensity
        self.intensityMetric = intensityMetric
        self.weightUnit = weightUnit
        self.weightLabel = weightLabel
        self.onWeightChange = onWeightChange
        self.onRepsChange = onRepsChange
        self.onIntensityChange = onIntensityChange
        self.onToggleComplete = onToggleComplete
        self.onSetTypeChange = onSetTypeChange
        self.onAddDropEntry = onAddDropEntry
        self.onToggleFailure = onToggleFailure
        self.onDropEntryWeightChange = onDropEntryWeightChange
        self.onDropEntryRepsChange = onDropEntryRepsChange
        self.onDropEntryIntensityChange = onDropEntryIntensityChange
        self.onDropEntryToggleFailure = onDropEntryToggleFailure
        self.onRemoveDropEntry = onRemoveDropEntry
    }

    private var hasDropEntries: Bool { !exerciseSet.dropSets.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SetRowGridView(
                setNumber: setNumber,
                exerciseSet: exerciseSet,
                previousText: previousText,
                weightSuggestion: weightSuggestion,
                showRPE: showIntensity,
                intensityMetric: intensityMetric,
                weightUnit: weightUnit,
                weightLabel: weightLabel,                onWeightChange: onWeightChange,
                onRepsChange: onRepsChange,
                onIntensityChange: onIntensityChange,
                onToggleComplete: onToggleComplete,
                onSetTypeChange: onSetTypeChange,
                onAddDropEntry: onAddDropEntry,
                onToggleFailure: onToggleFailure
            )
            // Re-seed the row's text state whenever the set converts to/from a drop
            // set, the metric changes mid-session, or a failure toggle backfills
            // intensity — otherwise stale @State text lingers.
            .id("\(exerciseSet.id)-\(hasDropEntries)-\(intensityMetric.rawValue)-\(exerciseSet.isFailure)")

            ForEach(Array(exerciseSet.dropSets.enumerated()), id: \.element.id) { index, entry in
                DropSetRowView(
                    label: segmentLabel(index),
                    entry: entry,
                    showIntensity: showIntensity,
                    intensityMetric: intensityMetric,
                    weightUnit: weightUnit,
                weightLabel: weightLabel,                    onWeightChange: { onDropEntryWeightChange?(entry.id, $0) },
                    onRepsChange: { onDropEntryRepsChange?(entry.id, $0) },
                    onIntensityChange: { onDropEntryIntensityChange?(entry.id, $0) },
                    onToggleFailure: { onDropEntryToggleFailure?(entry.id) },
                    onRemove: { onRemoveDropEntry?(entry.id) }
                )
                .id("\(entry.id)-\(intensityMetric.rawValue)-\(entry.isFailure)")
            }
        }
        .background(hasDropEntries ? Color.purple.opacity(0.04) : Color.clear)
        .overlay(alignment: .leading) {
            if hasDropEntries {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.purple.opacity(0.5))
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
    }

    /// "1a", "1b", … labels for segments of set N.
    private func segmentLabel(_ index: Int) -> String {
        if let scalar = UnicodeScalar(97 + index), index < 26 {
            return "\(setNumber)\(Character(scalar))"
        }
        return "\(setNumber).\(index + 1)"
    }
}

#endif
