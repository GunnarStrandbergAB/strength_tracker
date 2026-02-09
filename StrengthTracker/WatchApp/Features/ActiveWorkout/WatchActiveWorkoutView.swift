import SwiftUI
import StrengthTrackerShared

struct WatchActiveWorkoutView: View {
    @State private var viewModel: WatchWorkoutViewModel
    @State private var selectedTab: Int = 0

    init(viewModel: WatchWorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)
    private let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        if let workout = viewModel.activeWorkout {
            TabView(selection: $selectedTab) {
                if !workout.exercises.isEmpty {
                    exerciseView(workout)
                        .tag(0)
                }

                // Rest timer tab (shown when resting)
                if viewModel.isResting {
                    WatchRestTimerView(viewModel: viewModel)
                        .tag(1)
                }

                summaryTab(workout)
                    .tag(viewModel.isResting ? 2 : 1)
            }
            .tabViewStyle(.verticalPage)
            .navigationBarBackButtonHidden()
            .onChange(of: viewModel.isResting) { _, isResting in
                if isResting {
                    // Auto-navigate to rest timer when it starts
                    withAnimation {
                        selectedTab = 1
                    }
                } else {
                    // Return to exercise view when rest ends
                    withAnimation {
                        selectedTab = 0
                    }
                }
            }
        }
    }

    private func exerciseView(_ workout: Workout) -> some View {
        VStack(spacing: 2) {
            #if canImport(HealthKit) && os(watchOS)
            // Compact metrics bar
            WatchMetricsView(
                heartRate: viewModel.heartRate,
                activeCalories: viewModel.activeCalories,
                elapsedTime: viewModel.healthKitElapsedTime
            )
            #endif

            if viewModel.currentExerciseIndex < workout.exercises.count {
                let current = workout.exercises[viewModel.currentExerciseIndex]

                // Exercise name + set info on one line
                Text(current.exercise.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primaryYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if viewModel.hasPlannedSets {
                    Text("Set \(viewModel.currentSetNumber)/\(viewModel.plannedSets)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondaryText)
                } else {
                    Text("Set \(viewModel.currentSetNumber)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondaryText)
                }

                // Set input area
                WatchSetInputView(
                    viewModel: viewModel,
                    targetWeight: viewModel.currentTargetWeight,
                    targetReps: viewModel.currentTargetReps
                )

                // Exercise navigation
                HStack(spacing: 16) {
                    Button {
                        viewModel.previousExercise()
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                viewModel.currentExerciseIndex == 0
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.7)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.currentExerciseIndex == 0)

                    Text("\(viewModel.currentExerciseIndex + 1)/\(workout.exercises.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryText)

                    Button {
                        viewModel.nextExercise()
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                viewModel.currentExerciseIndex >= workout.exercises.count - 1
                                    ? Color.white.opacity(0.2)
                                    : Color.white.opacity(0.7)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.currentExerciseIndex >= workout.exercises.count - 1)
                }

                // Logged sets list with swipe-to-delete and RPE display
                if !current.sets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(current.sets.enumerated()), id: \.element.id) { index, set in
                                setChip(set: set, index: index)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func setChip(set: ExerciseSet, index: Int) -> some View {
        VStack(spacing: 1) {
            Text("S\(set.order)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
            Text("\(Int(set.weight ?? 0))x\(set.reps ?? 0)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
            // Show RPE if available (Task 5.3)
            if let rpe = set.rpe {
                Text("@\(String(format: "%.0f", rpe))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(primaryYellow)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
        .onLongPressGesture {
            // Swipe-to-delete alternative for Watch: long-press to delete
            viewModel.removeSetFromCurrentExercise(at: index)
        }
    }

    private func summaryTab(_ workout: Workout) -> some View {
        WorkoutSummaryView(
            workout: workout,
            viewModel: viewModel
        )
    }
}
