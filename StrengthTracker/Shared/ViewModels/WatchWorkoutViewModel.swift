import Foundation
import Observation

@MainActor
@Observable
public final class WatchWorkoutViewModel {
    public var activeWorkout: Workout? = nil
    public var currentExerciseIndex: Int = 0
    public var isActive = false

    // Template target data per exercise index
    public var plannedSetsPerExercise: [Int: Int] = [:]
    public var targetWeightPerExercise: [Int: Double?] = [:]
    public var targetRepsPerExercise: [Int: Int?] = [:]

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
    private var restStartDate: Date?

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
        let completedCount = exercise.sets.filter(\.isCompleted).count
        return completedCount + 1
    }

    public var plannedSets: Int {
        plannedSetsPerExercise[currentExerciseIndex] ?? 4
    }

    public var currentTargetWeight: Double? {
        targetWeightPerExercise[currentExerciseIndex] ?? nil
    }

    public var currentTargetReps: Int? {
        targetRepsPerExercise[currentExerciseIndex] ?? nil
    }

    public var currentExerciseVolume: Double {
        currentExercise?.exerciseVolume ?? 0
    }

    public var totalSetsCompleted: Int {
        guard let workout = activeWorkout else { return 0 }
        return workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
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

    public func startWorkout(name: String, from template: WorkoutTemplate) async {
        let workoutExercises = template.exercises.sorted { $0.order < $1.order }.enumerated().map { index, te in
            let sets = (0..<te.targetSets).map { setIndex in
                ExerciseSet(
                    id: UUID(),
                    order: setIndex + 1,
                    setType: .normal,
                    weight: te.targetWeight,
                    reps: te.targetReps,
                    durationSeconds: te.targetDurationSeconds,
                    distanceMeters: te.targetDistanceMeters,
                    rpe: nil,
                    isCompleted: false,
                    isPersonalRecord: false,
                    completedAt: nil
                )
            }
            return WorkoutExercise(
                id: UUID(),
                exercise: te.exercise,
                order: index + 1,
                supersetGroup: te.supersetGroup,
                notes: te.notes,
                restTimerSeconds: te.restTimerSeconds,
                sets: sets
            )
        }

        // Store per-exercise targets
        for (index, te) in template.exercises.sorted(by: { $0.order < $1.order }).enumerated() {
            plannedSetsPerExercise[index] = te.targetSets
            targetWeightPerExercise[index] = te.targetWeight
            targetRepsPerExercise[index] = te.targetReps
        }

        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: template.id,
            exercises: workoutExercises
        )

        do {
            activeWorkout = try await workoutRepository.save(workout)
            currentExerciseIndex = 0
            isActive = true

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

        // If there's an incomplete pre-populated set, update it instead of appending
        if let incompleteIndex = workout.exercises[currentExerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) {
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].weight = weight
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].reps = reps
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].rpe = rpe
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].isCompleted = true
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].completedAt = Date()
        } else {
            // All pre-populated sets done (or none existed), append a new one
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
        }

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
        restStartDate = Date()

        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.restStartDate else { return }
                let elapsed = Date().timeIntervalSince(start)
                let remaining = self.restDuration - elapsed
                if remaining > 0 {
                    self.restTimeRemaining = remaining
                } else {
                    self.restTimeRemaining = 0
                    self.stopRestTimer()
                }
            }
        }
    }

    public func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        restStartDate = nil
        isResting = false
        restTimeRemaining = 0
    }

    public func skipRestTimer() {
        stopRestTimer()
    }
}
