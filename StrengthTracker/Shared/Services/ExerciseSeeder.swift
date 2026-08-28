#if canImport(SwiftData)
import Foundation

@MainActor
public final class ExerciseSeeder {
    private let exerciseRepository: any ExerciseRepository
    private var seedingTask: Task<Void, Never>?
    private var hasSeeded = false

    public init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    /// Start seeding in background. Call from app init.
    public func startSeeding() {
        guard seedingTask == nil else { return }
        seedingTask = Task { await seedIfNeeded() }
    }

    /// Wait until seeding is complete. Safe to call multiple times.
    public func ensureSeeded() async {
        await seedingTask?.value
    }

    public func seedIfNeeded() async {
        guard !hasSeeded else { return }
        do {
            let existing = try await exerciseRepository.fetchAll()
            let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for seed in ExerciseSeedData.allExercises {
                if let current = existingById[seed.id] {
                    // Update non-custom exercises if seed data changed
                    if !current.isCustom && seedDataChanged(current: current, seed: seed) {
                        _ = try await exerciseRepository.save(seed)
                    }
                } else {
                    _ = try await exerciseRepository.save(seed)
                }
            }
            hasSeeded = true
        } catch {
            print("Failed to seed exercises: \(error)")
        }
    }

    private func seedDataChanged(current: Exercise, seed: Exercise) -> Bool {
        current.name != seed.name ||
        current.primaryMuscleGroup != seed.primaryMuscleGroup ||
        current.secondaryMuscleGroups != seed.secondaryMuscleGroups ||
        current.category != seed.category ||
        current.exerciseType != seed.exerciseType ||
        current.instructions != seed.instructions ||
        current.bodyweightFactor != seed.bodyweightFactor ||
        // equipmentBrand deliberately not compared — gym-specific, never shipped in seeds
        current.loadingType != seed.loadingType
    }
}
#endif
