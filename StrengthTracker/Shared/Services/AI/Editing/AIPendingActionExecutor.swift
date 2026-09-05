import Foundation

public extension ProgressionPlan {
    /// A session and its week, by session id.
    func locateSession(id: UUID) -> (session: PlannedSession, week: TrainingWeek)? {
        for block in blocks {
            for week in block.weeks {
                if let session = week.sessions.first(where: { $0.id == id }) {
                    return (session, week)
                }
            }
        }
        return nil
    }
}

/// Runs a confirmed `AIPendingAction` through the same coordinator/editor code
/// the tools use. Wired to `AIChatViewModel.onSaveDraft` for `.action` drafts.
@MainActor
public final class AIPendingActionExecutor {
    private let coordinator: WorkoutSessionCoordinator
    private let resolver: WorkoutEditorResolver
    private let templateRepository: any TemplateRepository
    private let progressionPlanViewModel: ProgressionPlanViewModel

    public init(
        coordinator: WorkoutSessionCoordinator,
        resolver: WorkoutEditorResolver,
        templateRepository: any TemplateRepository,
        progressionPlanViewModel: ProgressionPlanViewModel
    ) {
        self.coordinator = coordinator
        self.resolver = resolver
        self.templateRepository = templateRepository
        self.progressionPlanViewModel = progressionPlanViewModel
    }

    public func execute(_ action: AIPendingAction) async throws {
        let vm = coordinator.workoutViewModel
        switch action.kind {
        case .startWorkout(let name, let templateID, let plannedSessionID, let plannedPlanID, let isDeload, let replacingWorkoutID):
            if let current = vm.currentWorkout, vm.isActive, current.id != replacingWorkoutID {
                throw AIToolError("The active workout changed since this was proposed. Ask again.")
            }
            var template: WorkoutTemplate?
            if let plannedSessionID {
                if progressionPlanViewModel.activePlan == nil {
                    await progressionPlanViewModel.loadActivePlan()
                }
                guard let plan = progressionPlanViewModel.activePlan,
                      let located = plan.locateSession(id: plannedSessionID) else {
                    throw AIToolError("The planned session no longer exists.")
                }
                template = await progressionPlanViewModel.prepareSessionTemplate(for: located.session)
            } else if let templateID {
                template = try await templateRepository.fetchAll().first { $0.id == templateID }
                guard template != nil else { throw AIToolError("The template no longer exists.") }
            }
            try await coordinator.start(
                .init(
                    name: name,
                    template: template,
                    isDeload: isDeload,
                    plannedSessionId: plannedSessionID,
                    plannedPlanId: plannedPlanID
                ),
                replacingActive: true
            )

        case .cancelWorkout(let workoutID):
            guard vm.isActive, vm.currentWorkout?.id == workoutID else {
                throw AIToolError("That workout is no longer active.")
            }
            await coordinator.cancel()

        case .removeExercise(let workoutID, let exerciseID):
            let editor = try await resolver.resolve(workoutID: workoutID)
            try await editor.removeExercise(id: exerciseID)
            await editor.commit()

        case .removeSet(let workoutID, let exerciseID, let setID):
            let editor = try await resolver.resolve(workoutID: workoutID)
            try await editor.removeSet(exerciseId: exerciseID, setId: setID)
            await editor.commit()
        }
    }
}
