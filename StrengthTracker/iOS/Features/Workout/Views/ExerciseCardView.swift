#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ExerciseCardView: View {
    let workoutExercise: WorkoutExercise
    let isActiveExercise: Bool
    let previousSetData: [Int: String]
    let onWeightChange: (UUID, Double?) -> Void
    let onRepsChange: (UUID, Int?) -> Void
    let onToggleComplete: (UUID) -> Void
    let onAddSet: () -> Void
    let onRemoveSet: ((UUID) -> Void)?
    let onRemoveExercise: (() -> Void)?
    let onSetTypeChange: (UUID, SetType) -> Void
    let onNoteChange: ((String) -> Void)?
    let onMoveSet: ((Int, Int) -> Void)?

    @State private var isReorderingSets: Bool = false
    @State private var isEditingNote: Bool = false
    @State private var noteText: String = ""
    @State private var noteDebounceTask: Task<Void, Never>?

    init(
        workoutExercise: WorkoutExercise,
        isActiveExercise: Bool = true,
        previousSetData: [Int: String] = [:],
        onWeightChange: @escaping (UUID, Double?) -> Void,
        onRepsChange: @escaping (UUID, Int?) -> Void,
        onToggleComplete: @escaping (UUID) -> Void,
        onAddSet: @escaping () -> Void,
        onRemoveSet: ((UUID) -> Void)? = nil,
        onRemoveExercise: (() -> Void)? = nil,
        onSetTypeChange: @escaping (UUID, SetType) -> Void = { _, _ in },
        onNoteChange: ((String) -> Void)? = nil,
        onMoveSet: ((Int, Int) -> Void)? = nil
    ) {
        self.workoutExercise = workoutExercise
        self.isActiveExercise = isActiveExercise
        self.previousSetData = previousSetData
        self.onWeightChange = onWeightChange
        self.onRepsChange = onRepsChange
        self.onToggleComplete = onToggleComplete
        self.onAddSet = onAddSet
        self.onRemoveSet = onRemoveSet
        self.onRemoveExercise = onRemoveExercise
        self.onSetTypeChange = onSetTypeChange
        self.onNoteChange = onNoteChange
        self.onMoveSet = onMoveSet
        self._noteText = State(initialValue: workoutExercise.notes ?? "")
        self._isEditingNote = State(initialValue: workoutExercise.notes != nil && !workoutExercise.notes!.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            cardHeader

            Divider()
                .background(STColors.border)

            // Inline note
            if isEditingNote {
                noteEditor
            }

            if isReorderingSets {
                // Reorder mode
                reorderSetsList

                // Done button
                Button {
                    isReorderingSets = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("DONE")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(STColors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(STColors.border),
                    alignment: .top
                )
            } else {
                // Column headers
                columnHeaders

                // Sets
                ForEach(Array(workoutExercise.sets.enumerated()), id: \.element.id) { index, exerciseSet in
                    SetRowGridView(
                        setNumber: index + 1,
                        exerciseSet: exerciseSet,
                        previousText: previousSetData[index],
                        onWeightChange: { weight in
                            onWeightChange(exerciseSet.id, weight)
                        },
                        onRepsChange: { reps in
                            onRepsChange(exerciseSet.id, reps)
                        },
                        onToggleComplete: {
                            onToggleComplete(exerciseSet.id)
                        },
                        onSetTypeChange: { setType in
                            onSetTypeChange(exerciseSet.id, setType)
                        }
                    )

                    if index < workoutExercise.sets.count - 1 {
                        Divider()
                            .background(STColors.border.opacity(0.5))
                            .padding(.horizontal, STSpacing.setRowHorizontal)
                    }
                }

                // Add Set button
                addSetButton
            }
        }
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .stroke(STColors.border, lineWidth: 1)
        )
        .opacity(isActiveExercise ? 1.0 : 0.9)
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutExercise.exercise.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        isActiveExercise ? STColors.primary : STColors.textPrimary
                    )

                Text(muscleGroupText)
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Menu {
                    Button("Reorder Sets", systemImage: "arrow.up.arrow.down") {
                        isReorderingSets = true
                    }
                    .disabled(workoutExercise.sets.count < 2)
                    Button(
                        workoutExercise.notes != nil && !workoutExercise.notes!.isEmpty ? "Edit Note" : "Add Note",
                        systemImage: "note.text"
                    ) {
                        isEditingNote = true
                    }
                    if workoutExercise.sets.count > 1, let lastSet = workoutExercise.sets.last {
                        Button("Remove Last Set", systemImage: "minus.circle") {
                            onRemoveSet?(lastSet.id)
                        }
                    }
                    Divider()
                    Button("Remove Exercise", systemImage: "trash", role: .destructive) {
                        onRemoveExercise?()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundStyle(STColors.textSecondary)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(STSpacing.cardPadding)
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            STColumnHeader(title: "SET")
                .frame(width: 28)

            STColumnHeader(title: "PREVIOUS", alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            STColumnHeader(title: "KG")
                .frame(width: 72)

            STColumnHeader(title: "REPS")
                .frame(width: 60)

            STColumnHeader(title: "")
                .frame(width: 48)
        }
        .padding(.horizontal, STSpacing.setRowHorizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Add Set Button

    private var addSetButton: some View {
        Button(action: onAddSet) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("ADD SET")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
            }
            .foregroundStyle(STColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(STColors.border),
            alignment: .top
        )
    }

    // MARK: - Note Editor

    private var noteEditor: some View {
        HStack(spacing: 8) {
            TextField("Add a note...", text: $noteText, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 13))
                .foregroundStyle(STColors.textPrimary)
                .onChange(of: noteText) { _, newValue in
                    noteDebounceTask?.cancel()
                    noteDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        onNoteChange?(newValue)
                    }
                }

            Button {
                noteText = ""
                isEditingNote = false
                onNoteChange?("")
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, STSpacing.cardPadding)
        .padding(.vertical, 8)
        .background(STColors.background.opacity(0.3))
    }

    // MARK: - Reorder Sets

    private var reorderSetsList: some View {
        ForEach(Array(workoutExercise.sets.enumerated()), id: \.element.id) { index, exerciseSet in
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(STColors.textSecondary)
                    .frame(width: 28)

                if exerciseSet.setType != .normal {
                    Text(exerciseSet.setType.rawValue.capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(STColors.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(STColors.primary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text(setSummary(exerciseSet))
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textPrimary)

                Spacer()

                Button {
                    onMoveSet?(index, index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(index == 0 ? STColors.textTertiary : STColors.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Button {
                    onMoveSet?(index, index + 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(index == workoutExercise.sets.count - 1 ? STColors.textTertiary : STColors.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(index == workoutExercise.sets.count - 1)
            }
            .padding(.horizontal, STSpacing.setRowHorizontal)
            .padding(.vertical, 6)

            if index < workoutExercise.sets.count - 1 {
                Divider()
                    .background(STColors.border.opacity(0.5))
                    .padding(.horizontal, STSpacing.setRowHorizontal)
            }
        }
    }

    private func setSummary(_ set: ExerciseSet) -> String {
        let weight = set.weight.map { String(format: "%g", $0) + " kg" } ?? "–"
        let reps = set.reps.map { "\($0) reps" } ?? "–"
        return "\(weight) × \(reps)"
    }

    // MARK: - Helpers

    private var muscleGroupText: String {
        var groups: [String] = [workoutExercise.exercise.primaryMuscleGroup.rawValue.capitalized]
        for secondary in workoutExercise.exercise.secondaryMuscleGroups.prefix(2) {
            groups.append(secondary.rawValue.capitalized)
        }
        return groups.joined(separator: ", ")
    }
}

#endif
