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
            let existingIds = Set(existing.map(\.id))
            let missing = ExerciseSeedData.allExercises.filter { !existingIds.contains($0.id) }
            guard !missing.isEmpty else { return }

            for exercise in missing {
                _ = try await exerciseRepository.save(exercise)
            }
        } catch {
            print("Failed to seed exercises: \(error)")
        }
    }
}
#endif
