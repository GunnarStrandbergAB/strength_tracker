import Foundation
@testable import StrengthTrackerShared

@MainActor
final class InMemoryProgressionPlanRepository: ProgressionPlanRepository {
    var plans: [ProgressionPlan] = []

    func fetchAll() async throws -> [ProgressionPlan] {
        plans
    }

    func fetchActive() async throws -> ProgressionPlan? {
        plans.filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }  // m14: deterministic ordering
            .first
    }

    func fetch(id: UUID) async throws -> ProgressionPlan? {
        plans.first { $0.id == id }
    }

    func save(_ plan: ProgressionPlan) async throws {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            // M18: Optimistic concurrency check
            if plans[index].updatedAt > plan.updatedAt {
                throw ProgressionPlanConcurrencyError.staleData(
                    planId: plan.id,
                    storedUpdatedAt: plans[index].updatedAt,
                    attemptedUpdatedAt: plan.updatedAt
                )
            }
            plans[index] = plan
        } else {
            plans.append(plan)
        }
    }

    func delete(_ plan: ProgressionPlan) async throws {
        plans.removeAll { $0.id == plan.id }
    }

    func updateStatus(_ planId: UUID, status: PlanStatus) async throws {
        guard let index = plans.firstIndex(where: { $0.id == planId }) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }
        plans[index].status = status
        plans[index].updatedAt = Date()  // M18
    }

    func addAdjustment(_ adjustment: PlanAdjustment, toPlan planId: UUID) async throws {
        guard let index = plans.firstIndex(where: { $0.id == planId }) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }
        plans[index].adjustments.append(adjustment)
        plans[index].updatedAt = Date()  // M18
    }

    func updateExercise(_ exercise: PlanExercise, inPlan planId: UUID) async throws {
        guard let planIndex = plans.firstIndex(where: { $0.id == planId }) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }
        if let exerciseIndex = plans[planIndex].exercises.firstIndex(where: { $0.id == exercise.id }) {
            plans[planIndex].exercises[exerciseIndex] = exercise
            plans[planIndex].updatedAt = Date()  // M18
        }
    }

    func updateBlock(_ block: TrainingBlock, inPlan planId: UUID) async throws {
        guard let planIndex = plans.firstIndex(where: { $0.id == planId }) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }
        if let blockIndex = plans[planIndex].blocks.firstIndex(where: { $0.id == block.id }) {
            plans[planIndex].blocks[blockIndex] = block
            plans[planIndex].updatedAt = Date()  // M18
        }
    }

    func markSessionCompleted(_ sessionId: UUID, workoutId: UUID, inPlan planId: UUID) async throws {
        guard let planIndex = plans.firstIndex(where: { $0.id == planId }) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }
        for blockIndex in plans[planIndex].blocks.indices {
            for weekIndex in plans[planIndex].blocks[blockIndex].weeks.indices {
                if let sessionIndex = plans[planIndex].blocks[blockIndex].weeks[weekIndex].sessions.firstIndex(where: { $0.id == sessionId }) {
                    plans[planIndex].blocks[blockIndex].weeks[weekIndex].sessions[sessionIndex].completedWorkoutId = workoutId
                    plans[planIndex].blocks[blockIndex].weeks[weekIndex].sessions[sessionIndex].completedAt = Date()
                    plans[planIndex].updatedAt = Date()  // M18
                    return
                }
            }
        }
    }
}
