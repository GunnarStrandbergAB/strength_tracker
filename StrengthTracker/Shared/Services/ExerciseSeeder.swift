#if canImport(SwiftData)
import Foundation

@MainActor
public final class ExerciseSeeder {
    private let exerciseRepository: any ExerciseRepository

    public init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    public func seedIfNeeded() async {
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
