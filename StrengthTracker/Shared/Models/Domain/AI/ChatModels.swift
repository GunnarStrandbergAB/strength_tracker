import Foundation

public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

public enum MessageKind: String, Codable, Sendable {
    case text
    case draft
    case receipt
    case error
}

public enum DraftStatus: String, Codable, Sendable {
    case pending
    case accepted
    case discarded
}

/// One tool invocation shown as an activity chip in the chat.
public struct ToolActivity: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var label: String

    public init(id: UUID = UUID(), name: String, label: String) {
        self.id = id
        self.name = name
        self.label = label
    }
}

public struct ChatMessage: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var role: ChatRole
    public var kind: MessageKind
    public var text: String
    public var createdAt: Date
    /// JSON-encoded AIDraft for kind == .draft.
    public var draftJSON: String?
    public var draftStatus: DraftStatus?
    /// JSON-encoded AIReceipt for kind == .receipt.
    public var receiptJSON: String?
    /// Tool invocations that happened while producing this message.
    public var toolActivities: [ToolActivity]

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        kind: MessageKind = .text,
        text: String,
        createdAt: Date = Date(),
        draftJSON: String? = nil,
        draftStatus: DraftStatus? = nil,
        receiptJSON: String? = nil,
        toolActivities: [ToolActivity] = []
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.draftJSON = draftJSON
        self.draftStatus = draftStatus
        self.receiptJSON = receiptJSON
        self.toolActivities = toolActivities
    }
}

public struct ChatConversation: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    /// The xAI response id of the latest turn, for previous_response_id continuation.
    /// The server keeps stored responses for 30 days.
    public var lastResponseID: String?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastResponseID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastResponseID = lastResponseID
    }
}
