#if canImport(SwiftData)
import Foundation
import SwiftData

/// Maps between ProgressionPlanEntity (persistence) and ProgressionPlan (domain).
/// Uses JSON serialization for nested arrays (exercises, blocks, adjustments).
/// Tolerant decoding: missing optional fields default to nil (Review Fix #13).
public enum ProgressionPlanMapper {

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Current Schema Version

    /// v2: weeks are Monday-anchored calendar buckets of dated sessions (Model A).
    /// v1 plans (microcycle weeks) are migrated lazily on fetch by the repository.
    public static let currentSchemaVersion = 2

    // MARK: - Entity -> Domain

    /// Converts a ProgressionPlanEntity (SwiftData) to a ProgressionPlan (domain model).
    /// Returns nil if critical JSON decoding fails.
    public static func toDomain(_ entity: ProgressionPlanEntity) -> ProgressionPlan? {
        // Tolerant decoding: fallback to empty arrays on failure (M10), but log loudly —
        // an empty fallback here silently erases plan content from the UI.
        let exercises = decodeOrLog([PlanExercise].self, from: entity.exercisesJSON, label: "exercises", planId: entity.id)
        let blocks = decodeOrLog([TrainingBlock].self, from: entity.blocksJSON, label: "blocks", planId: entity.id)
        let adjustments = decodeOrLog([PlanAdjustment].self, from: entity.adjustmentsJSON, label: "adjustments", planId: entity.id)

        // Enum decoding with fallbacks for forward compatibility
        guard let status = PlanStatus(rawValue: entity.status),
              let trainingStatus = TrainingStatus(rawValue: entity.trainingStatus),
              let programType = ProgramType(rawValue: entity.programType),
              let primaryGoal = TrainingGoal(rawValue: entity.primaryGoal) else {
            return nil
        }

        let trainingDays: [Int]? = entity.trainingDaysJSON.flatMap {
            try? decoder.decode([Int].self, from: $0)
        }
        let deloadDays: [Int]? = entity.deloadDaysJSON.flatMap {
            try? decoder.decode([Int].self, from: $0)
        }
        let daySchedule: [DayScheduleEntry] = entity.dayScheduleJSON.flatMap {
            try? decoder.decode([DayScheduleEntry].self, from: $0)
        } ?? []
        let secondaryGoal: TrainingGoal? = entity.secondaryGoal.flatMap { TrainingGoal(rawValue: $0) }
        let creationSource: ProgressionPlan.PlanCreationSource? = entity.creationSource.flatMap {
            ProgressionPlan.PlanCreationSource(rawValue: $0)
        }

        return ProgressionPlan(
            id: entity.id,
            name: entity.name,
            status: status,
            trainingStatus: trainingStatus,
            programType: programType,
            primaryGoal: primaryGoal,
            secondaryGoal: secondaryGoal,
            weeklyFrequency: entity.weeklyFrequency,
            trainingDays: trainingDays,
            deloadDays: deloadDays,
            startDate: entity.startDate,
            targetEndDate: entity.targetEndDate,
            actualEndDate: entity.actualEndDate,
            exercises: exercises,
            blocks: blocks,
            adjustments: adjustments,
            daySchedule: daySchedule,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            notes: entity.notes,
            creationSource: creationSource
        )
    }

    // MARK: - Domain -> Entity

    /// Converts a ProgressionPlan (domain model) to a ProgressionPlanEntity (SwiftData).
    /// Throws if encoding fails — persisting an empty fallback would silently wipe plan content.
    public static func toEntity(_ plan: ProgressionPlan) throws -> ProgressionPlanEntity {
        let exercisesData = try encodeOrThrow(plan.exercises, label: "exercises")
        let blocksData = try encodeOrThrow(plan.blocks, label: "blocks")
        let adjustmentsData = try encodeOrThrow(plan.adjustments, label: "adjustments")
        let trainingDaysData: Data? = plan.trainingDays.flatMap { try? encoder.encode($0) }
        let deloadDaysData: Data? = plan.deloadDays.flatMap { try? encoder.encode($0) }
        let dayScheduleData: Data? = plan.daySchedule.isEmpty ? nil : (try? encoder.encode(plan.daySchedule))

        return ProgressionPlanEntity(
            id: plan.id,
            name: plan.name,
            status: plan.status.rawValue,
            trainingStatus: plan.trainingStatus.rawValue,
            programType: plan.programType.rawValue,
            primaryGoal: plan.primaryGoal.rawValue,
            secondaryGoal: plan.secondaryGoal?.rawValue,
            weeklyFrequency: plan.weeklyFrequency,
            trainingDaysJSON: trainingDaysData,
            deloadDaysJSON: deloadDaysData,
            startDate: plan.startDate,
            targetEndDate: plan.targetEndDate,
            actualEndDate: plan.actualEndDate,
            exercisesJSON: exercisesData,
            blocksJSON: blocksData,
            adjustmentsJSON: adjustmentsData,
            dayScheduleJSON: dayScheduleData,
            createdAt: plan.createdAt,
            updatedAt: plan.updatedAt,
            notes: plan.notes,
            creationSource: plan.creationSource?.rawValue,
            schemaVersion: currentSchemaVersion
        )
    }

    // MARK: - Update Entity In-Place

    /// Updates an existing ProgressionPlanEntity with values from a ProgressionPlan domain model.
    /// Throws if encoding fails — partial updates would otherwise wipe plan content.
    public static func updateEntity(_ entity: ProgressionPlanEntity, from plan: ProgressionPlan) throws {
        entity.name = plan.name
        entity.status = plan.status.rawValue
        entity.trainingStatus = plan.trainingStatus.rawValue
        entity.programType = plan.programType.rawValue
        entity.primaryGoal = plan.primaryGoal.rawValue
        entity.secondaryGoal = plan.secondaryGoal?.rawValue
        entity.weeklyFrequency = plan.weeklyFrequency
        entity.trainingDaysJSON = plan.trainingDays.flatMap { try? encoder.encode($0) }
        entity.deloadDaysJSON = plan.deloadDays.flatMap { try? encoder.encode($0) }
        entity.startDate = plan.startDate
        entity.targetEndDate = plan.targetEndDate
        entity.actualEndDate = plan.actualEndDate
        entity.exercisesJSON = try encodeOrThrow(plan.exercises, label: "exercises")
        entity.blocksJSON = try encodeOrThrow(plan.blocks, label: "blocks")
        entity.adjustmentsJSON = try encodeOrThrow(plan.adjustments, label: "adjustments")
        entity.dayScheduleJSON = plan.daySchedule.isEmpty ? nil : (try? encoder.encode(plan.daySchedule))
        entity.updatedAt = plan.updatedAt
        entity.notes = plan.notes
        entity.creationSource = plan.creationSource?.rawValue
        entity.schemaVersion = currentSchemaVersion
    }
    // MARK: - Encoding/Decoding Helpers

    /// Encodes a value, propagating the error so the save fails visibly instead of
    /// silently persisting empty data (M11 revised).
    private static func encodeOrThrow<T: Encodable>(_ value: T, label: String) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            assertionFailure("ProgressionPlanMapper: Failed to encode \(label): \(error)")
            throw error
        }
    }

    /// Decodes a stored array, logging on failure instead of silently dropping content.
    private static func decodeOrLog<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        label: String,
        planId: UUID
    ) -> T where T: ExpressibleByArrayLiteral {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            print("⚠️ ProgressionPlanMapper: failed to decode \(label) for plan \(planId) — content hidden until data is repaired: \(error)")
            return []
        }
    }
}
#endif
