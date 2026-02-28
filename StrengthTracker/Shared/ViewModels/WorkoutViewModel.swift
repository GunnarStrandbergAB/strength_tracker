import Foundation
import Observation

public enum WorkoutError: Error, Sendable {
    case noActiveWorkout
    case exerciseNotFound
}

@MainActor
@Observable
public final class WorkoutViewModel {
    public var currentWorkout: Workout? = nil
    public var isActive = false
    public var plannedSessionId: UUID? = nil
    public var plannedPlanId: UUID? = nil
    public var errorMessage: String? = nil
    public var lastPR: PersonalRecord? = nil
    public var previousSetDataCache: [String: String] = [:]
    public var watchActiveWorkout: Workout? = nil

    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let personalRecordService: PersonalRecordService?
    private let healthKitService: any HealthKitServiceProtocol
    private let calorieEstimationService: CalorieEstimationService
    public let userPreferencesService: UserPreferencesService?
    private let analyticsService: WorkoutAnalyticsService?
    private let webhookService: WebhookService?

    public init(
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        personalRecordService: PersonalRecordService? = nil,
        healthKitService: any HealthKitServiceProtocol,
        calorieEstimationService: CalorieEstimationService = CalorieEstimationService(),
        userPreferencesService: UserPreferencesService? = nil,
        analyticsService: WorkoutAnalyticsService? = nil,
        webhookService: WebhookService? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.personalRecordService = personalRecordService
        self.healthKitService = healthKitService
        self.calorieEstimationService = calorieEstimationService
        self.userPreferencesService = userPreferencesService
        self.analyticsService = analyticsService
        self.webhookService = webhookService
    }

