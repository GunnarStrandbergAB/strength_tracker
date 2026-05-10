#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ActivePlanDetailView: View {
    let viewModel: ProgressionPlanViewModel
    let templateViewModel: TemplateViewModel
    let onStartSession: (WorkoutTemplate, UUID, UUID, Bool) async -> Void
    @State private var expandedWeekId: UUID?
    @State private var preparingSessionId: UUID?
    @State private var showPauseConfirmation = false
    @State private var showAbandonConfirmation = false
    @State private var templatePickerSession: PlannedSession?
    @State private var rescheduleSession: PlannedSession?
    @State private var rescheduleDate: Date = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let plan = viewModel.activePlan {
                VStack(alignment: .leading, spacing: 20) {
                    // Plan header
                    planHeader(plan)

                    // Overall progress
                    progressSection(plan)

                    // Block sections
                    ForEach(plan.blocks) { block in
                        blockSection(block, plan: plan)
                    }

                    // Actions
                    actionButtons(plan)

                    Spacer(minLength: 20)
                }
            } else {
                ContentUnavailableView(
                    "No Active Plan",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Create a plan from the dashboard.")
                )
            }
        }
        .background(STColors.background)
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.inline)
        .stNavigationBarStyle()
        .sheet(item: $templatePickerSession) { session in
            TemplateMergePickerView(
                session: session,
                planExercises: viewModel.activePlan?.exercises ?? [],
                templateViewModel: templateViewModel,
                progressionPlanViewModel: viewModel
            )
        }
        .sheet(item: $rescheduleSession) { session in
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Reschedule Session")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(STColors.textPrimary)

                    DatePicker(
                        "New date",
                        selection: $rescheduleDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(STColors.primary)

                    Spacer()
                }
                .padding(20)
                .background(STColors.background)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { rescheduleSession = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let sessionId = session.id
                            let newDate = rescheduleDate
                            rescheduleSession = nil
                            Task {
                                await viewModel.rescheduleSession(sessionId: sessionId, to: newDate)
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Pause Plan?", isPresented: $showPauseConfirmation) {
            Button("Pause Plan") {
                Task { await viewModel.pausePlan() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can resume this plan later from where you left off.")
        }
        .confirmationDialog("Abandon Plan?", isPresented: $showAbandonConfirmation) {
            Button("Abandon Plan", role: .destructive) {
                Task {
                    await viewModel.abandonPlan()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently end your current plan. Progress data is kept but the plan cannot be resumed.")
        }
    }

    // MARK: - Plan Header

    private func planHeader(_ plan: ProgressionPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(STColors.textPrimary)

                Spacer()

                Text(plan.status.rawValue.capitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(statusColor(plan.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(plan.status).opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label(plan.programType.displayName, systemImage: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)

                Label("\(plan.weeklyFrequency)x/week", systemImage: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Progress Section

    private func progressSection(_ plan: ProgressionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PROGRESS")
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(STColors.textSecondary)

                Spacer()

                Text("\(plan.completedWeeks)/\(plan.totalWeeks) weeks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(STColors.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(STColors.surface)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(STColors.primary)
                        .frame(width: geo.size.width * plan.overallProgress, height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(viewModel.adherencePercent)% adherence")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)

                Spacer()

                if let progress = viewModel.planProgress, progress.isOnTrack {
                    Label("On Track", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(STColors.success)
                } else {
                    Label("Needs Attention", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .padding(.horizontal, 20)
    }

    // MARK: - Block Section

    private func blockSection(_ block: TrainingBlock, plan: ProgressionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(block.name.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(STColors.textSecondary)

                if block.isDeload {
                    Text("DELOAD")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(STColors.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(STColors.primary.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                if block.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(STColors.success)
                        .font(.system(size: 14))
                }
            }

            ForEach(block.weeks) { week in
                weekSection(week, isCurrentWeek: week.id == plan.currentWeek?.id, plan: plan)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Week Section (Expandable)

    private func weekSection(_ week: TrainingWeek, isCurrentWeek: Bool, plan: ProgressionPlan) -> some View {
        let isExpanded = expandedWeekId == week.id

        return VStack(spacing: 0) {
            // Tappable week row
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedWeekId = isExpanded ? nil : week.id
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(week.allSessionsCompleted ? STColors.success : (isCurrentWeek ? STColors.primary : STColors.textTertiary.opacity(0.3)))
                        .frame(width: 10, height: 10)

                    Text("Week \(week.absoluteWeekNumber)")
                        .font(.system(size: 13, weight: isCurrentWeek ? .semibold : .regular))
                        .foregroundStyle(isCurrentWeek ? STColors.textPrimary : STColors.textSecondary)

                    if week.isDeload {
                        Text("Deload")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(STColors.primary.opacity(0.8))
                    }

                    Spacer()

                    Text("\(week.completedSessions)/\(week.sessions.count) sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(STColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isCurrentWeek ? STColors.primary.opacity(0.06) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Expanded session cards
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(week.sessions) { session in
                        sessionCard(session, plan: plan, weekIsDeload: week.isDeload)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Session Card

    private func sessionCard(_ session: PlannedSession, plan: ProgressionPlan, weekIsDeload: Bool = false) -> some View {
        let isCompleted = session.isCompleted
        let isPreparing = preparingSessionId == session.id

        return VStack(alignment: .leading, spacing: 8) {
            // Header: label + linked badge + completion badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sessionLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isCompleted ? STColors.textTertiary : STColors.textPrimary)

                    if let date = session.scheduledDate {
                        Button {
                            if !isCompleted {
                                rescheduleDate = date
                                rescheduleSession = session
                            }
                        } label: {
                            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .font(.system(size: 12))
                                .foregroundStyle(isCompleted ? .secondary : isOverdue(session) ? STColors.danger : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCompleted)
                    }

                    if let tid = session.templateId {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                            Text(viewModel.linkedTemplateNames[tid] ?? "Template")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(STColors.primary)
                    }
                }

                Spacer()

                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.success)
                }
            }

            // Exercise lines
            ForEach(session.plannedExercises) { exercise in
                exerciseLine(exercise, muted: isCompleted)
            }

            // Duration + RPE info
            HStack {
                Label("~\(session.estimatedDurationMinutes) min", systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)

                Spacer()

                if session.dupSessionType != nil {
                    Text(session.dupSessionType?.rawValue.capitalized ?? "")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(STColors.primary.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(STColors.primary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            // Start Session button
            if !isCompleted && plan.status == .active {
                Button {
                    Task {
                        preparingSessionId = session.id
                        if let template = await viewModel.prepareSessionTemplate(for: session) {
                            await onStartSession(template, session.id, plan.id, session.isDeload || weekIsDeload)
                        }
                        preparingSessionId = nil
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isPreparing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                        }

                        Text(isPreparing ? "PREPARING..." : "START SESSION")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(STColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isPreparing)
                .padding(.top, 2)

                Button {
                    templatePickerSession = session
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                        Text(session.templateId != nil ? "CHANGE TEMPLATE" : "LINK TEMPLATE")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(STColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(STColors.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .opacity(isCompleted ? 0.7 : 1.0)
    }

    // MARK: - Exercise Line

    private func exerciseLine(_ exercise: PlannedExerciseSet, muted: Bool) -> some View {
        HStack(spacing: 0) {
            Text(exercise.exerciseName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted ? STColors.textTertiary : STColors.textSecondary)

            Text(" — ")
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)

            Text("\(exercise.sets)x\(exercise.targetReps)")
                .font(.system(size: 12))
                .foregroundStyle(muted ? STColors.textTertiary : STColors.textSecondary)

            if exercise.targetWeight > 0 {
                Text(" @ \(formattedWeight(exercise.targetWeight))")
                    .font(.system(size: 12))
                    .foregroundStyle(muted ? STColors.textTertiary : STColors.textSecondary)
            }

            if let rpe = exercise.targetRPE {
                Text(" RPE \(Int(rpe))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(STColors.primary.opacity(0.8))
            }

            Spacer()
        }
    }

    // MARK: - Action Buttons

    private func actionButtons(_ plan: ProgressionPlan) -> some View {
        VStack(spacing: 10) {
            if plan.status == .active {
                Button {
                    showPauseConfirmation = true
                } label: {
                    Text("Pause Plan")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(STColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(STColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    showAbandonConfirmation = true
                } label: {
                    Text("Abandon Plan")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(STColors.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(STColors.danger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func statusColor(_ status: PlanStatus) -> Color {
        switch status {
        case .draft: return STColors.textTertiary
        case .active: return STColors.success
        case .paused: return .orange
        case .completed: return STColors.primary
        case .abandoned: return STColors.danger
        }
    }

    private func isOverdue(_ session: PlannedSession) -> Bool {
        guard !session.isCompleted,
              let scheduled = session.scheduledDate else { return false }
        return scheduled < Calendar.current.startOfDay(for: Date())
    }

    private func formattedWeight(_ weight: Double) -> String {
        if weight == weight.rounded() {
            return "\(Int(weight)) kg"
        }
        return String(format: "%.1f kg", weight)
    }
}
#endif
