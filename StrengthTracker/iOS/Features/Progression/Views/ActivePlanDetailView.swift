#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ActivePlanDetailView: View {
    let viewModel: ProgressionPlanViewModel
    let templateViewModel: TemplateViewModel
    let onStartSession: (WorkoutTemplate, UUID, UUID, Bool) async -> Void
    @State private var showPlanEditor = false
    @State private var expandedWeekId: UUID?
    @State private var preparingSessionId: UUID?
    @State private var showPauseConfirmation = false
    @State private var showAbandonConfirmation = false
    @State private var templatePickerSession: PlannedSession?
    @State private var rescheduleSession: PlannedSession?
    @State private var rescheduleDate: Date = Date()
    @Environment(\.dismiss) private var dismiss
    @Environment(DataRevision.self) private var dataRevision: DataRevision?

    var body: some View {
        ScrollView {
            if let plan = viewModel.activePlan {
                VStack(alignment: .leading, spacing: 20) {
                    // Plan header
                    planHeader(plan)

                    Button { showPlanEditor = true } label: {
                        Label("Edit remaining plan", systemImage: "calendar.badge.clock")
                            .frame(maxWidth: .infinity).padding(14)
                    }
                    .buttonStyle(.plain).foregroundStyle(STColors.primary)
                    .background(STColors.surface, in: RoundedRectangle(cornerRadius: STRadius.card))
                    .padding(.horizontal, 20)

                    // Overall progress
                    progressSection(plan)

                    // Pending coach suggestions
                    if !viewModel.pendingAdjustments.isEmpty {
                        pendingAdjustmentsSection
                    }

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
        .task(id: dataRevision?.value ?? 0) {
            await viewModel.loadActivePlan()
        }
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.inline)
        .stNavigationBarStyle()
        .sheet(isPresented: $showPlanEditor) {
            PlanScheduleEditor(viewModel: viewModel)
        }
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

            Text("\(plan.totalWeeks) calendar weeks · finishes \(PlanEditingService.dateLabel(plan.targetEndDate))")
                .font(.caption).foregroundStyle(STColors.textSecondary)
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

    // MARK: - Pending Adjustments

    private var pendingAdjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COACH SUGGESTIONS")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(STColors.textSecondary)

            ForEach(viewModel.pendingAdjustments) { adjustment in
                adjustmentCard(adjustment)
            }
        }
        .padding(.horizontal, 20)
    }

    private func adjustmentCard(_ adjustment: PlanAdjustment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: adjustmentIcon(adjustment.adjustmentType))
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.primary)

                Text(adjustmentTitle(adjustment.adjustmentType))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)

                Spacer()
            }

            Text(adjustment.coachingExplanation ?? adjustment.description)
                .font(.system(size: 12))
                .foregroundStyle(STColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = VerdictConflictRules.conflictNote(for: adjustment, verdict: viewModel.coachVerdict) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.warning)
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(STColors.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.acceptAdjustment(id: adjustment.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12))
                        Text("APPLY")
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

                Button {
                    Task { await viewModel.dismissAdjustment(id: adjustment.id) }
                } label: {
                    Text("DISMISS")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(STColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(STColors.textTertiary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
    }

    private func adjustmentIcon(_ type: AdjustmentType) -> String {
        switch type {
        case .deload: return "leaf.fill"
        case .loadDecrease: return "arrow.down.circle"
        case .loadIncrease: return "arrow.up.circle"
        case .blockExtension: return "calendar.badge.plus"
        case .exerciseSwap: return "arrow.triangle.2.circlepath"
        case .volumeAdjustment: return "slider.horizontal.3"
        case .frequencyChange: return "calendar"
        case .reforecast: return "chart.line.uptrend.xyaxis"
        }
    }

    private func adjustmentTitle(_ type: AdjustmentType) -> String {
        switch type {
        case .deload: return "Recovery Week"
        case .loadDecrease: return "Reduce Weight"
        case .loadIncrease: return "Increase Weight"
        case .blockExtension: return "Extend Block"
        case .exerciseSwap: return "Swap Exercise"
        case .volumeAdjustment: return "Adjust Volume"
        case .frequencyChange: return "Change Frequency"
        case .reforecast: return "Update Timeline"
        }
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
                        .fill(week.allSessionsClosed ? STColors.success : (isCurrentWeek ? STColors.primary : STColors.textTertiary.opacity(0.3)))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Week \(week.absoluteWeekNumber)")
                            .font(.system(size: 13, weight: isCurrentWeek ? .semibold : .regular))
                            .foregroundStyle(isCurrentWeek ? STColors.textPrimary : STColors.textSecondary)

                        if let range = week.dateRange {
                            Text(weekDateRangeText(range))
                                .font(.system(size: 10))
                                .foregroundStyle(STColors.textTertiary)
                        }
                    }

                    if week.containsDeloadSessions {
                        Text(week.isDeload ? "Deload" : "Partial deload")
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
        let isSkipped = session.isSkipped
        let isMuted = isCompleted || isSkipped || session.isOmitted
        let isPreparing = preparingSessionId == session.id

        return VStack(alignment: .leading, spacing: 8) {
            // Header: label + linked badge + completion/skipped badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sessionLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isMuted ? STColors.textTertiary : STColors.textPrimary)

                    if let date = session.scheduledDate {
                        Button {
                            if !isCompleted {
                                rescheduleDate = date
                                rescheduleSession = session
                            }
                        } label: {
                            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .font(.system(size: 12))
                                .foregroundStyle(isMuted ? .secondary : isOverdue(session) ? STColors.danger : .secondary)
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
                } else if isSkipped {
                    Text("SKIPPED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(STColors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(STColors.textTertiary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if session.isOmitted {
                Text("Rest day during deload · excluded from adherence").font(.caption).foregroundStyle(STColors.textSecondary)
            } else if let origin = session.programmingWeekNumber {
                Text(session.insertedGroupID != nil ? "Added week · based on programme week \(origin)" : "Programme week \(origin)")
                    .font(.caption).foregroundStyle(STColors.textSecondary)
            }
            // Exercise lines
            ForEach(session.plannedExercises) { exercise in
                exerciseLine(exercise, muted: isMuted)
            }

            // Duration + RPE info
            HStack {
                Label("~\(session.estimatedDurationMinutes) min", systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textTertiary)

                Spacer()

                if session.isDeload {
                    Text("Deload")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(STColors.primary.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(STColors.primary.opacity(0.1))
                        .clipShape(Capsule())
                }

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

            // Start Session button (hidden for skipped sessions)
            if !session.isClosed && plan.status == .active {
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
        .opacity(isMuted ? 0.7 : 1.0)
        .contextMenu {
            if !isCompleted && !session.isOmitted && plan.status == .active {
                Button {
                    Task { await viewModel.toggleSessionSkipped(sessionId: session.id) }
                } label: {
                    Label(
                        isSkipped ? "Undo skip" : "Skip session",
                        systemImage: isSkipped ? "arrow.uturn.backward" : "forward.end"
                    )
                }
            }
        }
    }

    // MARK: - Exercise Line

    private func exerciseLine(_ exercise: PlannedExerciseSet, muted: Bool) -> some View {
        let recording = exercise.weightRecording ?? viewModel.activePlan?.exercises.first { $0.exerciseId == exercise.exerciseId }?.weightRecording
        return HStack(spacing: 0) {
            Text(exercise.exerciseName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted ? STColors.textTertiary : STColors.textSecondary)

            Text(" — ")
                .font(.system(size: 12))
                .foregroundStyle(STColors.textTertiary)

            Text("\(exercise.sets)x\(exercise.targetReps)\(recording?.repetitions == .perSide ? "/side" : "")")
                .font(.system(size: 12))
                .foregroundStyle(muted ? STColors.textTertiary : STColors.textSecondary)

            if exercise.targetWeight > 0 {
                Text(" @ \(formattedWeight(exercise.targetWeight))\(recording.map { $0.weightEntry == .perDumbbell ? " each" : " total" } ?? "")")
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
        guard !session.isClosed,
              let scheduled = session.scheduledDate else { return false }
        return scheduled < Calendar.current.startOfDay(for: Date())
    }

    /// Compact "14–15 Jun" / "30 Jun–3 Jul" range label for a week's sessions.
    private func weekDateRangeText(_ range: ClosedRange<Date>) -> String {
        let calendar = Calendar.current
        let start = range.lowerBound
        let end = range.upperBound
        let endText = end.formatted(.dateTime.day().month(.abbreviated))
        if calendar.isDate(start, inSameDayAs: end) {
            return endText
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(calendar.component(.day, from: start))–\(endText)"
        }
        return "\(start.formatted(.dateTime.day().month(.abbreviated)))–\(endText)"
    }

    private func formattedWeight(_ weight: Double) -> String {
        viewModel.weightUnit.format(weight)
    }
}

/// The manual path uses the same validated preview/apply service as Grok.
struct PlanScheduleEditor: View {
    let viewModel: ProgressionPlanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var operation: PlanEditRequest.Operation = .convertDeload
    @State private var scope: PlanEditRequest.Scope = .week
    @State private var week = 1
    @State private var destinationWeek = 2
    @State private var weeks = 1
    @State private var sessionID: UUID?
    @State private var templateID: UUID?
    @State private var exerciseID: UUID?
    @State private var replacementID: UUID?
    @State private var date = Date()
    @State private var sets = ""
    @State private var reps = ""
    @State private var weight = ""
    @State private var rest = ""
    @FocusState private var editingNumber: Bool
    @State private var skipped = true
    @State private var templates: [WorkoutTemplate] = []
    @State private var exercises: [Exercise] = []
    @State private var preview: PlanEditPreview?
    @State private var error: String?
    @State private var busy = false
    private var sessions: [PlannedSession] {
        viewModel.activePlan?.blocks.flatMap(\.weeks).flatMap(\.sessions).filter { !$0.isCompleted } ?? []
    }
    private var labels: [PlanEditRequest.Operation: String] { [
        .convertDeload: "Make week a deload", .insertDeload: "Insert extra deload week", .moveDeload: "Move deload",
        .removeDeload: "Remove deload", .repeatWeek: "Repeat week", .extendPlan: "Extend plan",
        .rescheduleSession: "Reschedule session", .skipSession: "Skip / restore session",
        .changeTemplate: "Change workout template", .changeExercise: "Swap exercise", .changeTargets: "Change targets"
    ] }
    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section("Review changes") {
                        ForEach(Array(preview.summaryLines.enumerated()), id: \.offset) { _, line in Text(line) }
                        DisclosureGroup("Session details") {
                            ForEach(Array((preview.detailLines ?? []).enumerated()), id: \.offset) { _, line in Text(line) }
                        }
                    }
                    Section {
                        Button("Apply changes") { apply(preview) }.disabled(busy)
                        Button("Back to editing") { self.preview = nil; error = nil }.disabled(busy)
                    }
                } else {
                    Section("Change") {
                        Picker("Action", selection: $operation) {
                            ForEach(PlanEditRequest.Operation.allCases, id: \.self) { Text(labels[$0] ?? $0.rawValue).tag($0) }
                        }
                        Text(operation == .insertDeload ? "Adds time and preserves every original session. Deload uses your Settings percentages." : "Calendar weeks match the plan schedule. Completed and in-progress workouts are preserved.")
                            .font(.caption).foregroundStyle(STColors.textSecondary)
                    }
                    Section("Where") {
                        if [.changeTargets, .changeExercise, .changeTemplate].contains(operation) {
                            Picker("Scope", selection: $scope) {
                                Text("This week").tag(PlanEditRequest.Scope.week)
                                Text("This session").tag(PlanEditRequest.Scope.session)
                                Text("Remaining from week").tag(PlanEditRequest.Scope.remaining)
                            }
                        }
                        if [.rescheduleSession, .skipSession].contains(operation) || scope == .session {
                            Picker("Session", selection: $sessionID) {
                                Text("Select a session").tag(Optional<UUID>.none)
                                ForEach(sessions) { s in Text("\(PlanEditingService.dateLabel(s.scheduledDate)) · \(s.sessionLabel)").tag(Optional(s.id)) }
                            }
                        } else {
                            Stepper("Calendar week \(week)", value: $week, in: 1...max(1, viewModel.activePlan?.totalWeeks ?? 1))
                        }
                        if operation == .moveDeload {
                            Stepper("Move to week \(destinationWeek)", value: $destinationWeek, in: 1...max(1, viewModel.activePlan?.totalWeeks ?? 1))
                        }
                        if [.insertDeload, .repeatWeek, .extendPlan].contains(operation) { Stepper("\(weeks) extra week(s)", value: $weeks, in: 1...12) }
                        if operation == .rescheduleSession { DatePicker("New date", selection: $date, in: Date()..., displayedComponents: .date) }
                        if operation == .skipSession { Toggle("Skip session", isOn: $skipped) }
                    }
                    if operation == .changeTemplate {
                        Section("Template") {
                            Picker("Workout template", selection: $templateID) {
                                Text("Select template").tag(Optional<UUID>.none)
                                ForEach(templates) { Text($0.name).tag(Optional($0.id)) }
                            }
                            Text("Changes this plan's sessions. The reusable template is unchanged.").font(.caption)
                        }
                    }
                    if [.changeTargets, .changeExercise].contains(operation) {
                        Section("Exercise and normal targets") {
                            Picker("Exercise", selection: $exerciseID) {
                                Text(operation == .changeTargets ? "All exercises in scope" : "Select source exercise").tag(Optional<UUID>.none)
                                ForEach(exercises) { Text($0.name).tag(Optional($0.id)) }
                            }
                            if operation == .changeExercise {
                                Picker("Replace with", selection: $replacementID) {
                                    Text("Select replacement").tag(Optional<UUID>.none)
                                    ForEach(exercises) { Text($0.name).tag(Optional($0.id)) }
                                }
                                Text("Enter weight and reps for the replacement; weights do not transfer between exercises.").font(.caption)
                            }
                            TextField("Sets (leave blank to keep)", text: $sets).keyboardType(.numberPad).focused($editingNumber)
                            TextField("Reps (leave blank to keep)", text: $reps).keyboardType(.numberPad).focused($editingNumber)
                            TextField("Normal weight in kg", text: $weight).keyboardType(.decimalPad).focused($editingNumber)
                            Text("Use the target’s each/total weight convention. For a replacement, use its exercise-library convention.").font(.caption).foregroundStyle(STColors.textSecondary)
                            TextField("Normal rest in seconds", text: $rest).keyboardType(.numberPad).focused($editingNumber)
                            Text("Deload percentages apply after these normal targets. Explicit targets stay fixed when adaptive updates run.").font(.caption)
                        }
                    }
                    Section { Button("Preview changes", action: makePreview).disabled(busy) }
                }
                if let error { Section { Text(error).foregroundStyle(STColors.danger) } }
                if busy { ProgressView() }
            }
            .onChange(of: operation) { _, _ in
                scope = .week; sets = ""; reps = ""; weight = ""; rest = ""; error = nil
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingNumber = false } } }
            .scrollContentBackground(.hidden).background(STColors.background)
            .foregroundStyle(STColors.textPrimary).tint(STColors.primary)
            .navigationTitle("Edit plan").navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .task {
                week = viewModel.activePlan?.currentWeek?.absoluteWeekNumber ?? 1
                do { let catalog = try await viewModel.planEditCatalog(); templates = catalog.templates; exercises = catalog.exercises }
                catch { self.error = error.localizedDescription }
            }
        }
        .preferredColorScheme(.dark)
    }
    private func makePreview() {
        error = nil
        let fields = [(sets, Int(sets) != nil), (reps, Int(reps) != nil), (rest, Int(rest) != nil), (weight, Double(weight.replacingOccurrences(of: ",", with: ".")) != nil)]
        guard fields.allSatisfy({ $0.0.isEmpty || $0.1 }) else { error = "Enter valid numbers, or leave fields blank to keep their targets."; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let actualScope: PlanEditRequest.Scope = [.rescheduleSession, .skipSession].contains(operation) ? .session : [.changeTargets, .changeExercise, .changeTemplate].contains(operation) ? scope : .week
                preview = try await viewModel.previewPlanEdit(.init(operation: operation, week: week, destinationWeek: destinationWeek,
                    sessionID: sessionID, newDate: date, weeks: weeks, scope: actualScope, templateID: templateID,
                    exerciseID: exerciseID, replacementExerciseID: replacementID, sets: Int(sets), reps: Int(reps),
                    weightKg: Double(weight.replacingOccurrences(of: ",", with: ".")), restSeconds: Int(rest), skipped: skipped))
            } catch { self.error = error.localizedDescription }
        }
    }
    private func apply(_ preview: PlanEditPreview) {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await viewModel.applyPlanEdit(preview); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
#endif
