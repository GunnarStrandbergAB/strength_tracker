import Foundation
import Observation

@MainActor
@Observable
public final class ExerciseListViewModel {
    public var exercises: [Exercise] = []
    public var searchText: String = ""
    public var selectedCategory: ExerciseCategory? = nil
    public var selectedMuscleGroup: MuscleGroup? = nil
    public var isLoading = false
    public var errorMessage: String? = nil

    public var filteredExercises: [Exercise] {
        var result = exercises

        if !searchText.isEmpty {
            let lowered = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(lowered) }
        }

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if let muscleGroup = selectedMuscleGroup {
            result = result.filter { $0.primaryMuscleGroup == muscleGroup }
        }

        return result
    }

    private let exerciseRepository: any ExerciseRepository
    #if canImport(SwiftData)
    private let exerciseSeeder: ExerciseSeeder?
    #endif

    #if canImport(SwiftData)
    public init(exerciseRepository: any ExerciseRepository, exerciseSeeder: ExerciseSeeder? = nil) {
        self.exerciseRepository = exerciseRepository
        self.exerciseSeeder = exerciseSeeder
    }
    #else
    public init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }
    #endif

    public func loadExercises() async {
        isLoading = true
        errorMessage = nil
        do {
            #if canImport(SwiftData)
            await exerciseSeeder?.ensureSeeded()
            #endif
            exercises = try await exerciseRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
