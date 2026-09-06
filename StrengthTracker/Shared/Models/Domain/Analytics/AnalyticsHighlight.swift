import Foundation

/// A notable insight or achievement surfaced by analytics.
public struct AnalyticsHighlight: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let type: HighlightType
    public let title: String
    public let detail: String
    public let topic: String?
    public let computedAt: Date?
    public let validUntil: Date?
    public let isAction: Bool?
    public var destination: String { "strengthtracker://analytics?topic=\(topic ?? "overview")" }
    public var identity: String { topic ?? title }

    public init(
        id: UUID = UUID(),
        type: HighlightType,
        title: String,
        detail: String, topic: String? = nil, computedAt: Date = Date(), isAction: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.topic = topic
        self.computedAt = computedAt
        self.validUntil = computedAt.addingTimeInterval(6 * 3600)
        self.isAction = isAction
    }
}

/// The category of an analytics highlight.
public enum HighlightType: String, Codable, Sendable {
    case personalRecord
    case streak
    case milestone
    case improvement
    case warning
}
