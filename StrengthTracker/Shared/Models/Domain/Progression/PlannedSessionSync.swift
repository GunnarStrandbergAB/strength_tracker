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
    public let template: WorkoutTemplate

    public init(
        id: UUID,
        planId: UUID,
        planName: String,
        sessionLabel: String,
        weekLabel: String,
        blockName: String?,
        template: WorkoutTemplate
    ) {
        self.id = id
        self.planId = planId
        self.planName = planName
        self.sessionLabel = sessionLabel
        self.weekLabel = weekLabel
        self.blockName = blockName
        self.template = template
    }
}
