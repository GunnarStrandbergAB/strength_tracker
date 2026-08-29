import Foundation

/// One-time migration for the effective-load model: historical workout and
/// template exercise snapshots predate `bodyweightFactor`, so their nil factor
/// would silently fall back to 1.0 even when the library ships a researched
/// value. Backfills factors from the live library by exercise ID, then
/// recalculates all PRs once — extra-kg-era records would otherwise trigger
/// false PR celebrations on every bodyweight set under effective load.
@MainActor
public final class EffectiveLoadMigrationService {
    /// Bump when the effective-load model changes in a way that requires re-running.
    public static let targetVersion = 1

    private let workoutRepository: any WorkoutRepository
    private let templateRepository: any TemplateRepository
    private let exerciseRepository: any ExerciseRepository
    private let personalRecordService: PersonalRecordService?
    private let userPreferencesService: UserPreferencesService

    public init(
        workoutRepository: any WorkoutRepository,
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        personalRecordService: PersonalRecordService?,
        userPreferencesService: UserPreferencesService
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.personalRecordService = personalRecordService
        self.userPreferencesService = userPreferencesService
    }

    /// Runs the migration if it hasn't run yet. Call after exercise seeding so
    /// the library already carries the researched factors.
    public func migrateIfNeeded() async {
        guard userPreferencesService.effectiveLoadModelVersion < Self.targetVersion else { return }

        do {
            let library = try await exerciseRepository.fetchAll()
            let factorById = Dictionary(library.compactMap { exercise in
                exercise.bodyweightFactor.map { (exercise.id, $0) }
            }, uniquingKeysWith: { first, _ in first })

            try await backfillWorkouts(factorById: factorById)
            try await backfillTemplates(factorById: factorById)
            try? await personalRecordService?.recalculateAllPRs()

            userPreferencesService.effectiveLoadModelVersion = Self.targetVersion
        } catch {
            // Leave the version untouched so the migration retries next launch.
            print("EffectiveLoadMigration failed: \(error)")
        }
    }

    private func backfillWorkouts(factorById: [UUID: Double]) async throws {
        let workouts = try await workoutRepository.fetchAll()
        for var workout in workouts {
            var changed = false
            for i in workout.exercises.indices {
                let snapshot = workout.exercises[i].exercise
                guard snapshot.exerciseType == .bodyweightReps,
                      snapshot.bodyweightFactor == nil,
                      let factor = factorById[snapshot.id] else { continue }
                workout.exercises[i].exercise.bodyweightFactor = factor
                changed = true
            }
            if changed {
                _ = try await workoutRepository.save(workout)
            }
        }
    }

    private func backfillTemplates(factorById: [UUID: Double]) async throws {
        let templates = try await templateRepository.fetchAll()
        for var template in templates {
            var changed = false
            for i in template.exercises.indices {
                let snapshot = template.exercises[i].exercise
                guard snapshot.exerciseType == .bodyweightReps,
                      snapshot.bodyweightFactor == nil,
                      let factor = factorById[snapshot.id] else { continue }
                template.exercises[i].exercise.bodyweightFactor = factor
                changed = true
            }
            if changed {
                _ = try await templateRepository.save(template)
            }
        }
    }
}
