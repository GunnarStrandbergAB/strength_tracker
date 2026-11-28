#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Edits one upcoming session in place: its day, its name, and what it asks for.
/// Saving goes through the plan edit engine, so every change can be undone.
struct PlanSessionEditor: View {
    let viewModel: ProgressionPlanViewModel
    let session: PlannedSession

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var date = Date()
    @State private var rows: [PlanExercisePrescription] = []
    @State private var loaded: [PlanExercisePrescription] = []
    @State private var catalog: [Exercise] = []
    @State private var error: String?
    @State private var isBusy = false
    @State private var isLoading = true
    @State private var showPicker = false
    @State private var askScope = false
    @State private var confirmRemove = false

    private var plan: ProgressionPlan? { viewModel.activePlan }
    private var unit: WeightUnit { viewModel.weightUnit }

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker("Day", selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    TextField("Workout name", text: $name)
                        .accessibilityLabel("Workout name")
                }

                Section {
                    if isLoading { ProgressView() }
                    ForEach($rows, id: \.rowID) { $row in exerciseRow($row) }
                        .onDelete { rows.remove(atOffsets: $0) }
                        .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                    Button { showPicker = true } label: { Label("Add exercise", systemImage: "plus") }
                } header: {
                    Text("Exercises")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if session.isDeload {
                            Text("This is a deload session. The numbers are its normal targets; the deload percentage is applied on top.")
                        }
                        if rows.contains(where: { followsRule($0.exerciseID) }) {
                            Text("A lift on a progression rule keeps this change for this session, and its later targets continue from it.")
                        }
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(STColors.danger) }
                }

                Section {
                    Button(session.isSkipped ? "Undo skip" : "Skip this session") {
                        run { await viewModel.toggleSessionSkipped(sessionId: session.id) }
                    }
                    Button("Remove from plan", role: .destructive) { confirmRemove = true }
                } footer: {
                    Text("A skipped session counts as missed. A removed one does not, and can be restored from the plan's edit history.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(STColors.background)
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isBusy || isLoading || !hasChanges)
                        .accessibilityIdentifier("plan-session-save")
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { _ = AppKeyboardDismissal.commitAndDismiss() }
                }
            }
            .sheet(isPresented: $showPicker) { picker }
            .confirmationDialog("Apply the new targets to", isPresented: $askScope, titleVisibility: .visible) {
                Button("This session only") { apply(remaining: false) }
                Button("All remaining sessions") { apply(remaining: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(widened.map { name(of: $0.exerciseID) }.joined(separator: ", "))
            }
            .confirmationDialog("Remove this session from the plan?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    run { try await viewModel.applyPlanEditNow(.init(operation: .removeSessions, sessionIDs: [session.id])) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .tint(STColors.primary)
        .task { await load() }
    }

    // MARK: - Rows

    private func exercise(_ id: UUID) -> Exercise? { catalog.first { $0.id == id } }
    private func name(of id: UUID) -> String { exercise(id)?.name ?? "Exercise" }
    private func followsRule(_ id: UUID) -> Bool { plan?.exercises.first { $0.exerciseId == id }?.progression != nil }

    private func exerciseRow(_ row: Binding<PlanExercisePrescription>) -> some View {
        let type = exercise(row.wrappedValue.exerciseID)?.exerciseType ?? .weightedReps
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name(of: row.wrappedValue.exerciseID)).font(.headline)
                if followsRule(row.wrappedValue.exerciseID) {
                    Text("Rule")
                        .font(.caption2.bold())
                        .foregroundStyle(STColors.primary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(STColors.primary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 10) {
                number("Sets", value: Binding(get: { row.wrappedValue.sets.map(Double.init) }, set: { row.wrappedValue.sets = $0.map { Int($0) } }), label: "sets")
                if type == .weightedReps || type == .bodyweightReps {
                    number("Reps", value: Binding(get: { row.wrappedValue.reps.map(Double.init) }, set: { row.wrappedValue.reps = $0.map { Int($0) } }), label: "reps")
                }
                if type == .weightedReps || type == .bodyweightReps || type == .weightedCardio {
                    number("Weight", value: Binding(
                        get: { row.wrappedValue.weightKg.map(unit.fromKg) },
                        set: { row.wrappedValue.weightKg = $0.map(unit.toKg) }), label: unit.symbol)
                }
                if [.duration, .distance, .cardio, .weightedCardio].contains(type) {
                    number("Seconds", value: Binding(get: { row.wrappedValue.durationSeconds.map(Double.init) },
                        set: { row.wrappedValue.durationSeconds = $0.map { Int($0) } }), label: "s")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func number(_ title: String, value: Binding<Double?>, label: String) -> some View {
        HStack(spacing: 4) {
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
                .padding(.vertical, 6).padding(.horizontal, 6)
                .background(STColors.background)
                .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
                .accessibilityLabel(title)
            Text(label).font(.footnote).foregroundStyle(STColors.textSecondary)
        }
    }

    private var picker: some View {
        PlanExercisePicker(exercises: catalog.filter { !$0.isArchived }) { exercise in
            // One new row per exercise; a second occurrence can be added after saving.
            guard !rows.contains(where: { $0.occurrenceID == nil && $0.exerciseID == exercise.id }) else { return }
            let repBased = exercise.exerciseType == .weightedReps || exercise.exerciseType == .bodyweightReps
            rows.append(PlanExercisePrescription(exerciseID: exercise.id, sets: 3, reps: repBased ? 10 : nil,
                weightKg: repBased || exercise.exerciseType == .weightedCardio ? 0 : nil,
                durationSeconds: repBased ? nil : 60))
        }
    }

    // MARK: - Loading and saving

    private func load() async {
        name = session.displayLabel
        date = session.scheduledDate ?? Date()
        do {
            let (templates, exercises) = try await viewModel.planEditCatalog()
            catalog = exercises
            if let plan {
                rows = try PlanEditingService.editableContents(for: session, plan: plan, templates: templates, exercises: exercises)
                loaded = rows
            }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private var contentsChanged: Bool { rows != loaded }
    private var nameChanged: Bool { name.trimmingCharacters(in: .whitespaces) != session.displayLabel && !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var dateChanged: Bool {
        guard let scheduled = session.scheduledDate else { return true }
        return !Calendar.current.isDate(date, inSameDayAs: scheduled)
    }
    private var hasChanges: Bool { contentsChanged || nameChanged || dateChanged }

    /// Kept exercises whose targets changed and that are not on a rule: the changes
    /// that can sensibly be carried to the remaining sessions.
    private var widened: [PlanExercisePrescription] {
        rows.filter { row in
            guard let before = loaded.first(where: { $0.occurrenceID == row.occurrenceID && row.occurrenceID != nil }),
                  before.exerciseID == row.exerciseID, !followsRule(row.exerciseID) else { return false }
            return before.sets != row.sets || before.reps != row.reps || before.weightKg != row.weightKg
        }
    }

    private func save() {
        if widened.isEmpty { apply(remaining: false) } else { askScope = true }
    }

    private func apply(remaining: Bool) {
        var operations: [PlanEditRequest] = []
        if contentsChanged { operations.append(.init(operation: .setSessionExercises, sessionID: session.id, scope: .session, contents: rows)) }
        if remaining {
            for row in widened {
                operations.append(.init(operation: .changeTargets, sessionID: session.id, scope: .remaining, exerciseID: row.exerciseID,
                    sets: row.sets, reps: row.reps, weightKg: row.weightKg))
            }
        }
        if nameChanged { operations.append(.init(operation: .updateSession, sessionID: session.id, scope: .session, label: name.trimmingCharacters(in: .whitespaces))) }
        if dateChanged { operations.append(.init(operation: .rescheduleSession, sessionID: session.id, newDate: date, scope: .session)) }
        guard !operations.isEmpty else { return }
        let request = operations.count == 1 ? operations[0] : PlanEditRequest(operation: .batch, operations: operations)
        run { try await viewModel.applyPlanEditNow(request) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do {
                try await work()
                if let message = viewModel.errorMessage { error = message; viewModel.errorMessage = nil } else { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }
}

private extension PlanExercisePrescription {
    /// Stable identity for a row: its occurrence, or the exercise for one just added.
    var rowID: String { occurrenceID?.uuidString ?? "new-\(exerciseID.uuidString)" }
}

/// A searchable list of the exercise library.
struct PlanExercisePicker: View {
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [Exercise] {
        let sorted = exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return search.isEmpty ? sorted : sorted.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(shown) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).foregroundStyle(STColors.textPrimary)
                        Text(exercise.primaryMuscleGroup.rawValue.capitalized).font(.caption).foregroundStyle(STColors.textSecondary)
                    }
                }
            }
            .searchable(text: $search)
            .scrollContentBackground(.hidden)
            .background(STColors.background)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .tint(STColors.primary)
    }
}
#endif
