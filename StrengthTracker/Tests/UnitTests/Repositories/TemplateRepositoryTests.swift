import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("TemplateRepository")
@MainActor
struct TemplateRepositoryTests {

    private func makeRepository() -> InMemoryTemplateRepository {
        InMemoryTemplateRepository()
    }

    private func makeExercise(name: String = "Bench Press") -> Exercise {
        Exercise(
            id: UUID(),
            name: name,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeTemplateExercise(
        exercise: Exercise? = nil,
        targetSets: Int = 3,
        targetReps: Int = 10
    ) -> TemplateExercise {
        TemplateExercise(
            id: UUID(),
            exercise: exercise ?? makeExercise(),
            order: 1,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: 90,
            targetSets: targetSets,
            targetReps: targetReps,
            targetWeight: nil,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )
    }

    private func makeTemplate(
        name: String = "Push Day",
        sortOrder: Int = 0,
        timesUsed: Int = 0,
        exercises: [TemplateExercise]? = nil
    ) -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID(),
            name: name,
            notes: nil,
            sortOrder: sortOrder,
            lastUsedAt: nil,
            timesUsed: timesUsed,
            exercises: exercises ?? [makeTemplateExercise()]
        )
    }

    // MARK: - fetchAll

    @Test("fetchAll returns empty when no templates")
    func fetchAllEmpty() async throws {
        let repo = makeRepository()
        let result = try await repo.fetchAll()
        #expect(result.isEmpty)
    }

    @Test("fetchAll returns templates sorted by sortOrder")
    func fetchAllSorted() async throws {
        let repo = makeRepository()
        let t1 = makeTemplate(name: "Push", sortOrder: 2)
        let t2 = makeTemplate(name: "Pull", sortOrder: 0)
        let t3 = makeTemplate(name: "Legs", sortOrder: 1)

        _ = try await repo.save(t1)
        _ = try await repo.save(t2)
        _ = try await repo.save(t3)

        let result = try await repo.fetchAll()
        #expect(result.count == 3)
        #expect(result[0].name == "Pull")
        #expect(result[1].name == "Legs")
        #expect(result[2].name == "Push")
    }

    // MARK: - save

    @Test("save persists template with exercises")
    func savePersists() async throws {
        let repo = makeRepository()
        let exercise = makeExercise()
        let templateExercise = makeTemplateExercise(exercise: exercise, targetSets: 4, targetReps: 8)
        let template = makeTemplate(exercises: [templateExercise])

        let saved = try await repo.save(template)
        #expect(saved.exercises.count == 1)
        #expect(saved.exercises[0].targetSets == 4)
        #expect(saved.exercises[0].targetReps == 8)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].id == template.id)
    }

    @Test("save overwrites existing template")
    func saveOverwrites() async throws {
        let repo = makeRepository()
        var template = makeTemplate(name: "Push Day")
        _ = try await repo.save(template)

        template.name = "Heavy Push Day"
        _ = try await repo.save(template)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].name == "Heavy Push Day")
    }

    // MARK: - delete

    @Test("delete removes template")
    func deleteRemoves() async throws {
        let repo = makeRepository()
        let template = makeTemplate()
        _ = try await repo.save(template)

        try await repo.delete(template)

        let all = try await repo.fetchAll()
        #expect(all.isEmpty)
    }

    @Test("delete non-existent template does not throw")
    func deleteNonExistent() async throws {
        let repo = makeRepository()
        let template = makeTemplate()
        try await repo.delete(template)
    }

    // MARK: - incrementUsage

    @Test("incrementUsage updates timesUsed and lastUsedAt")
    func incrementUsage() async throws {
        let repo = makeRepository()
        let template = makeTemplate(timesUsed: 0)
        _ = try await repo.save(template)

        #expect(template.lastUsedAt == nil)

        try await repo.incrementUsage(template.id)

        let all = try await repo.fetchAll()
        #expect(all[0].timesUsed == 1)
        #expect(all[0].lastUsedAt != nil)
    }

    @Test("incrementUsage called multiple times accumulates")
    func incrementUsageMultiple() async throws {
        let repo = makeRepository()
        let template = makeTemplate(timesUsed: 5)
        _ = try await repo.save(template)

        try await repo.incrementUsage(template.id)
        try await repo.incrementUsage(template.id)

        let all = try await repo.fetchAll()
        #expect(all[0].timesUsed == 7)
    }
}
