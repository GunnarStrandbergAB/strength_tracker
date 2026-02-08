import SwiftUI
import StrengthTrackerShared

struct ActiveWorkoutView: View {
    @State private var viewModel: WorkoutViewModel
    @State private var exerciseListViewModel: ExerciseListViewModel
    @State private var restTimerService = RestTimerService()
    @State private var showingExercisePicker = false
    @State private var showingCancelConfirmation = false
    @State private var showingFinishError = false
    @State private var finishErrorMessage = ""
    @State private var showingNotes = false
    @State private var showingRestTimer = false
    @State private var notesText = ""

    init(viewModel: WorkoutViewModel, exerciseListViewModel: ExerciseListViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self._exerciseListViewModel = State(initialValue: exerciseListViewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = viewModel.currentWorkout, viewModel.isActive {
                    workoutContent(workout)
                } else {
                    startView
                }
            }
            .navigationTitle(viewModel.currentWorkout?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(STColors.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                    Task {
                        await viewModel.cancelWorkout()
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

    // MARK: - Start View

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Active Workout")
                .font(.title2)
            Button("Start Workout") {
                Task {
                    await viewModel.startWorkout(name: "Quick Workout", from: nil)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(STColors.background)
    }

    // MARK: - Workout Content

    private func workoutContent(_ workout: Workout) -> some View {
        ScrollViewReader { proxy in
            workoutScrollView(workout: workout, proxy: proxy)
        }
        .task {
            await viewModel.loadPreviousData()
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
        }
        .sheet(isPresented: $showingRestTimer) {
            RestTimerView(service: restTimerService)
        }
    }

    private func workoutScrollView(workout: Workout, proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: STSpacing.cardGap) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, workoutExercise in
                    exerciseCard(for: workoutExercise, isActive: index == 0)
                        .id(workoutExercise.id)
                }
                notesCard
                addExerciseButton
                cancelWorkoutButton
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .onChange(of: workout.exercises.count) { _, _ in
            if let lastExercise = workout.exercises.last {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(lastExercise.id, anchor: .top)
                }
            }
        }
        .background(STColors.background)
        .scrollDismissesKeyboard(.interactively)
    }

    private func exerciseCard(for workoutExercise: WorkoutExercise, isActive: Bool) -> some View {
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
            }
        )
    }

    private func handleSetToggle(workoutExercise: WorkoutExercise, setId: UUID) {
        Task {
            await viewModel.toggleSetCompletion(
                exerciseId: workoutExercise.id,
                setId: setId
            )
            if let ex = viewModel.currentWorkout?.exercises.first(where: { $0.id == workoutExercise.id }),
               let completedSet = ex.sets.first(where: { $0.id == setId }),
               completedSet.isCompleted {
                let restSeconds = workoutExercise.restTimerSeconds ?? 90
                let setIndex = ex.sets.firstIndex(where: { $0.id == setId }) ?? 0
                restTimerService.start(
                    seconds: restSeconds,
                    exerciseName: workoutExercise.exercise.name,
                    setNumber: setIndex + 1
                )
            }
        }
    }

    private var finishButton: some View {
        Button {
            Task {
                do {
                    try await viewModel.completeWorkout()
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
                    restTimerService.remainingSeconds += 15
                    restTimerService.totalSeconds += 15
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
                    restTimerService.remainingSeconds = 0
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
