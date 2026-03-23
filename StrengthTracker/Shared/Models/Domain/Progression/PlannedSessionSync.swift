import Foundation

/// Lightweight DTO for syncing planned sessions from iPhone to Watch via WatchConnectivity.
/// iPhone builds these from the active plan's current week; Watch consumes them as-is.
public struct PlannedSessionSync: Identifiable, Codable, Sendable {
    public let id: UUID          // PlannedSession.id
    public let planId: UUID
    public let planName: String
    public let sessionLabel: String  // e.g. "Push A"
    public let weekLabel: String     // e.g. "Week 2"
    public let blockName: String?    // e.g. "Strength Phase"
    public let isDeload: Bool
    public let template: WorkoutTemplate

    public init(
        id: UUID,
        planId: UUID,
        planName: String,
        sessionLabel: String,
        weekLabel: String,
        blockName: String?,
        isDeload: Bool = false,
        template: WorkoutTemplate
    ) {
        self.id = id
        self.planId = planId
        self.planName = planName
        self.sessionLabel = sessionLabel
        self.weekLabel = weekLabel
        self.blockName = blockName
        self.isDeload = isDeload
        self.template = template
    }

    // Custom decoding for backward compatibility — existing JSON without isDeload decodes as false
    private enum CodingKeys: String, CodingKey {
        case id, planId, planName, sessionLabel, weekLabel, blockName, isDeload, template
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        planId = try container.decode(UUID.self, forKey: .planId)
        planName = try container.decode(String.self, forKey: .planName)
        sessionLabel = try container.decode(String.self, forKey: .sessionLabel)
        weekLabel = try container.decode(String.self, forKey: .weekLabel)
        blockName = try container.decodeIfPresent(String.self, forKey: .blockName)
        isDeload = try container.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
        template = try container.decode(WorkoutTemplate.self, forKey: .template)
    }
}
