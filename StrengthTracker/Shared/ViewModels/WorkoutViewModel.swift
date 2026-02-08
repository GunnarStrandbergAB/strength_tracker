import Foundation
import Observation

enum WorkoutError: Error, Sendable {
    case noActiveWorkout
    case exerciseNotFound
}

@MainActor
@Observable
final class WorkoutViewModel {
    var currentWorkout: Workout? = nil
    var isActive = false
    var errorMessage: String? = nil
    var lastPR: PersonalRecord? = nil
    var previousSetDataCache: [String: String] = [:]

    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let personalRecordService: PersonalRecordService?
    private let healthKitService: any HealthKitServiceProtocol

    init(
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        personalRecordService: PersonalRecordService? = nil,
        healthKitService: any HealthKitServiceProtocol
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.personalRecordService = personalRecordService
        self.healthKitService = healthKitService
    }

    func startWorkout(name: String, from template: WorkoutTemplate? = nil) async {
        var exercises: [WorkoutExercise] = []

        if let template = template {
            exercises = template.exercises.enumerated().map { index, te in
                WorkoutExercise(
                    id: UUID(),
                    exercise: te.exercise,
                    order: index + 1,
                    supersetGroup: te.supersetGroup,
                    notes: te.notes,
                    restTimerSeconds: te.restTimerSeconds,
                    sets: []
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

    func addExercise(_ exercise: Exercise) {
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
    }

    func logSet(exerciseId: UUID, weight: Double?, reps: Int?, setType: SetType = .normal) async throws {
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

    func removeSet(exerciseId: UUID, setId: UUID) async {
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

    func removeExercise(exerciseId: UUID) async {
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

    func updateNotes(_ notes: String) async {
        guard var workout = currentWorkout else { return }
        workout.notes = notes.isEmpty ? nil : notes
        do {
            currentWorkout = try await workoutRepository.save(workout)
        } catch {
            currentWorkout = workout
        }
    }

    func completeWorkout() async throws {
        guard var workout = currentWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        workout.completedAt = Date()
        let saved = try await workoutRepository.save(workout)
        currentWorkout = saved
        isActive = false

        // Save to HealthKit after persisting to SwiftData
        #if canImport(HealthKit)
        Task {
            try? await healthKitService.saveWorkout(saved)
        }
        #endif
    }

    /// Fetch previous set data for an exercise to help with progressive overload
    func previousSetData(for exerciseId: UUID, setIndex: Int) async -> String? {
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
    func loadPreviousData() async {
        guard let workout = currentWorkout else { return }
        for exercise in workout.exercises {
            for (index, _) in exercise.sets.enumerated() {
                let key = "\(exercise.id)-\(index)"
                if let data = await previousSetData(for: exercise.id, setIndex: index) {
                    previousSetDataCache[key] = data
                }
            }
        }
    }

    // MARK: - Inline Editing Methods

    /// Add an empty (incomplete) set to an exercise for the inline editing workflow.
    func addEmptySet(exerciseId: UUID) async {
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
        currentWorkout = workout
    }

    /// Update the weight of a specific set within an exercise.
    func updateSetWeight(exerciseId: UUID, setId: UUID, weight: Double?) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        workout.exercises[exerciseIndex].sets[setIndex].weight = weight
        currentWorkout = workout
    }

    /// Update the reps of a specific set within an exercise.
    func updateSetReps(exerciseId: UUID, setId: UUID, reps: Int?) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        workout.exercises[exerciseIndex].sets[setIndex].reps = reps
        currentWorkout = workout
    }

    /// Toggle the completion status of a specific set.
    func toggleSetCompletion(exerciseId: UUID, setId: UUID) async {
        guard var workout = currentWorkout else { return }

        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        let wasCompleted = workout.exercises[exerciseIndex].sets[setIndex].isCompleted
        workout.exercises[exerciseIndex].sets[setIndex].isCompleted = !wasCompleted
        workout.exercises[exerciseIndex].sets[setIndex].completedAt = wasCompleted ? nil : Date()
        currentWorkout = workout
    }

    /// Cancel the current workout without saving completion.
    func cancelWorkout() async {
        currentWorkout = nil
        isActive = false
    }
}
