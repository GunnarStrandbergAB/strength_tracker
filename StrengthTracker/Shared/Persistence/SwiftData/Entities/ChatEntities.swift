#if canImport(SwiftData)
import SwiftData
import Foundation

@Model
public final class ChatConversationEntity {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastResponseID: String?
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageEntity.conversation)
    public var messages: [ChatMessageEntity]

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        lastResponseID: String? = nil,
        messages: [ChatMessageEntity] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastResponseID = lastResponseID
        self.messages = messages
    }
}

@Model
public final class ChatMessageEntity {
    @Attribute(.unique) public var id: UUID
    public var role: String
    public var kind: String
    public var text: String
    public var createdAt: Date
    public var draftJSON: String?
    public var draftStatus: String?
    public var toolActivityJSON: String?
    public var conversation: ChatConversationEntity?

    public init(
        id: UUID,
        role: String,
        kind: String,
        text: String,
        createdAt: Date,
        draftJSON: String? = nil,
        draftStatus: String? = nil,
        toolActivityJSON: String? = nil
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.draftJSON = draftJSON
        self.draftStatus = draftStatus
        self.toolActivityJSON = toolActivityJSON
    }
}
#endif
