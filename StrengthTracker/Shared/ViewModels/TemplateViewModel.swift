import Foundation
import Observation

@MainActor
@Observable
public final class TemplateViewModel {
    public var templates: [WorkoutTemplate] = []
    public var selectedTemplate: WorkoutTemplate? = nil
    public var isLoading = false
    public var errorMessage: String? = nil

    private let templateRepository: any TemplateRepository
    private let exerciseRepository: any ExerciseRepository

    public init(templateRepository: any TemplateRepository, exerciseRepository: any ExerciseRepository) {
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
    }

    public func loadTemplates() async {
        isLoading = true
        errorMessage = nil
        do {
            templates = try await templateRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func saveTemplate(_ template: WorkoutTemplate) async {
        errorMessage = nil
        do {
            let saved = try await templateRepository.save(template)
            if let index = templates.firstIndex(where: { $0.id == saved.id }) {
                templates[index] = saved
            } else {
                templates.append(saved)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteTemplate(_ template: WorkoutTemplate) async {
        errorMessage = nil
        do {
            try await templateRepository.delete(template)
            templates.removeAll { $0.id == template.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createTemplate(name: String, exercises: [TemplateExercise]) async {
        let template = WorkoutTemplate(
            id: UUID(),
            name: name,
            notes: nil,
            sortOrder: templates.count,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: exercises
        )
        await saveTemplate(template)
    }
}
