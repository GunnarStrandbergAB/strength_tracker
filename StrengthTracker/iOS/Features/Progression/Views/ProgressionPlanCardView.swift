#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct ProgressionPlanCardView: View {
    let viewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let templateViewModel: TemplateViewModel
    let proFeatureGate: ProFeatureGate?
    let storeService: StoreService?
    let onStartSession: (WorkoutTemplate, UUID, UUID, Bool) async -> Void
    @State private var showCreationSheet = false
    @State private var showActivePlanDetail = false
    @State private var showUpgradeSheet = false

    var body: some View {
        Group {
            if let plan = viewModel.activePlan, plan.isActive {
                activePlanCard(plan)
            } else if !viewModel.hasLoadedOnce {
                EmptyView()
            } else {
                noPlanCard
            }
        }
    }

    // MARK: - No Plan CTA

    private var isLocked: Bool {
        if let proFeatureGate {
            return !proFeatureGate.hasProAccess
        }
        return false
    }

    private var noPlanCard: some View {
        Button {
            if isLocked {
                showUpgradeSheet = true
            } else {
                showCreationSheet = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isLocked ? "lock.fill" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22))
                    .foregroundStyle(isLocked ? STColors.textTertiary : STColors.success)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("CREATE TRAINING PLAN")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isLocked ? STColors.textTertiary : STColors.success)

                        if isLocked {
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(STColors.background)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(STColors.primary)
                                .clipShape(Capsule())
                        }
                    }

                    Text("Periodized programming with auto-progression")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)
                }

                Spacer()

                Image(systemName: isLocked ? "crown.fill" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isLocked ? STColors.primary : STColors.success.opacity(0.7))
            }
            .padding(STSpacing.cardPadding)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(isLocked ? STColors.primary.opacity(0.3) : STColors.success.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCreationSheet) {
            PlanCreationView(
                viewModel: viewModel,
                exerciseListViewModel: exerciseListViewModel,
                templateViewModel: templateViewModel
            )
        }
        .sheet(isPresented: $showUpgradeSheet) {
            if let storeService {
                ProUpgradeView(storeService: storeService)
            }
        }
    }

    // MARK: - Active Plan Card

    @State private var isStarting = false
    @State private var movingSession: PlannedSession?
    @State private var moveDate = Date()
    @State private var skippingSession: PlannedSession?
    @State private var moveError: String?

    /// The plan at a glance: this week day by day, the next session with a start
    /// button, how far the lifts have come, and where the plan stands.
    private func activePlanCard(_ plan: ProgressionPlan) -> some View {
        let summary = PlanDashboardSummary(plan: plan, progress: viewModel.planProgress)
        return VStack(alignment: .leading, spacing: 14) {
            header(plan, summary)
            weekStrip(summary)
            if let next = summary.next { nextSession(next, plan: plan, summary: summary) }
            if let review = viewModel.lastSessionReview { lastSession(review) }
            if !summary.lifts.isEmpty { liftRows(summary) }
            footer(summary)
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .contentShape(Rectangle())
        .onTapGesture { showActivePlanDetail = true }
        .navigationDestination(isPresented: $showActivePlanDetail) {
            ActivePlanDetailView(viewModel: viewModel, templateViewModel: templateViewModel, onStartSession: onStartSession)
        }
        .sheet(item: $movingSession) { session in moveSheet(session) }
        .confirmationDialog("Skip this session?", isPresented: Binding(get: { skippingSession != nil }, set: { if !$0 { skippingSession = nil } }),
            titleVisibility: .visible) {
            Button("Skip session", role: .destructive) {
                if let session = skippingSession { change { await viewModel.toggleSessionSkipped(sessionId: session.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A skipped session counts as missed. You can undo it on the plan screen.")
        }
    }

    /// Runs a change to the plan and keeps what went wrong, if anything, on the card.
    private func change(_ work: @escaping () async -> Void) {
        moveError = nil
        Task {
            await work()
            if let message = viewModel.errorMessage {
                moveError = message
                viewModel.errorMessage = nil
            }
        }
    }

    /// Picks the new day for a session that was missed.
    private func moveSheet(_ session: PlannedSession) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.scheduledDate.map { "\(session.displayLabel) was planned for \($0.formatted(.dateTime.weekday(.wide).day().month(.wide)))." }
                    ?? session.displayLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textSecondary)
                DatePicker("New day", selection: $moveDate, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(STColors.primary)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(STColors.background)
            .navigationTitle("Move session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { movingSession = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        let date = moveDate
                        movingSession = nil
                        change { await viewModel.rescheduleSession(sessionId: session.id, to: date) }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("dashboard-plan-move-save")
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .tint(STColors.primary)
    }

    private func startMoving(_ session: PlannedSession) {
        moveDate = Calendar.current.startOfDay(for: Date())
        movingSession = session
    }

    private func header(_ plan: ProgressionPlan, _ summary: PlanDashboardSummary) -> some View {
        Button {
            showActivePlanDetail = true
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRAINING PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(STColors.textSecondary)
                    Text(plan.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(STColors.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(summary.week.map { "Week \($0) of \(summary.totalWeeks)" } ?? "\(summary.totalWeeks) weeks")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(STColors.textTertiary)
                    }
                    if summary.isDeloadWeek {
                        badge("Deload week", color: STColors.primary)
                    } else if let weeks = summary.weeksUntilDeload {
                        Text(weeks == 1 ? "Deload next week" : "Deload in \(weeks) weeks")
                            .font(.system(size: 11))
                            .foregroundStyle(STColors.textSecondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(plan.name)")
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: This week

    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    private static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private func weekStrip(_ summary: PlanDashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(summary.days) { day in
                    Group {
                        // A finished day opens its workout; the others open the plan with the card.
                        if let workout = day.workoutID {
                            NavigationLink(value: workout) { dayCircle(day) }.buttonStyle(.plain)
                        } else if day.status == .missed, let session = session(day.sessionID) {
                            // A missed day asks where its session should go.
                            Button { startMoving(session) } label: { dayCircle(day) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Moves the session to another day")
                        } else {
                            dayCircle(day)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(weekLine(summary))
                .font(.system(size: 12))
                .foregroundStyle(STColors.textSecondary)
        }
    }

    private func session(_ id: UUID?) -> PlannedSession? {
        guard let id else { return nil }
        return viewModel.activePlan?.blocks.flatMap(\.weeks).flatMap(\.sessions).first { $0.id == id }
    }

    private func weekLine(_ summary: PlanDashboardSummary) -> String {
        guard summary.plannedThisWeek > 0 else { return "Nothing planned this week" }
        var text = "\(summary.doneThisWeek) of \(summary.plannedThisWeek) sessions done this week"
        let missed = summary.days.filter { $0.status == .missed }.count
        if missed > 0 { text += " · \(missed) missed" }
        return text
    }

    private func dayCircle(_ day: PlanDashboardSummary.Day) -> some View {
        VStack(spacing: 5) {
            Text(Self.dayLetters[day.index])
                .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                .foregroundStyle(day.isToday ? STColors.textPrimary : STColors.textTertiary)
            ZStack {
                switch day.status {
                case .done:
                    Circle().fill(STColors.primary)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(STColors.background)
                case .today:
                    Circle().stroke(STColors.primary, lineWidth: 2)
                    Circle().fill(STColors.primary).frame(width: 8, height: 8)
                case .planned:
                    Circle().stroke(STColors.textSecondary, lineWidth: 1.5)
                case .missed:
                    Circle().stroke(STColors.danger, lineWidth: 1.5)
                    Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold)).foregroundStyle(STColors.danger)
                case .skipped:
                    Circle().stroke(STColors.textTertiary, lineWidth: 1.5)
                    Image(systemName: "forward.end.fill").font(.system(size: 8)).foregroundStyle(STColors.textTertiary)
                case .rest:
                    Circle().fill(STColors.textTertiary.opacity(0.35)).frame(width: 6, height: 6)
                }
            }
            .frame(width: 26, height: 26)
            // The line under today, so a rest day today is still easy to find.
            Capsule().fill(day.isToday ? STColors.primary : Color.clear).frame(width: 14, height: 2)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.dayNames[day.index]): \(dayDescription(day))")
    }

    private func dayDescription(_ day: PlanDashboardSummary.Day) -> String {
        let deload = day.isDeload ? "deload " : ""
        switch day.status {
        case .rest: return "rest"
        case .planned: return "\(deload)session planned"
        case .today: return "\(deload)session today"
        case .done: return "\(deload)session done"
        case .missed: return "\(deload)session missed"
        case .skipped: return "session skipped"
        }
    }

    // MARK: Next session

    private func nextSession(_ session: PlannedSession, plan: ProgressionPlan, summary: PlanDashboardSummary) -> some View {
        let shown = Array(session.plannedExercises.prefix(3))
        let more = session.plannedExercises.count - shown.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(summary.nextIsOverdue ? "OVERDUE" : "NEXT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(summary.nextIsOverdue ? STColors.danger : STColors.textSecondary)
                Text(when(session.scheduledDate))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(summary.nextIsOverdue ? STColors.danger : STColors.primary)
                Spacer()
                if session.isDeload { badge("Deload", color: STColors.primary) }
            }
            Text(session.displayLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(STColors.textPrimary)
            ForEach(shown) { exercise in
                HStack {
                    Text(exercise.exerciseName)
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(target(exercise, in: session))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(STColors.textPrimary)
                }
            }
            Text((more > 0 ? "+ \(more) more · " : "") + "about \(session.estimatedDurationMinutes) min")
                .font(.system(size: 11))
                .foregroundStyle(STColors.textTertiary)

            if plan.status == .active {
                Button {
                    isStarting = true
                    Task {
                        if let template = await viewModel.prepareSessionTemplate(for: session) {
                            await onStartSession(template, session.id, plan.id, session.isDeload)
                        }
                        isStarting = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isStarting { ProgressView().tint(.white).scaleEffect(0.8) } else { Image(systemName: "play.fill").font(.system(size: 12)) }
                        Text("START SESSION")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(STColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
                .accessibilityIdentifier("dashboard-plan-start")

                // A session whose day has passed can be moved to a new day or skipped.
                if summary.nextIsOverdue {
                    HStack(spacing: 8) {
                        secondaryAction("MOVE", systemImage: "calendar") { startMoving(session) }
                            .accessibilityIdentifier("dashboard-plan-move")
                        secondaryAction("SKIP", systemImage: "forward.end") { skippingSession = session }
                            .accessibilityIdentifier("dashboard-plan-skip")
                    }
                }
            }
            if let moveError {
                Text(moveError)
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.danger)
            }
        }
        .padding(12)
        .background(STColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func secondaryAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(STColors.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(STColors.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: Last session

    /// How the last finished session went: misses first, then what was hit.
    private func lastSession(_ review: PlanSessionReview) -> some View {
        let ordered = review.lines.filter { !$0.isHit } + review.lines.filter(\.isHit)
        let shown = Array(ordered.prefix(4))
        let allHit = review.hitCount == review.lines.count
        return NavigationLink(value: review.workoutID) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("LAST SESSION")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(STColors.textSecondary)
                    Text(review.date.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? review.name)
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                    Spacer()
                    Text("\(review.hitCount) of \(review.lines.count) targets hit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(allHit ? STColors.success : STColors.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(STColors.textTertiary)
                }
                ForEach(shown) { line in
                    HStack(spacing: 6) {
                        Image(systemName: line.isHit ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(line.isHit ? STColors.success : STColors.danger)
                        Text(line.name)
                            .font(.system(size: 13))
                            .foregroundStyle(STColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(result(line))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(line.isHit ? STColors.textSecondary : STColors.danger)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(line.name): \(line.isHit ? "target hit" : "target missed"), \(result(line))")
                }
                if ordered.count > shown.count {
                    Text("+ \(ordered.count - shown.count) more")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the workout")
    }

    /// What was done: the target when it was hit, otherwise where it fell short.
    private func result(_ line: PlanSessionReview.Line) -> String {
        let unit = viewModel.weightUnit
        guard let done = line.done else { return "not done" }
        let load = done.weightKg > 0 ? "\(unit.format(done.weightKg)) × " : ""
        if line.isHit { return "\(load)\(done.lowestReps)\(done.weightKg > 0 ? "" : " reps")" }
        if done.weightKg < line.target.weightKg - 0.26 { return "\(unit.formatValue(done.weightKg)) of \(unit.format(line.target.weightKg))" }
        if done.lowestReps < line.target.reps { return "\(done.lowestReps) of \(line.target.reps) reps" }
        return "sets left out"
    }

    /// "Today", "Tomorrow", "Thursday", or "Thu 10 Dec" further away or in the past.
    private func when(_ date: Date?) -> String {
        guard let date else { return "Not scheduled" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return date.formatted(.dateTime.weekday(.wide))
        default: return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    /// "3 × 8 · 82.5 kg", "3 × 12" without a weight, "3 × 60 s" for a timed exercise.
    private func target(_ exercise: PlannedExerciseSet, in session: PlannedSession) -> String {
        if let timed = PlanWizard.timedTarget(of: exercise, in: session) { return "\(exercise.sets) × \(timed)" }
        let weight = exercise.targetWeight > 0 ? " · \(viewModel.weightUnit.format(exercise.targetWeight))" : ""
        return "\(exercise.sets) × \(exercise.targetReps)\(weight)"
    }

    // MARK: Lifts

    private func liftRows(_ summary: PlanDashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.targetsOnHold ? "SINCE THE START · TARGETS ON HOLD" : "SINCE THE START")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(STColors.textSecondary)
            ForEach(summary.lifts) { lift in
                HStack(spacing: 6) {
                    Text(lift.name)
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(change(lift))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(lift.hasMoved ? STColors.success : STColors.textSecondary)
                    Image(systemName: lift.hasMoved ? "arrow.up.right" : "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(lift.hasMoved ? STColors.success : STColors.textTertiary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "80 → 85 kg", "8 → 10 reps" at the same weight, or "1RM 100 → 104 kg".
    private func change(_ lift: PlanDashboardSummary.Lift) -> String {
        let unit = viewModel.weightUnit
        func weight(_ kg: Double) -> String { unit.formatValue(kg) }
        if lift.isEstimatedMax { return "1RM \(weight(lift.start.weightKg)) → \(unit.format(lift.now.weightKg))" }
        if abs(lift.now.weightKg - lift.start.weightKg) > 0.01 {
            return "\(weight(lift.start.weightKg)) → \(unit.format(lift.now.weightKg)) × \(lift.now.reps)"
        }
        let load = lift.now.weightKg > 0 ? "\(unit.format(lift.now.weightKg)) · " : ""
        return lift.hasMoved ? "\(load)\(lift.start.reps) → \(lift.now.reps) reps" : "\(load)\(lift.now.reps) reps"
    }

    // MARK: Footer

    private func footer(_ summary: PlanDashboardSummary) -> some View {
        let adherence = viewModel.adherencePercent
        // How much of the plan is behind you: the same count as the text below the bar.
        let share = summary.sessionsTotal > 0 ? Double(summary.sessionsDone) / Double(summary.sessionsTotal) : 0
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(STColors.background).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3).fill(STColors.primary)
                        .frame(width: geo.size.width * min(max(share, 0), 1), height: 5)
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(summary.sessionsDone) of \(summary.sessionsTotal) sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textSecondary)
                Spacer()
                if summary.overdueCount > 0 {
                    Text("\(summary.overdueCount) overdue")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(STColors.danger)
                    Text("·").font(.system(size: 11)).foregroundStyle(STColors.textTertiary)
                }
                Text("\(adherence)% adherence")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(adherence >= 85 ? STColors.success : adherence >= 60 ? STColors.primary : STColors.danger)
            }
        }
    }
}
#endif
