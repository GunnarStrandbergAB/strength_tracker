import Foundation
import Observation

@MainActor
@Observable
final class ExerciseListViewModel {
    var exercises: [Exercise] = []
    var searchText: String = ""
    var selectedCategory: ExerciseCategory? = nil
    var selectedMuscleGroup: MuscleGroup? = nil
    var isLoading = false
    var errorMessage: String? = nil

    var filteredExercises: [Exercise] {
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

    init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    func loadExercises() async {
        isLoading = true
        errorMessage = nil
        do {
            exercises = try await exerciseRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
