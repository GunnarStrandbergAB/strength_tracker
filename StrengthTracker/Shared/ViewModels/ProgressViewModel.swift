import Foundation
import Observation

@MainActor
@Observable
public final class ProgressViewModel {
    public var selectedExercise: Exercise? = nil
    public var exercises: [Exercise] = []
    public var progressionData: [(date: Date, weight: Double, reps: Int)] = []
    public var isLoading = false

    public var bestWeight: Double? {
        progressionData.map(\.weight).max()
    }

    public var bestReps: Int? {
        progressionData.map(\.reps).max()
    }

    public var estimated1RM: Double? {
        progressionData
            .map { AnalyticsCalculations.calculateOneRM(weight: $0.weight, reps: min($0.reps, 15)) }
            .max()
    }

    public var totalVolume: Double {
        progressionData.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    public let userPreferencesService: UserPreferencesService?

    public var weightUnit: WeightUnit { userPreferencesService?.weightUnit ?? .kg }

    public init(
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        userPreferencesService: UserPreferencesService? = nil
    ) {
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
    }

    public func loadExercises() async {
        isLoading = true
        do {
            exercises = try await exerciseRepository.fetchAll()
        } catch {
            exercises = []
        }
        isLoading = false
    }

    public func loadProgression(for exerciseId: UUID) async {
        isLoading = true
        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            let completed = allWorkouts.filter { $0.completedAt != nil }
            var results: [(date: Date, weight: Double, reps: Int)] = []

            let bodyWeightKg = userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
            for workout in completed {
                for workoutExercise in workout.exercises {
                    if workoutExercise.exercise.id == exerciseId {
                        let baseLoad = workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                        for set in workoutExercise.sets where set.isCompleted {
                            // One point per performed segment so drop-set parts feed
                            // best-weight/best-reps/e1RM/volume like any other effort.
                            for part in set.effectiveLoadParts(baseLoadPerRep: baseLoad) {
                                results.append((date: workout.startedAt, weight: part.load, reps: part.reps))
                            }
                        }
                    }
                }
            }

            progressionData = results.sorted { $0.date < $1.date }
        } catch {
            progressionData = []
        }
        isLoading = false
    }

}
