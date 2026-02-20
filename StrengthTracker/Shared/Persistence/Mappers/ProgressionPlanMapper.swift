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

    public static let currentSchemaVersion = 1

    // MARK: - Entity -> Domain

    /// Converts a ProgressionPlanEntity (SwiftData) to a ProgressionPlan (domain model).
    /// Returns nil if critical JSON decoding fails.
    public static func toDomain(_ entity: ProgressionPlanEntity) -> ProgressionPlan? {
        // Tolerant decoding: fallback to empty arrays on failure (M10)
        let exercises = (try? decoder.decode([PlanExercise].self, from: entity.exercisesJSON)) ?? []
        let blocks = (try? decoder.decode([TrainingBlock].self, from: entity.blocksJSON)) ?? []
        let adjustments = (try? decoder.decode([PlanAdjustment].self, from: entity.adjustmentsJSON)) ?? []

        // Enum decoding with fallbacks for forward compatibility
        guard let status = PlanStatus(rawValue: entity.status),
              let trainingStatus = TrainingStatus(rawValue: entity.trainingStatus),
              let programType = ProgramType(rawValue: entity.programType),
              let primaryGoal = TrainingGoal(rawValue: entity.primaryGoal) else {
            return nil
        }

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
            startDate: entity.startDate,
            targetEndDate: entity.targetEndDate,
            actualEndDate: entity.actualEndDate,
            exercises: exercises,
            blocks: blocks,
            adjustments: adjustments,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            notes: entity.notes,
            creationSource: creationSource
        )
    }

    // MARK: - Domain -> Entity

    /// Converts a ProgressionPlan (domain model) to a ProgressionPlanEntity (SwiftData).
    public static func toEntity(_ plan: ProgressionPlan) -> ProgressionPlanEntity {
        let exercisesData = encodeOrWarn(plan.exercises, label: "exercises")
        let blocksData = encodeOrWarn(plan.blocks, label: "blocks")
        let adjustmentsData = encodeOrWarn(plan.adjustments, label: "adjustments")

        return ProgressionPlanEntity(
            id: plan.id,
            name: plan.name,
            status: plan.status.rawValue,
            trainingStatus: plan.trainingStatus.rawValue,
            programType: plan.programType.rawValue,
            primaryGoal: plan.primaryGoal.rawValue,
            secondaryGoal: plan.secondaryGoal?.rawValue,
            weeklyFrequency: plan.weeklyFrequency,
            startDate: plan.startDate,
            targetEndDate: plan.targetEndDate,
            actualEndDate: plan.actualEndDate,
            exercisesJSON: exercisesData,
            blocksJSON: blocksData,
            adjustmentsJSON: adjustmentsData,
            createdAt: plan.createdAt,
            updatedAt: plan.updatedAt,
            notes: plan.notes,
            creationSource: plan.creationSource?.rawValue,
            schemaVersion: currentSchemaVersion
        )
    }

    // MARK: - Update Entity In-Place

    /// Updates an existing ProgressionPlanEntity with values from a ProgressionPlan domain model.
    public static func updateEntity(_ entity: ProgressionPlanEntity, from plan: ProgressionPlan) {
        entity.name = plan.name
        entity.status = plan.status.rawValue
        entity.trainingStatus = plan.trainingStatus.rawValue
        entity.programType = plan.programType.rawValue
        entity.primaryGoal = plan.primaryGoal.rawValue
        entity.secondaryGoal = plan.secondaryGoal?.rawValue
        entity.weeklyFrequency = plan.weeklyFrequency
        entity.startDate = plan.startDate
        entity.targetEndDate = plan.targetEndDate
        entity.actualEndDate = plan.actualEndDate
        entity.exercisesJSON = encodeOrWarn(plan.exercises, label: "exercises")
        entity.blocksJSON = encodeOrWarn(plan.blocks, label: "blocks")
        entity.adjustmentsJSON = encodeOrWarn(plan.adjustments, label: "adjustments")
        entity.updatedAt = plan.updatedAt
        entity.notes = plan.notes
        entity.creationSource = plan.creationSource?.rawValue
        entity.schemaVersion = currentSchemaVersion
    }
    // MARK: - Encoding Helper

    /// Encodes a value, logging a warning on failure instead of silently returning empty data (M11).
    private static func encodeOrWarn<T: Encodable>(_ value: T, label: String) -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            assertionFailure("ProgressionPlanMapper: Failed to encode \(label): \(error)")
            return Data("[]".utf8)
        }
    }
}
#endif
