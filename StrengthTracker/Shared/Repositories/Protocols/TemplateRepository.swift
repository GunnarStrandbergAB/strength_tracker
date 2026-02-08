import Foundation

@MainActor
public protocol TemplateRepository: Sendable {
    func fetchAll() async throws -> [WorkoutTemplate]
    func save(_ template: WorkoutTemplate) async throws -> WorkoutTemplate
    func delete(_ template: WorkoutTemplate) async throws
    func incrementUsage(_ templateId: UUID) async throws
}
