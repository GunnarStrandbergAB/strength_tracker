#if canImport(SwiftData)
import Foundation

@MainActor
final class ExerciseSeeder {
    private let exerciseRepository: any ExerciseRepository

    init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    func seedIfNeeded() async {
        do {
            let existing = try await exerciseRepository.fetchAll()
            guard existing.isEmpty else { return }

            for exercise in ExerciseSeedData.allExercises {
                _ = try await exerciseRepository.save(exercise)
            }
        } catch {
            print("Failed to seed exercises: \(error)")
        }
    }
}
#endif
