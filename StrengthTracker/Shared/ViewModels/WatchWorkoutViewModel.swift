import Foundation
import Observation

@MainActor
@Observable
public final class WatchWorkoutViewModel {
    public var activeWorkout: Workout? = nil
    public var currentExerciseIndex: Int = 0
    public var isActive = false

    // Rest timer state
    public var isResting = false
    public var restTimeRemaining: TimeInterval = 0
    public var restDuration: TimeInterval = 90

    // Notes
    public var workoutNotes: String = ""

    private let workoutRepository: any WorkoutRepository
    private let healthKitService: any HealthKitServiceProtocol
    private let connectivityManager: ConnectivityManager
    private var restTimer: Timer?

    public init(
        workoutRepository: any WorkoutRepository,
        healthKitService: any HealthKitServiceProtocol,
        connectivityManager: ConnectivityManager
    ) {
        self.workoutRepository = workoutRepository
        self.healthKitService = healthKitService
        self.connectivityManager = connectivityManager
    }

    // MARK: - Computed Properties

    public var currentExercise: WorkoutExercise? {
        guard let workout = activeWorkout,
              currentExerciseIndex < workout.exercises.count else {
            return nil
        }
        return workout.exercises[currentExerciseIndex]
    }

    public var currentSetNumber: Int {
        guard let exercise = currentExercise else { return 1 }
        return exercise.sets.count + 1
    }

    public var plannedSets: Int {
        4 // Default planned sets per exercise
    }

    public var currentExerciseVolume: Double {
        currentExercise?.exerciseVolume ?? 0
    }

    public var totalSetsCompleted: Int {
        guard let workout = activeWorkout else { return 0 }
        return workout.exercises.reduce(0) { $0 + $1.sets.count }
    }

    public var elapsedTime: TimeInterval {
        guard let workout = activeWorkout else { return 0 }
        return Date().timeIntervalSince(workout.startedAt)
    }

    public var restTimerText: String {
        let minutes = Int(restTimeRemaining) / 60
        let seconds = Int(restTimeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var restProgress: Double {
        guard restDuration > 0 else { return 0 }
        return 1.0 - (restTimeRemaining / restDuration)
    }

    // MARK: - Workout Lifecycle

    public func startWorkout(name: String, exercises: [Exercise]) async {
        let workoutExercises = exercises.enumerated().map { index, exercise in
            WorkoutExercise(
                id: UUID(),
                exercise: exercise,
                order: index + 1,
                supersetGroup: nil,
                notes: nil,
                restTimerSeconds: nil,
                sets: []
            )
        }

        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            healthKitWorkoutId: nil,
            exercises: workoutExercises
        )

        do {
            activeWorkout = try await workoutRepository.save(workout)
            currentExerciseIndex = 0
            isActive = true

            // Start HealthKit workout session
            #if canImport(HealthKit)
            try? await healthKitService.startWorkoutSession()
            #endif
        } catch {
            activeWorkout = workout
            currentExerciseIndex = 0
            isActive = true
        }
    }

    public func logSet(weight: Double?, reps: Int?, rpe: Double? = nil) async throws {
        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard currentExerciseIndex < workout.exercises.count else {
            throw WorkoutError.exerciseNotFound
        }

        let setOrder = workout.exercises[currentExerciseIndex].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
            setType: .normal,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: rpe,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )

        workout.exercises[currentExerciseIndex].sets.append(newSet)
        activeWorkout = workout

        // Auto-start rest timer after logging a set
        startRestTimer()
    }

    public func removeSet(at exerciseIndex: Int, setIndex: Int) {
        guard var workout = activeWorkout,
              exerciseIndex < workout.exercises.count,
              setIndex < workout.exercises[exerciseIndex].sets.count else {
            return
        }

        workout.exercises[exerciseIndex].sets.remove(at: setIndex)

        // Re-order remaining sets
        for i in 0..<workout.exercises[exerciseIndex].sets.count {
            workout.exercises[exerciseIndex].sets[i].order = i + 1
        }

        activeWorkout = workout
    }

    public func removeSetFromCurrentExercise(at setIndex: Int) {
        removeSet(at: currentExerciseIndex, setIndex: setIndex)
    }

    public func completeWorkout() async throws {
        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        workout.completedAt = Date()
        if !workoutNotes.isEmpty {
            workout.notes = workoutNotes
        }
        let saved = try await workoutRepository.save(workout)
        activeWorkout = saved
        stopRestTimer()
        isActive = false

        // End HealthKit workout session and save
        #if canImport(HealthKit)
        try? await healthKitService.endWorkoutSession(saved)
        #endif

        // Send completion notification to iPhone via WatchConnectivity
        connectivityManager.sendWorkoutCompleted(saved)
    }

    // MARK: - Navigation

    public func nextExercise() {
        guard let workout = activeWorkout else { return }
        if currentExerciseIndex < workout.exercises.count - 1 {
            currentExerciseIndex += 1
        }
    }

    public func previousExercise() {
        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
        }
    }

    // MARK: - Rest Timer

    public func startRestTimer() {
        stopRestTimer()
        isResting = true
        restTimeRemaining = restDuration

        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.restTimeRemaining > 0 {
                    self.restTimeRemaining -= 1
                } else {
                    self.stopRestTimer()
                }
            }
        }
    }

    public func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isResting = false
        restTimeRemaining = 0
    }

    public func skipRestTimer() {
        stopRestTimer()
    }
}
