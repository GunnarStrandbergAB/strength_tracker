#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Step 4: the plan exactly as it would be saved. Nothing exists until "Start plan".
struct PlanPreviewStepView: View {
    @Bindable var viewModel: ProgressionPlanViewModel
    let onDone: () -> Void
    @State private var plan: ProgressionPlan?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PlanStepHeader(step: 4, title: "Preview",
                    subtitle: "This is the plan as it will start. Go back to change anything; you can also edit it once it is running.")

                VStack(alignment: .leading, spacing: 8) {
                    PlanSectionTitle(text: "Name")
                    TextField("", text: $viewModel.draftPlanName, prompt: Text("Training Plan").foregroundStyle(STColors.textSecondary))
                        .font(.system(size: 16))
                        .foregroundStyle(STColors.textPrimary)
                        .padding(12)
                        .background(STColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
                        .accessibilityLabel("Plan name")
                }
                .padding(.horizontal, 20)

                if let plan {
                    summary(plan)
                    projection(plan)
                    firstWeeks(plan)
                } else if isLoading {
                    ProgressView().tint(STColors.primary).frame(maxWidth: .infinity).padding(.vertical, 30)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.danger)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 80)
            }
        }
        .background(STColors.background)
        .task {
            plan = await viewModel.draftPreviewPlan()
            isLoading = false
        }
        .safeAreaInset(edge: .bottom) {
            PlanStepButtons(back: { viewModel.draftStep = 3 },
                forwardTitle: viewModel.isSavingPlan ? "Starting…" : "Start plan",
                forwardEnabled: plan != nil && !viewModel.isSavingPlan) {
                Task {
                    await viewModel.generateAndSavePlan()
                    if viewModel.errorMessage == nil { onDone() }
                }
            }
        }
    }

    /// "Mon 30 Nov".
    private func day(_ date: Date?) -> String {
        date?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? "—"
    }

    private func sessions(_ plan: ProgressionPlan) -> [PlannedSession] {
        plan.blocks.flatMap(\.weeks).flatMap(\.sessions).sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }

    private func summary(_ plan: ProgressionPlan) -> some View {
        let all = sessions(plan)
        let deloadWeeks = Set(all.filter(\.isDeload).compactMap(\.programmingWeekNumber)).count
        return VStack(alignment: .leading, spacing: 6) {
            PlanSectionTitle(text: "Schedule")
            Text("\(plan.configuration?.durationWeeks ?? plan.totalWeeks) weeks · \(plan.weeklyFrequency) days a week · \(all.count) sessions")
                .font(.system(size: 14))
                .foregroundStyle(STColors.textPrimary)
            Text("\(day(all.first?.scheduledDate)) to \(day(plan.targetEndDate))"
                + (deloadWeeks > 0 ? " · \(deloadWeeks) deload week\(deloadWeeks == 1 ? "" : "s")" : " · no scheduled deloads"))
                .font(.system(size: 13))
                .foregroundStyle(STColors.textSecondary)
            if let schedule = plan.configuration?.deloadSchedule, !schedule.isEmpty {
                let days = [2, 3, 4, 5, 6, 7, 1].compactMap { day in schedule.first { $0.dayOfWeek == day } }
                Text("A deload week: " + days.map { "\(PlanWizard.dayNames[$0.dayOfWeek] ?? "Day")\($0.templateName.map { " (\($0))" } ?? "")" }
                    .joined(separator: ", ") + ".")
                    .font(.system(size: 13))
                    .foregroundStyle(STColors.textSecondary)
            } else if let kept = plan.deloadDays, !kept.isEmpty, kept.count < plan.weeklyFrequency {
                Text("A deload week keeps \(kept.compactMap { PlanWizard.dayNames[$0] }.joined(separator: ", ")) only.")
                    .font(.system(size: 13))
                    .foregroundStyle(STColors.textSecondary)
            }
        }
        .padding(.horizontal, 20)
    }

    /// First and last normal target of each lift: where it ends up if every target is hit.
    private func projection(_ plan: ProgressionPlan) -> some View {
        let normal = sessions(plan).filter { !$0.isDeload }
        return VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: "If you hit every target")
            ForEach(plan.exercises) { exercise in
                let targets = normal.compactMap { $0.plannedExercises.first { $0.planExerciseId == exercise.id } }
                if let first = targets.first, let last = targets.last {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.exerciseName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)
                        Text("\(first.sets) × \(PlanWizard.target(first.targetWeight, first.targetReps, unit: viewModel.weightUnit))"
                            + "  to  \(last.sets) × \(PlanWizard.target(last.targetWeight, last.targetReps, unit: viewModel.weightUnit))")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(STColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                    .accessibilityElement(children: .combine)
                }
            }
            Text("A missed target repeats, so the real plan moves at your pace.")
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)
        }
        .padding(.horizontal, 20)
    }

    private func firstWeeks(_ plan: ProgressionPlan) -> some View {
        let all = sessions(plan)
        let weekStarts = Array(Set(all.compactMap(\.scheduledDate).map { CalendarWeekBucketer.weekStart(of: $0) })).sorted().prefix(2)
        return VStack(alignment: .leading, spacing: 10) {
            PlanSectionTitle(text: "First two weeks")
            ForEach(Array(weekStarts.enumerated()), id: \.element) { index, start in
                Text("Week \(index + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(STColors.textPrimary)
                ForEach(all.filter { $0.scheduledDate.map { CalendarWeekBucketer.weekStart(of: $0) } == start }) { session in
                    sessionCard(session)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func sessionCard(_ session: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(day(session.scheduledDate)) · \(session.displayLabel)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)
                if session.isDeload {
                    Text("Deload").font(.system(size: 10, weight: .bold)).foregroundStyle(STColors.primary)
                }
            }
            ForEach(session.plannedExercises) { exercise in
                let target = PlanWizard.timedTarget(of: exercise, in: session)
                    ?? PlanWizard.target(exercise.targetWeight, exercise.targetReps, unit: viewModel.weightUnit)
                Text("\(exercise.exerciseName)  \(exercise.sets) × \(target)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(STColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }
}
#endif
