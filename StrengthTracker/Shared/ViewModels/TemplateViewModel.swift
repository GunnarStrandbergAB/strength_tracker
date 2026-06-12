import Foundation
import Observation

@MainActor
@Observable
public final class TemplateViewModel {
    public var templates: [WorkoutTemplate] = []
    public var selectedTemplate: WorkoutTemplate? = nil
    public var isLoading = false
    public var errorMessage: String? = nil

    public var userTemplates: [WorkoutTemplate] { templates.filter { $0.isCustom } }
    public var libraryTemplates: [WorkoutTemplate] { templates.filter { !$0.isCustom } }

    private let templateRepository: any TemplateRepository
    private let exerciseRepository: any ExerciseRepository
    private let connectivityManager: ConnectivityManager?
    public let userPreferencesService: UserPreferencesService?

    public var weightUnit: WeightUnit { userPreferencesService?.weightUnit ?? .kg }

    public init(
        templateRepository: any TemplateRepository,
        exerciseRepository: any ExerciseRepository,
        connectivityManager: ConnectivityManager? = nil,
        userPreferencesService: UserPreferencesService? = nil
    ) {
        self.templateRepository = templateRepository
        self.exerciseRepository = exerciseRepository
        self.connectivityManager = connectivityManager
        self.userPreferencesService = userPreferencesService
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
            syncTemplatesToWatch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteTemplate(_ template: WorkoutTemplate) async {
        errorMessage = nil
        do {
            try await templateRepository.delete(template)
            templates.removeAll { $0.id == template.id }
            syncTemplatesToWatch()
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

    /// Copies a library template as a new user-owned template
    public func addLibraryTemplate(_ template: WorkoutTemplate) async {
        let copiedExercises = template.exercises.map { ex in
            TemplateExercise(
                id: UUID(),
                exercise: ex.exercise,
                order: ex.order,
                supersetGroup: ex.supersetGroup,
                notes: ex.notes,
                restTimerSeconds: ex.restTimerSeconds,
                targetSets: ex.targetSets,
                targetReps: ex.targetReps,
                targetWeight: ex.targetWeight,
                targetDurationSeconds: ex.targetDurationSeconds,
                targetDistanceMeters: ex.targetDistanceMeters,
                setTargets: ex.setTargets,
                isWarmUp: ex.isWarmUp
            )
        }
        let copy = WorkoutTemplate(
            id: UUID(),
            name: template.name,
            notes: template.notes,
            sortOrder: userTemplates.count,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: copiedExercises,
            isCustom: true
        )
        await saveTemplate(copy)
    }

    /// Checks if a library template has already been added to user templates (by name match)
    public func isLibraryTemplateAdded(_ template: WorkoutTemplate) -> Bool {
        userTemplates.contains { $0.name == template.name }
    }

    #if os(iOS)
    private func syncTemplatesToWatch() {
        connectivityManager?.syncTemplates(userTemplates)
    }
    #else
    private func syncTemplatesToWatch() {}
    #endif
}
