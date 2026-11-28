#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// What can be changed about a running plan as a whole: its name, how each lift
/// progresses, its length, and the last edit.
struct PlanSettingsView: View {
    let viewModel: ProgressionPlanViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var extraWeeks = 1
    @State private var editing: Lift?
    @State private var catalog: [Exercise] = []
    @State private var error: String?
    @State private var isBusy = false
    @State private var showAdvanced = false

    /// A lift the remaining plan trains, with its rule when it has one.
    private struct Lift: Identifiable {
        let id: UUID
        let name: String
        let exercise: PlanExercise?
        let next: PlannedExerciseSet
    }

    private var plan: ProgressionPlan? { viewModel.activePlan }

    /// Every weighted lift in the remaining sessions, in the order it first comes up.
    private var lifts: [Lift] {
        guard let plan else { return [] }
        var seen = Set<UUID>()
        let open = plan.blocks.flatMap(\.weeks).flatMap(\.sessions).filter { !$0.isClosed }
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
        return open.flatMap { $0.deloadPrescription?.normalExercises ?? $0.plannedExercises }.compactMap { planned in
            guard seen.insert(planned.exerciseId).inserted,
                  catalog.first(where: { $0.id == planned.exerciseId })?.exerciseType == .weightedReps else { return nil }
            return Lift(id: planned.exerciseId, name: planned.exerciseName,
                exercise: plan.exercises.first { $0.exerciseId == planned.exerciseId }, next: planned)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Plan name", text: $name)
                        .accessibilityLabel("Plan name")
                    Button("Rename") {
                        run(.init(operation: .renamePlan, label: name))
                    }
                    .disabled(isBusy || name.trimmingCharacters(in: .whitespaces).isEmpty || name == plan?.name)
                }

                Section {
                    ForEach(lifts) { lift in
                        Button { editing = lift } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lift.name).font(.headline).foregroundStyle(STColors.textPrimary)
                                Text(lift.exercise?.progression?.summary(unit: viewModel.weightUnit)
                                    ?? (lift.next.percentageOf1RM > 0 ? "Percentage wave. Tap to give it a rule." : "Fixed targets. Tap to give it a rule."))
                                    .font(.footnote)
                                    .foregroundStyle(STColors.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    if lifts.contains(where: { $0.exercise?.progression != nil }) {
                        Menu("Set every rule to a pace") {
                            ForEach(PlanPace.allCases, id: \.self) { pace in
                                Button("\(pace.displayName): \(pace.summary)") { applyPace(pace) }
                            }
                        }
                    }
                } header: {
                    Text("Progression")
                } footer: {
                    if plan?.configuration?.holdIncreases == true {
                        Text("Increases are on hold while the coach's verdict is deload: the next session repeats the last one.")
                    } else {
                        Text("A rule applies from the next session. Sessions already trained keep their history.")
                    }
                }

                Section {
                    Stepper("Add \(extraWeeks) week\(extraWeeks == 1 ? "" : "s")", value: $extraWeeks, in: 1...12)
                    Button("Extend the plan") { run(.init(operation: .extendPlan, weeks: extraWeeks, scope: .remaining)) }
                        .disabled(isBusy)
                } header: {
                    Text("Length")
                } footer: {
                    if let end = plan?.targetEndDate { Text("Finishes \(end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())).") }
                }

                if let last = viewModel.lastUndoableEdit {
                    Section("Last edit") {
                        Button("Undo: \(last.description)") { run(.init(operation: .undoEdit, editID: last.id)) }
                            .disabled(isBusy)
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(STColors.danger) }
                }

                Section {
                    Button("More plan edits") { showAdvanced = true }
                } footer: {
                    Text("Deload weeks, rest weeks, a new weekly schedule, shifting or shortening the plan, and restoring removed sessions.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(STColors.background)
            .navigationTitle("Plan settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { _ = AppKeyboardDismissal.commitAndDismiss() }
                }
            }
            .sheet(item: $editing) { lift in
                ProgressionRuleEditor(title: lift.name, rule: lift.exercise?.progression, fallback: fallback(for: lift),
                    unit: viewModel.weightUnit, allowsWave: false,
                    weightIsOptional: lift.exercise?.category == .resistanceBand) { rule in
                    guard let rule else { return }
                    run(.init(operation: .setProgression, exerciseID: lift.id, progression: rule))
                }
            }
            .sheet(isPresented: $showAdvanced) { PlanScheduleEditor(viewModel: viewModel) }
        }
        .preferredColorScheme(.dark)
        .tint(STColors.primary)
        .task {
            name = plan?.name ?? ""
            catalog = (try? await viewModel.planEditCatalog().exercises) ?? []
        }
    }

    /// A rule that starts from what the next session already asks for.
    private func fallback(for lift: Lift) -> ProgressionRule {
        let exercise = catalog.first { $0.id == lift.id }
        var rule = ProgressionRuleEngine.defaultRule(pace: plan?.configuration?.pace ?? .standard, goal: plan?.primaryGoal ?? .hypertrophy,
            category: exercise?.category ?? .barbell, muscle: exercise?.primaryMuscleGroup ?? .chest,
            isCompound: lift.exercise?.isCompound ?? true,
            start: .init(weightKg: lift.next.targetWeight, reps: lift.next.targetReps))
        rule.sets = lift.next.sets
        rule.restSeconds = min(max(lift.next.restSeconds, 15), 900)
        return rule
    }

    /// Re-presets every rule-driven lift, keeping where each one stands.
    private func applyPace(_ pace: PlanPace) {
        guard let plan else { return }
        let operations: [PlanEditRequest] = plan.exercises.compactMap { exercise in
            guard exercise.progression != nil,
                  let current = ProgressionRuleEngine.currentState(of: exercise, in: plan)?.state.target else { return nil }
            let rule = ProgressionRuleEngine.defaultRule(pace: pace, goal: plan.primaryGoal, category: exercise.category,
                muscle: exercise.primaryMuscleGroup, isCompound: exercise.isCompound, start: current)
            return rule == exercise.progression ? nil : PlanEditRequest(operation: .setProgression, exerciseID: exercise.exerciseId, progression: rule)
        }
        guard !operations.isEmpty else { error = "Every rule already matches that pace."; return }
        run(operations.count == 1 ? operations[0] : .init(operation: .batch, operations: operations))
    }

    private func run(_ request: PlanEditRequest) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do {
                try await viewModel.applyPlanEditNow(request)
                name = viewModel.activePlan?.name ?? name
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
