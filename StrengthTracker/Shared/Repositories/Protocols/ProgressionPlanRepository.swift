import Foundation

@MainActor
public protocol ProgressionPlanRepository: Sendable {
    func fetchAll() async throws -> [ProgressionPlan]
    func fetchActive() async throws -> ProgressionPlan?
    func fetch(id: UUID) async throws -> ProgressionPlan?
    func save(_ plan: ProgressionPlan) async throws
    func delete(_ plan: ProgressionPlan) async throws
    func updateStatus(_ planId: UUID, status: PlanStatus) async throws
    func addAdjustment(_ adjustment: PlanAdjustment, toPlan planId: UUID) async throws
    func updateExercise(_ exercise: PlanExercise, inPlan planId: UUID) async throws
    func updateBlock(_ block: TrainingBlock, inPlan planId: UUID) async throws
    func markSessionCompleted(_ sessionId: UUID, workoutId: UUID, inPlan planId: UUID) async throws
}
