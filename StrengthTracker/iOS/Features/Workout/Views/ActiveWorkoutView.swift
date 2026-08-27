import SwiftUI
import UIKit
import StrengthTrackerShared

struct ActiveWorkoutView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: WorkoutViewModel
    @State private var exerciseListViewModel: ExerciseListViewModel
    let restTimerService: RestTimerService
    var analyticsViewModel: WorkoutAnalyticsViewModel?
    @State private var showingExercisePicker = false
    @State private var showingCancelConfirmation = false
    @State private var showingFinishError = false
    @State private var finishErrorMessage = ""
    @State private var showingNotes = false
    @State private var showingRestTimer = false
    @State private var notesText = ""

    // Drag-to-reorder state (grip handle in each card header)
    @State private var draggedExerciseId: UUID?
    @State private var dragTranslation: CGFloat = 0      // follows the finger, never animated
    @State private var dragTargetIndex: Int?             // proposed drop slot, animated
    @State private var cardHeights: [UUID: CGFloat] = [:]

    init(viewModel: WorkoutViewModel, exerciseListViewModel: ExerciseListViewModel, restTimerService: RestTimerService, analyticsViewModel: WorkoutAnalyticsViewModel? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self._exerciseListViewModel = State(initialValue: exerciseListViewModel)
        self.restTimerService = restTimerService
        self.analyticsViewModel = analyticsViewModel
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = viewModel.currentWorkout, viewModel.isActive {
                    workoutContent(workout)
                } else if let watchWorkout = viewModel.watchActiveWorkout {
                    watchWorkoutBanner(watchWorkout)
                } else {
                    startView
                }
            }
            .navigationTitle(viewModel.currentWorkout?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .stNavigationBarStyle()
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                    viewModel.addExercise(exercise)
                }
            }
            .confirmationDialog(
                "Cancel Workout",
                isPresented: $showingCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancel Workout", role: .destructive) {
                    restTimerService.stop()
                    Task {
                        await viewModel.cancelWorkout()
                        WidgetDataService().updateActiveWorkoutState(nil)
                    }
                }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel this workout? All progress will be lost.")
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Failed to Save Workout", isPresented: $showingFinishError) {
                Button("OK") {}
            } message: {
                Text(finishErrorMessage)
            }
        }
    }

    // MARK: - Watch Workout Banner

    private func watchWorkoutBanner(_ workout: Workout) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "applewatch")
                .font(.system(size: 48))
                .foregroundStyle(STColors.primary)

            Text("Workout In Progress on Watch")
                .font(.headline)
                .foregroundStyle(STColors.textPrimary)

            VStack(spacing: 8) {
                Text(workout.name)
                    .font(.title3.bold())
                    .foregroundStyle(STColors.textPrimary)

                if let currentExercise = workout.activeExercise(preferredId: nil) {
                    Text(currentExercise.exercise.name)
                        .font(.subheadline)
                        .foregroundStyle(STColors.textSecondary)
                }

                let totalSets = workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
                Text("\(totalSets) sets completed")
                    .font(.subheadline)
                    .foregroundStyle(STColors.textSecondary)

                let elapsed = Date().timeIntervalSince(workout.startedAt)
                let minutes = Int(elapsed) / 60
                Text("\(minutes) min elapsed")
                    .font(.caption)
                    .foregroundStyle(STColors.textTertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(STColors.border, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(STColors.background)
    }

    // MARK: - Start View

    private var startView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer()
                    .frame(height: 20)

                // Pre-workout context card (M4) when analytics loaded
                if let analytics = analyticsViewModel,
                   !analytics.insights.recoveryPatterns.isEmpty {
                    PreWorkoutContextCard(
                        recoveryPatterns: analytics.insights.recoveryPatterns,
                        trainingLoad: analytics.insights.trainingLoad,
                        adherence: analytics.adherenceAnalysis,
                        onStartWorkout: {
                            Task {
                                await viewModel.startWorkout(name: "Quick Workout", from: nil)
                                updateWidgetWorkoutState()
                            }
                        },
                        onStartFromPlan: nil
                    )
                } else {
                    // Minimal start view for new users
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 60))
                        .foregroundStyle(STColors.textSecondary)
                    Text("No Active Workout")
                        .font(.title2)
                        .foregroundStyle(STColors.textPrimary)
                    Button {
                        Task {
                            await viewModel.startWorkout(name: "Quick Workout", from: nil)
                            updateWidgetWorkoutState()
                        }
                    } label: {
                        Text("Start Workout")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(STColors.background)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(STColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(STColors.background)
        .task {
            // Load analytics for pre-workout context
            await analyticsViewModel?.loadDashboardInsights()
        }
    }

    // MARK: - Workout Content

    private func workoutContent(_ workout: Workout) -> some View {
        ScrollViewReader { proxy in
            workoutScrollView(workout: workout, proxy: proxy)
        }
        .task {
            await viewModel.loadPreviousData()
            await viewModel.loadCoachingData()
        }
        .onAppear {
            if let notes = workout.notes, !notes.isEmpty {
                notesText = notes
                showingNotes = true
            }
        }
        .safeAreaInset(edge: .bottom) {
            if restTimerService.isRunning || (restTimerService.remainingSeconds > 0 && !restTimerService.isCompleted) {
                stickyRestTimer
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                finishButton
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingRestTimer) {
            RestTimerView(service: restTimerService)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                restTimerService.handleForegroundReturn()
            }
        }
    }

    private func workoutScrollView(workout: Workout, proxy: ScrollViewProxy) -> some View {
        let activeId = viewModel.activeExercise?.id
        let canReorder = workout.exercises.count > 1
        return ScrollView {
            VStack(spacing: STSpacing.cardGap) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, workoutExercise in
                    exerciseCard(
                        for: workoutExercise,
                        isActive: workoutExercise.id == activeId,
                        reorderable: canReorder
                    )
                    .id(workoutExercise.id)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        cardHeights[workoutExercise.id] = height
                    }
                    .offset(y: dragOffset(index: index, id: workoutExercise.id, in: workout))
                    .zIndex(workoutExercise.id == draggedExerciseId ? 1 : 0)
                    .scaleEffect(workoutExercise.id == draggedExerciseId ? 1.02 : 1)
                    .shadow(
                        color: .black.opacity(workoutExercise.id == draggedExerciseId ? 0.25 : 0),
                        radius: 8, y: 4
                    )
                }
                notesCard
                deloadToggle
                addExerciseButton
                cancelWorkoutButton
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .scrollDisabled(draggedExerciseId != nil)
        .onChange(of: workout.exercises.count) { oldCount, newCount in
            // Add/remove/watch-sync mid-drag would leave stale offsets — reset first
            draggedExerciseId = nil
            dragTranslation = 0
            dragTargetIndex = nil
            guard newCount > oldCount else { return }  // Only scroll on addition
            if let lastExercise = workout.exercises.last {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(lastExercise.id, anchor: .top)
                }
            }
        }
        .background(STColors.background)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Drag to Reorder

    /// Dragged card follows the finger; siblings between source and target shift by
    /// the dragged card's height (plus gap) to open a slot.
    private func dragOffset(index: Int, id: UUID, in workout: Workout) -> CGFloat {
        guard let draggedId = draggedExerciseId,
              let source = workout.exercises.firstIndex(where: { $0.id == draggedId }) else { return 0 }
        if id == draggedId { return dragTranslation }
        guard let target = dragTargetIndex else { return 0 }
        let draggedHeight = (cardHeights[draggedId] ?? 0) + STSpacing.cardGap
        if source < target, index > source, index <= target { return -draggedHeight }
        if target < source, index >= target, index < source { return draggedHeight }
        return 0
    }

    private func handleExerciseDragChanged(id: UUID, translation: CGFloat, workout: Workout) {
        if draggedExerciseId == nil {
            draggedExerciseId = id
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        dragTranslation = translation
        let ids = workout.exercises.map(\.id)
        guard let source = ids.firstIndex(of: id) else { return }
        let proposed = proposedIndex(translation: translation, source: source, ids: ids)
        if proposed != dragTargetIndex {
            withAnimation(.spring(duration: 0.25)) { dragTargetIndex = proposed }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Walk cumulative card heights (+ gap) in the drag direction, crossing into the
    /// next slot once the drag passes a card's midpoint — handles variable heights.
    private func proposedIndex(translation: CGFloat, source: Int, ids: [UUID]) -> Int {
        var index = source
        var remaining = translation
        if translation > 0 {
            for i in (source + 1)..<ids.count {
                let height = (cardHeights[ids[i]] ?? 0) + STSpacing.cardGap
                guard remaining > height / 2 else { break }
                index = i
                remaining -= height
            }
        } else {
            for i in stride(from: source - 1, through: 0, by: -1) {
                let height = (cardHeights[ids[i]] ?? 0) + STSpacing.cardGap
                guard remaining < -height / 2 else { break }
                index = i
                remaining += height
            }
        }
        return index
    }

    private func handleExerciseDragEnded(workout: Workout) {
        let source = draggedExerciseId.flatMap { id in workout.exercises.firstIndex { $0.id == id } }
        let destination = dragTargetIndex
        withAnimation(.spring(duration: 0.3)) {
            draggedExerciseId = nil
            dragTranslation = 0
            dragTargetIndex = nil
        }
        if let source, let destination, source != destination {
            Task { await viewModel.moveExercise(from: source, to: destination) }
        }
    }

    private func exerciseCard(for workoutExercise: WorkoutExercise, isActive: Bool, reorderable: Bool) -> some View {
        ExerciseCardView(
            workoutExercise: workoutExercise,
            isActiveExercise: isActive,
            previousSetData: previousDataForExercise(workoutExercise.id),
            onWeightChange: { setId, weight in
                Task {
                    await viewModel.updateSetWeight(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        weight: weight
                    )
                }
            },
            onRepsChange: { setId, reps in
                Task {
                    await viewModel.updateSetReps(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        reps: reps
                    )
                }
            },
            onIntensityChange: { setId, value in
                Task {
                    await viewModel.updateSetIntensity(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        value: value,
                        metric: intensityMetric
                    )
                }
            },
            onToggleComplete: { setId in
                handleSetToggle(workoutExercise: workoutExercise, setId: setId)
            },
            onAddSet: {
                Task {
                    await viewModel.addEmptySet(exerciseId: workoutExercise.id)
                }
            },
            onRemoveSet: { setId in
                Task {
                    await viewModel.removeSet(
                        exerciseId: workoutExercise.id,
                        setId: setId
                    )
                }
            },
            onRemoveExercise: {
                Task {
                    await viewModel.removeExercise(exerciseId: workoutExercise.id)
                }
            },
            onSetTypeChange: { setId, setType in
                Task {
                    await viewModel.updateSetType(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        setType: setType
                    )
                }
            },
            onAddDropEntry: { setId in
                Task {
                    await viewModel.addDropEntry(exerciseId: workoutExercise.id, setId: setId)
                }
            },
            onToggleFailure: { setId in
                Task {
                    await viewModel.toggleSetFailure(exerciseId: workoutExercise.id, setId: setId)
                }
            },
            onDropEntryWeightChange: { setId, entryId, weight in
                Task {
                    await viewModel.updateDropEntryWeight(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId, weight: weight
                    )
                }
            },
            onDropEntryRepsChange: { setId, entryId, reps in
                Task {
                    await viewModel.updateDropEntryReps(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId, reps: reps
                    )
                }
            },
            onDropEntryIntensityChange: { setId, entryId, value in
                Task {
                    await viewModel.updateDropEntryIntensity(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId, value: value, metric: intensityMetric
                    )
                }
            },
            onDropEntryToggleFailure: { setId, entryId in
                Task {
                    await viewModel.toggleDropEntryFailure(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId
                    )
                }
            },
            onRemoveDropEntry: { setId, entryId in
                Task {
                    await viewModel.removeDropEntry(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId
                    )
                }
            },
            onNoteChange: { notes in
                Task {
                    await viewModel.updateExerciseNotes(
                        exerciseId: workoutExercise.id,
                        notes: notes
                    )
                }
            },
            onMoveSet: { fromIndex, toIndex in
                Task {
                    await viewModel.moveSets(
                        exerciseId: workoutExercise.id,
                        from: fromIndex,
                        to: toIndex
                    )
                }
            },
            onDragChanged: reorderable ? { translation in
                guard let workout = viewModel.currentWorkout else { return }
                handleExerciseDragChanged(id: workoutExercise.id, translation: translation, workout: workout)
            } : nil,
            onDragEnded: reorderable ? {
                guard let workout = viewModel.currentWorkout else { return }
                handleExerciseDragEnded(workout: workout)
            } : nil,
            coachingData: viewModel.exerciseCoachingCache[workoutExercise.id],
            alwaysShowRPE: viewModel.userPreferencesService?.alwaysShowRPE ?? false,
            intensityMetric: intensityMetric,
            weightUnit: viewModel.userPreferencesService?.weightUnit ?? .kg
        )
    }

    private var intensityMetric: IntensityMetric {
        viewModel.userPreferencesService?.intensityMetric ?? .rpe
    }

    private func handleSetToggle(workoutExercise: WorkoutExercise, setId: UUID) {
        Task {
            await viewModel.toggleSetCompletion(
                exerciseId: workoutExercise.id,
                setId: setId
            )
            if let ex = viewModel.currentWorkout?.exercises.first(where: { $0.id == workoutExercise.id }),
               let completedSet = ex.sets.first(where: { $0.id == setId }),
               completedSet.isCompleted,
               viewModel.userPreferencesService?.autoStartRestTimer ?? true {
                var restSeconds = workoutExercise.restTimerSeconds ?? viewModel.userPreferencesService?.defaultRestSeconds ?? UserPreferencesService.defaultRestSecondsValue
                if isDeload, let pct = viewModel.userPreferencesService?.deloadRestPercentage {
                    restSeconds = max(15, restSeconds * pct / 100)
                }
                let setIndex = ex.sets.firstIndex(where: { $0.id == setId }) ?? 0
                restTimerService.start(
                    seconds: restSeconds,
                    exerciseName: workoutExercise.exercise.name,
                    setNumber: setIndex + 1
                )
            }
            updateWidgetWorkoutState()
        }
    }

    private var isDeload: Bool {
        viewModel.currentWorkout?.isDeload ?? false
    }

    private var deloadToggle: some View {
        Button {
            Task { await viewModel.toggleDeload() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDeload ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isDeload ? STColors.primary : STColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDeload ? "Deload Workout" : "Mark as Deload")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isDeload ? STColors.primary : STColors.textSecondary)
                    Text("Excludes from progression & PR tracking")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                }
                Spacer()
                if isDeload {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(STColors.textTertiary)
                }
            }
            .padding(STSpacing.cardPadding)
            .background(isDeload ? STColors.primary.opacity(0.1) : STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(isDeload ? STColors.primary.opacity(0.3) : STColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var finishButton: some View {
        Button {
            restTimerService.stop()
            Task {
                do {
                    try await viewModel.completeWorkout()
                    WidgetDataService().updateActiveWorkoutState(nil)
                } catch {
                    finishErrorMessage = error.localizedDescription
                    showingFinishError = true
                }
            }
        } label: {
            Text("Finish")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(STColors.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(STColors.primary)
                .clipShape(Capsule())
        }
    }

    // MARK: - Add Exercise Button

    private var addExerciseButton: some View {
        Button {
            showingExercisePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Add Exercise")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(STColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(STColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cancel Workout Button

    private var cancelWorkoutButton: some View {
        Button {
            showingCancelConfirmation = true
        } label: {
            Text("Cancel Workout")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(STColors.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showingNotes {
                HStack {
                    Text("NOTES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(STColors.textSecondary)
                    Spacer()
                    Button {
                        showingNotes = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(STColors.textTertiary)
                    }
                }
                TextField("Add workout notes...", text: $notesText, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textPrimary)
                    .onChange(of: notesText) { _, newValue in
                        Task {
                            await viewModel.updateNotes(newValue)
                        }
                    }
            } else {
                Button {
                    showingNotes = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                        Text(notesText.isEmpty ? "Add Notes" : "Edit Notes")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(STColors.textSecondary)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .stroke(STColors.border, lineWidth: 1)
        )
    }

    // MARK: - Sticky Rest Timer

    private var stickyRestTimer: some View {
        HStack {
            HStack(spacing: 12) {
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.black.opacity(0.1), lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Circle()
                        .trim(from: 0, to: restTimerService.progress)
                        .stroke(
                            Color.black,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "timer")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.black)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("RESTING")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color.black.opacity(0.7))

                    Text(restTimerService.formattedTime)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(Color.black)
                }
            }
            .onTapGesture {
                showingRestTimer = true
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    restTimerService.addTime(seconds: 15)
                } label: {
                    Text("+15s")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    restTimerService.stop()
                    updateWidgetWorkoutState()
                } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(STColors.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(STColors.primary.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: STRadius.timer))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    // MARK: - Widget Data Updates

    private func updateWidgetWorkoutState() {
        let service = WidgetDataService()
        guard let workout = viewModel.currentWorkout, viewModel.isActive else {
            service.updateActiveWorkoutState(nil)
            return
        }
        service.updateActiveWorkoutState(service.buildActiveWorkoutState(
            workout: workout,
            isResting: restTimerService.isRunning,
            restEndDate: restTimerService.isRunning ? restTimerService.endDate : nil,
            activeExerciseId: viewModel.activeExerciseId
        ))
    }

    private func previousDataForExercise(_ exerciseId: UUID) -> [Int: String] {
        var result: [Int: String] = [:]
        if let exercise = viewModel.currentWorkout?.exercises.first(where: { $0.id == exerciseId }) {
            for (index, _) in exercise.sets.enumerated() {
                let key = "\(exerciseId)-\(index)"
                if let data = viewModel.previousSetDataCache[key] {
                    result[index] = data
                }
            }
        }
        return result
    }
}