    public func startWorkout(name: String, from template: WorkoutTemplate? = nil) async {
        var exercises: [WorkoutExercise] = []

        if let template = template {
            exercises = template.exercises.sorted(by: { $0.order < $1.order }).enumerated().map { index, te in
                let sets = (0..<te.targetSets).map { setIndex in
                    let target = te.setTargets.indices.contains(setIndex) ? te.setTargets[setIndex] : nil
                    let resolvedSetType: SetType = {
                        if let t = target, t.setType != .normal { return t.setType }
                        return te.isWarmUp ? .warmup : .normal
                    }()
                    return ExerciseSet(
                        id: UUID(),
                        order: setIndex + 1,
                        setType: resolvedSetType,
                        weight: target?.targetWeight ?? te.targetWeight,
                        reps: target?.targetReps ?? te.targetReps,
                        durationSeconds: target?.targetDurationSeconds ?? te.targetDurationSeconds,
                        distanceMeters: target?.targetDistanceMeters ?? te.targetDistanceMeters,
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
        }

        var workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: template?.id,
            exercises: exercises
        )

        do {
            workout = try await workoutRepository.save(workout)
            currentWorkout = workout
            isActive = true

            // Update template usage stats
            if let template = template {
                try? await templateRepository.incrementUsage(template.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addExercise(_ exercise: Exercise) {
        guard var workout = currentWorkout else { return }
        let order = workout.exercises.count + 1
        let workoutExercise = WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: nil,
            sets: []
        )
        workout.exercises.append(workoutExercise)
        currentWorkout = workout

        Task {
            await loadPreviousDataForExercise(workoutExercise.id)
        }
    }

    public func logSet(exerciseId: UUID, weight: Double?, reps: Int?, setType: SetType = .normal) async throws {
        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.exercise.id == exerciseId }) else {
            throw WorkoutError.exerciseNotFound
        }

        let setOrder = workout.exercises[exerciseIndex].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: true,
            isPersonalRecord: false,
            completedAt: Date()
        )

        workout.exercises[exerciseIndex].sets.append(newSet)
        workout = try await workoutRepository.save(workout)
        currentWorkout = workout

        // Check for personal records
        if let prService = personalRecordService {
            let exercise = workout.exercises[exerciseIndex].exercise
            if let pr = try? await prService.checkForPR(exercise: exercise, set: newSet) {
                lastPR = pr
            }
        }
    }

    public func removeSet(exerciseId: UUID, setId: UUID) async {
        guard var workout = currentWorkout else { return }
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        workout.exercises[exerciseIndex].sets.removeAll { $0.id == setId }
        // Re-number set orders
        for i in workout.exercises[exerciseIndex].sets.indices {
            workout.exercises[exerciseIndex].sets[i].order = i + 1
        }
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    public func removeExercise(exerciseId: UUID) async {
        guard var workout = currentWorkout else { return }
        workout.exercises.removeAll { $0.id == exerciseId }
        // Re-number orders
        for i in workout.exercises.indices {
            workout.exercises[i].order = i + 1
        }
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    public func updateNotes(_ notes: String) async {
        guard var workout = currentWorkout else { return }
        workout.notes = notes.isEmpty ? nil : notes
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    public func completeWorkout() async throws {
        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        workout.completedAt = Date()
        let saved = try await workoutRepository.save(workout)
        currentWorkout = saved
        isActive = false

        // Save to HealthKit with calorie estimation (iPhone-only path)
        #if canImport(HealthKit)
        Task {
            let bodyWeightKg = await resolveBodyWeightKg()
            if let bw = bodyWeightKg {
                let result = calorieEstimationService.estimateCalories(workout: saved, bodyWeightKg: bw)
                try? await healthKitService.saveWorkout(saved, calories: result.totalCalories)
            } else {
                try? await healthKitService.saveWorkout(saved)
            }
        }
        #endif

        // Vectorize workout for analytics in background
        Task {
            let bodyWeightKg = await resolveBodyWeightKg() ?? UserPreferencesService.defaultBodyWeightKg
            try? await analyticsService?.vectorizeWorkout(saved, bodyWeightKg: bodyWeightKg)
        }

        // Send to webhook in background (fire-and-forget)
        Task {
            await webhookService?.send(saved)
        }
    }

    /// Resolve body weight via fallback chain: HealthKit → UserPreferences → nil
    private func resolveBodyWeightKg() async -> Double? {
        // Try HealthKit first
        if let hkWeight = await healthKitService.fetchBodyWeightKg() {
            return hkWeight
        }
        // Fallback to user preference
        return userPreferencesService?.bodyWeightKg
    }

    /// Fetch previous set data for an exercise to help with progressive overload
    public func previousSetData(for exerciseId: UUID, setIndex: Int) async -> String? {
        // Get the exercise ID from the current workout's exercise
        guard let currentWorkout = currentWorkout,
              let workoutExercise = currentWorkout.exercises.first(where: { $0.id == exerciseId }) else {
            return nil
        }

        let targetExerciseId = workoutExercise.exercise.id

        // Fetch recent completed workouts
        #if canImport(SwiftData)
        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            // Find last completed workout with this exercise (not the current one)
            let previousWorkout = allWorkouts
                .filter { $0.completedAt != nil && $0.id != currentWorkout.id }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                .first { workout in
                    workout.exercises.contains { $0.exercise.id == targetExerciseId }
                }

            guard let prev = previousWorkout,
                  let prevExercise = prev.exercises.first(where: { $0.exercise.id == targetExerciseId }),
                  setIndex < prevExercise.sets.count else {
                return nil
            }

            let prevSet = prevExercise.sets[setIndex]
            let weight = prevSet.weight.map { String(format: "%g", $0) } ?? "0"
            let reps = prevSet.reps.map { String($0) } ?? "0"
            return "\(weight)kg × \(reps)"
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Load previous data for all exercises when workout starts
    public func loadPreviousData() async {
        guard let workout = currentWorkout else { return }
        for exercise in workout.exercises {
            await loadPreviousDataForExercise(exercise.id)
        }
    }

    /// Load previous data for a single exercise (fills any missing cache keys)
    public func loadPreviousDataForExercise(_ exerciseId: UUID) async {
        guard let workout = currentWorkout,
              let exercise = workout.exercises.first(where: { $0.id == exerciseId }) else { return }
        for (index, _) in exercise.sets.enumerated() {
            let key = "\(exercise.id)-\(index)"
            if previousSetDataCache[key] == nil {
                if let data = await previousSetData(for: exercise.id, setIndex: index) {
                    previousSetDataCache[key] = data
                }
            }
        }
    }

    // MARK: - Inline Editing Methods

    /// Add an empty (incomplete) set to an exercise for the inline editing workflow.
    public func addEmptySet(exerciseId: UUID) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else {
            return
        }

        let setOrder = workout.exercises[exerciseIndex].sets.count + 1
        let newSet = ExerciseSet(
            id: UUID(),
            order: setOrder,
            setType: .normal,
            weight: nil,
            reps: nil,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: nil,
            isCompleted: false,
            isPersonalRecord: false,
            completedAt: nil
        )

        workout.exercises[exerciseIndex].sets.append(newSet)
        do {
            currentWorkout = try await workoutRepository.save(workout)
            await loadPreviousDataForExercise(exerciseId)
        } catch {
            currentWorkout = workout
        }
    }

    /// Update the weight of a specific set within an exercise.
    public func updateSetWeight(exerciseId: UUID, setId: UUID, weight: Double?) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        workout.exercises[exerciseIndex].sets[setIndex].weight = weight
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    /// Update the reps of a specific set within an exercise.
    public func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        workout.exercises[exerciseIndex].sets[setIndex].reps = reps
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    /// Update the type of a specific set (normal, warmup, dropset, etc.).
    public func updateSetType(exerciseId: UUID, setId: UUID, setType: SetType) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        workout.exercises[exerciseIndex].sets[setIndex].setType = setType
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    /// Toggle the completion status of a specific set.
    public func toggleSetCompletion(exerciseId: UUID, setId: UUID) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        let wasCompleted = workout.exercises[exerciseIndex].sets[setIndex].isCompleted
        workout.exercises[exerciseIndex].sets[setIndex].isCompleted = !wasCompleted
        workout.exercises[exerciseIndex].sets[setIndex].completedAt = wasCompleted ? nil : Date()
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    public func updateExerciseNotes(exerciseId: UUID, notes: String) async {
        guard var workout = currentWorkout,
              let idx = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        workout.exercises[idx].notes = notes.isEmpty ? nil : notes
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    /// Cancel the current workout without saving completion.
    public func cancelWorkout() async {
        if let workout = currentWorkout {
            try? await workoutRepository.delete(workout)
        }
        currentWorkout = nil
        isActive = false
    }
}
