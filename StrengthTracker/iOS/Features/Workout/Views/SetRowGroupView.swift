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
    let repsLabel: String
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
    var recording: WeightRecording?
    var onSideSetsChange: (([SideSetEntry]) -> Void)?
    var onSideRest: (() -> Void)?

    init(
        setNumber: Int,
        exerciseSet: ExerciseSet,
        previousText: String? = nil,
        weightSuggestion: WeightSuggestion? = nil,
        showIntensity: Bool = false,
        intensityMetric: IntensityMetric = .rpe,
        weightUnit: WeightUnit = .kg,
        weightLabel: String? = nil,
        repsLabel: String = "Reps",
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
        onRemoveDropEntry: ((UUID) -> Void)? = nil,
        recording: WeightRecording? = nil,
        onSideSetsChange: (([SideSetEntry]) -> Void)? = nil,
        onSideRest: (() -> Void)? = nil
    ) {
        self.setNumber = setNumber
        self.exerciseSet = exerciseSet
        self.previousText = previousText
        self.weightSuggestion = weightSuggestion
        self.showIntensity = showIntensity
        self.intensityMetric = intensityMetric
        self.weightUnit = weightUnit
        self.weightLabel = weightLabel
        self.repsLabel = repsLabel
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
        self.recording = recording
        self.onSideSetsChange = onSideSetsChange
        self.onSideRest = onSideRest
    }

    private var hasDropEntries: Bool { !exerciseSet.dropSets.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if let sides = exerciseSet.sideSets {
                SideSetRowsView(setNumber: setNumber, parent: exerciseSet, sides: sides,
                    recording: recording, showIntensity: showIntensity, intensityMetric: intensityMetric,
                    weightUnit: weightUnit, onChange: onSideSetsChange, onRest: onSideRest)
            } else {
            SetRowGridView(
                setNumber: setNumber,
                exerciseSet: exerciseSet,
                previousText: previousText,
                weightSuggestion: weightSuggestion,
                showRPE: showIntensity,
                intensityMetric: intensityMetric,
                weightUnit: weightUnit,
                weightLabel: weightLabel, repsLabel: repsLabel,                onWeightChange: onWeightChange,
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
                weightLabel: weightLabel, repsLabel: repsLabel,                    onWeightChange: { onDropEntryWeightChange?(entry.id, $0) },
                    onRepsChange: { onDropEntryRepsChange?(entry.id, $0) },
                    onIntensityChange: { onDropEntryIntensityChange?(entry.id, $0) },
                    onToggleFailure: { onDropEntryToggleFailure?(entry.id) },
                    onRemove: { onRemoveDropEntry?(entry.id) }
                )
                .id("\(entry.id)-\(intensityMetric.rawValue)-\(entry.isFailure)")
            }
            }
            if exerciseSet.sideSets == nil, let recording, recording.supportsSeparateSides, let onSideSetsChange {
                if recording.repetitions == .oneSide {
                    Menu("Choose left or right side") {
                        ForEach(BodySide.allCases, id: \.self) { side in
                            Button(side.title) {
                                guard STNumericTextField.commitActiveInput() else { return }
                                var copy = exerciseSet; copy.separateSides(recording: recording, onlySide: side)
                                if let sides = copy.sideSets { onSideSetsChange(sides) }
                            }
                        }
                    }.font(.caption).frame(minHeight: 44).padding(.horizontal, STSpacing.setRowHorizontal)
                } else {
                Button("Log sides separately", systemImage: "rectangle.split.2x1") {
                    guard STNumericTextField.commitActiveInput() else { return }
                    var copy = exerciseSet; copy.separateSides(recording: recording)
                    if let sides = copy.sideSets { onSideSetsChange(sides) }
                }.font(.caption).frame(minHeight: 44).padding(.horizontal, STSpacing.setRowHorizontal)
                    .disabled(!exerciseSet.canSeparateSides(recording: recording))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !exerciseSet.canSeparateSides(recording: recording) {
                    Text("Enter an even alternating rep total before splitting it into left and right.")
                        .font(.caption).foregroundStyle(STColors.textSecondary).padding(.horizontal, STSpacing.setRowHorizontal)
                }
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

/// Named sides remain within the same logical set; each has its own completion
/// and optional drops. Only a fully completed pair starts the normal rest timer.
struct SideSetRowsView: View {
    let setNumber: Int
    let parent: ExerciseSet
    let sides: [SideSetEntry]
    let recording: WeightRecording?
    let showIntensity: Bool
    let intensityMetric: IntensityMetric
    let weightUnit: WeightUnit
    let onChange: (([SideSetEntry]) -> Void)?
    let onRest: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set \(setNumber) · \(parent.completedSideCount)/\(sides.count) sides complete")
                .font(.headline)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, STSpacing.setRowHorizontal).padding(.top, 12)
            ForEach(sides) { side in
                VStack(alignment: .leading, spacing: 0) {
                    SetRowGridView(setNumber: setNumber, exerciseSet: side.effort,
                        showRPE: showIntensity, intensityMetric: intensityMetric, weightUnit: weightUnit,
                        weightLabel: recording?.sideWeightLabel(weightUnit), repsLabel: "Reps/side",
                        onWeightChange: { value in change(side.side) { $0.weight = value } },
                        onRepsChange: { value in change(side.side) { $0.reps = value } },
                        onIntensityChange: { value in change(side.side) { $0.applyIntensity(value, metric: intensityMetric) } },
                        onToggleComplete: { change(side.side) { $0.setCompleted(!$0.isCompleted) } },
                        onSetTypeChange: { value in change(side.side) { $0.setType = value } },
                        onAddDropEntry: { change(side.side) { effort in
                            var entries = effort.dropSets.isEmpty ? effort.effectiveParts : effort.dropSets
                            entries.append(DropSetEntry(weight: entries.last?.weight, reps: entries.last?.reps))
                            effort.applyDropSets(entries)
                        } },
                        onToggleFailure: { change(side.side) { $0.setFailureFlag(!$0.isFailure) } },
                        labelOverride: side.side.title)
                    ForEach(Array(side.effort.dropSets.enumerated()), id: \.element.id) { index, drop in
                        DropSetRowView(label: "\(side.side.title) \(index + 1)", entry: drop,
                            showIntensity: showIntensity, intensityMetric: intensityMetric, weightUnit: weightUnit,
                            weightLabel: recording?.sideWeightLabel(weightUnit), repsLabel: "Reps/side",
                            onWeightChange: { value in changeDrop(side.side, drop.id) { $0.weight = value } },
                            onRepsChange: { value in changeDrop(side.side, drop.id) { $0.reps = value } },
                            onIntensityChange: { value in changeDrop(side.side, drop.id) { $0.applyIntensity(value, metric: intensityMetric) } },
                            onToggleFailure: { changeDrop(side.side, drop.id) { $0.setFailureFlag(!$0.isFailure) } },
                            onRemove: { change(side.side) { $0.applyDropSets($0.dropSets.filter { $0.id != drop.id }) } })
                    }
                }
            }
            if let onRest, recording?.execution != .together, parent.hasStartedSides, !parent.isFullyCompleted {
                Button("Rest between sides", systemImage: "timer", action: onRest)
                    .font(.callout).frame(minHeight: 44).padding(.horizontal, STSpacing.setRowHorizontal)
            }
            if onChange != nil {
                Menu {
                    if sides.count == 2 {
                        ForEach(sides.filter { !$0.effort.isCompleted }) { side in
                            Button("Only log \(side.side == .left ? "right" : "left") side") {
                                onChange?(sides.filter { $0.side != side.side })
                            }
                        }
                    } else if let first = sides.first {
                        Button("Add \(first.side == .left ? "right" : "left") side") {
                            var effort = first.effort; effort.setCompleted(false)
                            onChange?(sides + [SideSetEntry(side: first.side == .left ? .right : .left, effort: effort)])
                        }
                    }
                } label: { Label("Sides in this set", systemImage: "ellipsis.circle").font(.caption).frame(minHeight: 44) }
                    .padding(.horizontal, STSpacing.setRowHorizontal)
            }
        }.disabled(onChange == nil)
    }
    private func change(_ side: BodySide, _ update: (inout ExerciseSet) -> Void) {
        var copy = sides
        guard let i = copy.firstIndex(where: { $0.side == side }) else { return }
        update(&copy[i].effort)
        onChange?(copy)
    }
    private func changeDrop(_ side: BodySide, _ id: UUID, _ update: (inout DropSetEntry) -> Void) {
        change(side) { effort in
            var drops = effort.dropSets
            guard let i = drops.firstIndex(where: { $0.id == id }) else { return }
            update(&drops[i]); effort.applyDropSets(drops)
        }
    }
}
#endif
