import Foundation
@testable import StrengthTrackerShared

@MainActor
final class InMemoryTemplateRepository: TemplateRepository {
    private var storage: [UUID: WorkoutTemplate] = [:]

    func fetchAll() async throws -> [WorkoutTemplate] {
        Array(storage.values).sorted { $0.sortOrder < $1.sortOrder }
    }

    func save(_ template: WorkoutTemplate) async throws -> WorkoutTemplate {
        storage[template.id] = template
        return template
    }

    func delete(_ template: WorkoutTemplate) async throws {
        storage.removeValue(forKey: template.id)
    }

    func incrementUsage(_ templateId: UUID) async throws {
        guard var template = storage[templateId] else { return }
        template.timesUsed += 1
        template.lastUsedAt = Date()
        storage[templateId] = template
    }
}
