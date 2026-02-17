import Foundation

/// A notable insight or achievement surfaced by analytics.
public struct AnalyticsHighlight: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let type: HighlightType
    public let title: String
    public let detail: String

    public init(
        id: UUID = UUID(),
        type: HighlightType,
        title: String,
        detail: String
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
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
