#if canImport(SwiftData)
import Foundation
import SwiftData

/// SwiftData-backed implementation of ProgressionPlanRepository.
/// Uses ProgressionPlanMapper for domain <-> entity conversion.
/// Implements optimistic concurrency via updatedAt comparison (Review Fix #14).
@MainActor
public final class SwiftDataProgressionPlanRepository: ProgressionPlanRepository, Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch

    public func fetchAll() async throws -> [ProgressionPlan] {
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap { entity in
            guard let plan = migratedDomainPlan(from: entity) else {
                print("\u{26A0}\u{FE0F} SwiftDataProgressionPlanRepository: dropping plan \(entity.id) (\(entity.name)) — failed to decode; it will not appear in the UI")
                return nil
            }
            return plan
        }
    }

    public func fetchActive() async throws -> ProgressionPlan? {
        let activeStatus = PlanStatus.active.rawValue
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.status == activeStatus },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]  // m14: deterministic ordering
        )
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return migratedDomainPlan(from: entity)
    }

    public func fetch(id: UUID) async throws -> ProgressionPlan? {
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        return migratedDomainPlan(from: entity)
    }

    // MARK: - Lazy v1 → v2 Migration

    /// Maps an entity to its domain plan, migrating v1 microcycle weeks to v2
    /// calendar-week buckets on the fly (Model A). Dates only sessions that have no
    /// scheduledDate (preserving user reschedules), then re-buckets. The migration is
    /// persisted best-effort without bumping `updatedAt` so optimistic-concurrency
    /// checks against in-flight domain copies are unaffected.
    private func migratedDomainPlan(from entity: ProgressionPlanEntity) -> ProgressionPlan? {
        guard var plan = ProgressionPlanMapper.toDomain(entity) else { return nil }
        if entity.schemaVersion < 2 {
            CalendarWeekBucketer.assignSequentialDates(
                to: &plan.blocks, startDate: plan.startDate, onlyMissing: true
            )
            plan.blocks = CalendarWeekBucketer.rebucket(plan.blocks)
            // updateEntity stamps schemaVersion = currentSchemaVersion and writes
            // entity.updatedAt = plan.updatedAt (unchanged here by design).
            try? ProgressionPlanMapper.updateEntity(entity, from: plan)
            try? modelContext.save()
        }
        return plan
    }

    // MARK: - Save (Upsert with Optimistic Concurrency)

    public func save(_ plan: ProgressionPlan) async throws {
        let planId = plan.id
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Optimistic concurrency: verify no concurrent modification
            if existing.updatedAt > plan.updatedAt {
                throw ProgressionPlanConcurrencyError.staleData(
                    planId: plan.id,
                    storedUpdatedAt: existing.updatedAt,
                    attemptedUpdatedAt: plan.updatedAt
                )
            }
            try ProgressionPlanMapper.updateEntity(existing, from: plan)
        } else {
            let entity = try ProgressionPlanMapper.toEntity(plan)
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    // MARK: - Delete

    public func delete(_ plan: ProgressionPlan) async throws {
        let planId = plan.id
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        )

        if let entity = try modelContext.fetch(descriptor).first {
            modelContext.delete(entity)
            try modelContext.save()
        }
    }

    // MARK: - Partial Updates

    public func updateStatus(_ planId: UUID, status: PlanStatus) async throws {
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        )

        guard let entity = try modelContext.fetch(descriptor).first else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }
        entity.status = status.rawValue
        entity.updatedAt = Date()
        try modelContext.save()
    }

    public func addAdjustment(_ adjustment: PlanAdjustment, toPlan planId: UUID) async throws {
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        )

        guard let entity = try modelContext.fetch(descriptor).first,
              var plan = ProgressionPlanMapper.toDomain(entity) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }

        plan.adjustments.append(adjustment)
        plan.updatedAt = Date()
        try ProgressionPlanMapper.updateEntity(entity, from: plan)
        try modelContext.save()
    }

    public func updateExercise(_ exercise: PlanExercise, inPlan planId: UUID) async throws {
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        )

        guard let entity = try modelContext.fetch(descriptor).first,
              var plan = ProgressionPlanMapper.toDomain(entity) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }

        if let index = plan.exercises.firstIndex(where: { $0.id == exercise.id }) {
            plan.exercises[index] = exercise
            plan.updatedAt = Date()
            try ProgressionPlanMapper.updateEntity(entity, from: plan)
            try modelContext.save()
        }
    }

    public func updateBlock(_ block: TrainingBlock, inPlan planId: UUID) async throws {
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        )

        guard let entity = try modelContext.fetch(descriptor).first,
              var plan = ProgressionPlanMapper.toDomain(entity) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }

        if let index = plan.blocks.firstIndex(where: { $0.id == block.id }) {
            plan.blocks[index] = block
            plan.updatedAt = Date()
            try ProgressionPlanMapper.updateEntity(entity, from: plan)
            try modelContext.save()
        }
    }

    public func markSessionCompleted(_ sessionId: UUID, workoutId: UUID, inPlan planId: UUID) async throws {
        let descriptor = FetchDescriptor<ProgressionPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        )

        guard let entity = try modelContext.fetch(descriptor).first,
              var plan = ProgressionPlanMapper.toDomain(entity) else {
            throw ProgressionPlanRepositoryError.planNotFound(planId)
        }

        for blockIndex in plan.blocks.indices {
            for weekIndex in plan.blocks[blockIndex].weeks.indices {
                if let sessionIndex = plan.blocks[blockIndex].weeks[weekIndex].sessions.firstIndex(where: { $0.id == sessionId }) {
                    plan.blocks[blockIndex].weeks[weekIndex].sessions[sessionIndex].completedWorkoutId = workoutId
                    plan.blocks[blockIndex].weeks[weekIndex].sessions[sessionIndex].completedAt = Date()
                    // Completion wins over a prior skip.
                    plan.blocks[blockIndex].weeks[weekIndex].sessions[sessionIndex].isSkipped = false
                    plan.blocks[blockIndex].weeks[weekIndex].sessions[sessionIndex].skippedAt = nil
                    plan.updatedAt = Date()
                    try ProgressionPlanMapper.updateEntity(entity, from: plan)
                    try modelContext.save()
                    return
                }
            }
        }
    }
}

// MARK: - Repository Error

public enum ProgressionPlanRepositoryError: Error, LocalizedError {
    case planNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .planNotFound(let id):
            return "Progression plan not found: \(id)"
        }
    }
}

// MARK: - Concurrency Error

public enum ProgressionPlanConcurrencyError: Error, LocalizedError {
    case staleData(planId: UUID, storedUpdatedAt: Date, attemptedUpdatedAt: Date)

    public var errorDescription: String? {
        switch self {
        case .staleData(let planId, let stored, let attempted):
            return "Optimistic concurrency conflict for plan \(planId): stored updatedAt \(stored) is newer than attempted \(attempted)"
        }
    }
}
#endif
