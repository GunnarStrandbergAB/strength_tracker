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

    /// Effective-load volume of every completed working set of the exercise, all time
    /// (same definition as Workout.totalVolume). Computed in loadProgression.
    public private(set) var totalVolume: Double = 0

    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    public let userPreferencesService: UserPreferencesService?
    private let bodyWeightProvider: BodyWeightProvider?

    public var weightUnit: WeightUnit { userPreferencesService?.weightUnit ?? .kg }

    public init(
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        userPreferencesService: UserPreferencesService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil
    ) {
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
        self.bodyWeightProvider = bodyWeightProvider
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
            var volume: Double = 0

            let bodyWeightKg = bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
            for workout in completed {
                for workoutExercise in workout.exercises {
                    if workoutExercise.exercise.id == exerciseId {
                        let baseLoad = workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                        // Working sets only: warm-ups are not performance data.
                        for set in workoutExercise.sets where set.isCompleted && set.setType != .warmup {
                            volume += set.setVolume(baseLoadPerRep: baseLoad)
                            // One point per performed segment so drop-set parts feed
                            // best-weight/best-reps/e1RM like any other effort.
                            for part in set.effectiveLoadParts(baseLoadPerRep: baseLoad) {
                                results.append((date: workout.trainingDate, weight: part.load, reps: part.reps))
                            }
                        }
                    }
                }
            }

            progressionData = results.sorted { $0.date < $1.date }
            totalVolume = volume
        } catch {
            progressionData = []
        }
        isLoading = false
    }

}
