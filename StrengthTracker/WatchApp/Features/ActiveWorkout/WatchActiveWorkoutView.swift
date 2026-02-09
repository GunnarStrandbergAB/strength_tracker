import SwiftUI
import StrengthTrackerShared

struct WatchActiveWorkoutView: View {
    @State private var viewModel: WatchWorkoutViewModel
    @State private var selectedTab: Int = 0
    #if canImport(HealthKit) && os(watchOS)
    @State private var healthKitManager = WatchHealthKitManager()
    #endif

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
            #if canImport(HealthKit) && os(watchOS)
            .task {
                // Request authorization and start HealthKit session when workout view appears
                do {
                    try await healthKitManager.requestAuthorization()
                    try await healthKitManager.startWorkoutSession()
                } catch {
                    // Handle authorization or session start errors silently
                    // User can still track workout without HealthKit
                }
            }
            .onChange(of: viewModel.isActive) { _, isActive in
                // End HealthKit session when workout is completed
                if !isActive && healthKitManager.isSessionActive {
                    Task {
                        try? await healthKitManager.endWorkoutSession()
                    }
                }
            }
            #endif
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
        VStack(spacing: 4) {
            #if canImport(HealthKit) && os(watchOS)
            // Real-time workout metrics
            WatchMetricsView(
                heartRate: healthKitManager.heartRate,
                activeCalories: healthKitManager.activeCalories,
                elapsedTime: healthKitManager.elapsedTime
            )
            .padding(.bottom, 2)
            #endif

            if viewModel.currentExerciseIndex < workout.exercises.count {
                let current = workout.exercises[viewModel.currentExerciseIndex]

                // Exercise name - prominent, yellow
                Text(current.exercise.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(primaryYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Set count and exercise volume
                HStack(spacing: 8) {
                    if viewModel.hasPlannedSets {
                        Text("Set \(viewModel.currentSetNumber) of \(viewModel.plannedSets)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryText)
                    } else {
                        Text("Set \(viewModel.currentSetNumber)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }

                    if current.exerciseVolume > 0 {
                        Text(String(format: "%.0f kg", current.exerciseVolume))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
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
