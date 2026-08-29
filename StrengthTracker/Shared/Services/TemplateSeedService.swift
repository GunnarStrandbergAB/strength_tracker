#if canImport(SwiftData)
import Foundation

@MainActor
public final class TemplateSeedService {
    private let templateRepository: any TemplateRepository
    private let exerciseSeeder: ExerciseSeeder
    private var seedingTask: Task<Void, Never>?
    private var hasSeeded = false

    public init(templateRepository: any TemplateRepository, exerciseSeeder: ExerciseSeeder) {
        self.templateRepository = templateRepository
        self.exerciseSeeder = exerciseSeeder
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

        // Exercises must be seeded first (templates reference exercise seed data)
        await exerciseSeeder.ensureSeeded()

        do {
            let existing = try await templateRepository.fetchAll()
            let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            for seed in TemplateSeedData.allTemplates {
                if let current = existingById[seed.id] {
                    // Only update non-custom (library) templates if seed data changed
                    if !current.isCustom && seedDataChanged(current: current, seed: seed) {
                        _ = try await templateRepository.save(seed)
                    }
                } else {
                    _ = try await templateRepository.save(seed)
                }
            }
            hasSeeded = true
        } catch {
            print("Failed to seed templates: \(error)")
        }
    }

    private func seedDataChanged(current: WorkoutTemplate, seed: WorkoutTemplate) -> Bool {
        current.name != seed.name ||
        current.notes != seed.notes ||
        current.exercises.count != seed.exercises.count ||
        zip(current.exercises.sorted(by: { $0.order < $1.order }),
            seed.exercises.sorted(by: { $0.order < $1.order }))
            .contains { c, s in
                c.exercise.name != s.exercise.name ||
                c.targetSets != s.targetSets ||
                c.targetReps != s.targetReps ||
                c.restTimerSeconds != s.restTimerSeconds
            }
    }
}
#endif
